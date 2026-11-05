import Foundation
import Security

actor CredentialStore {
    static let shared = CredentialStore()

    struct Loaded: Sendable {
        let apiKey: String?
        let notice: String?
    }

    private enum LegacyAction: String, Codable {
        case migrate, clear
    }

    private struct Credentials: Codable, Equatable {
        let apiKey: String
        var legacyAction: LegacyAction?
    }

    private let service = "com.chulan.renqingadvisor"
    private let account = "deepseek-api-key"
    private var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(service, isDirectory: true)
            .appendingPathComponent("credentials.json")
    }

    private init() {}

    func load() throws -> Loaded {
        if let credentials = try readCredentials() {
            return Loaded(apiKey: credentials.apiKey, notice: finishLegacyAction(credentials))
        }
        guard let key = try readLegacyAPIKey() else { return Loaded(apiKey: nil, notice: nil) }
        let credentials = Credentials(apiKey: key, legacyAction: .migrate)
        try persist(credentials)
        return Loaded(apiKey: key, notice: finishLegacyAction(credentials))
    }

    func save(apiKey: String) throws -> String? {
        let credentials = Credentials(apiKey: apiKey, legacyAction: .clear)
        try persist(credentials)
        return finishLegacyAction(credentials)
    }

    func clearAPIKey() throws -> String? {
        // Keep an empty local record so a failed legacy cleanup cannot restore the old key.
        try save(apiKey: "")
    }

    private func readCredentials() throws -> Credentials? {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(Credentials.self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            throw StorageError(message: "本机密钥文件读取失败，原文件已保留。请检查应用数据目录的权限；文件损坏时可通过“清除密钥”重置。")
        }
    }

    private func persist(_ credentials: Credentials) throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try JSONEncoder().encode(credentials).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            guard try readCredentials() == credentials else {
                throw StorageError(message: "本机密钥文件回读校验失败。")
            }
        } catch {
            throw StorageError(message: "本机密钥保存或回读校验失败。请检查应用数据目录的空间与权限后重试。")
        }
    }

    private func finishLegacyAction(_ credentials: Credentials) -> String? {
        guard let action = credentials.legacyAction else { return nil }
        let result = credentials.apiKey.isEmpty ? "本机密钥已清空" : "密钥已保存到本机"
        do {
            if action == .migrate, let oldKey = try readLegacyAPIKey(), oldKey != credentials.apiKey
            {
                return "本机密钥已保留，但旧钥匙串记录发生了变化，暂未清理。请退出旧版 Jeff，确认所需密钥后重新保存或清除密钥。"
            }
            try deleteLegacyAPIKey()
        } catch {
            return "\(result)，旧钥匙串清理尚未完成。\(error.localizedDescription) 点击“重新读取”重试。"
        }
        var completed = credentials
        completed.legacyAction = nil
        do {
            try persist(completed)
            return nil
        } catch {
            return "\(result)，旧钥匙串已清理，但本机清理状态更新失败。\(error.localizedDescription) 点击“重新读取”重试。"
        }
    }

    private var legacyQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func readLegacyAPIKey() throws -> String? {
        var query = legacyQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status, operation: "读取") }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: errSecDecode, operation: "读取")
        }
        return key
    }

    private func deleteLegacyAPIKey() throws {
        let status = SecItemDelete(legacyQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status, operation: "清理")
        }
    }

    private struct StorageError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus
        let operation: String
        var errorDescription: String? {
            "旧钥匙串密钥\(operation)失败（\(status)）。请检查钥匙串访问权限后重试。"
        }
    }
}
