import Foundation
import Security

/// Keeps the original account so existing installations retain their API key.
actor KeychainStore {
    static let shared = KeychainStore()
    private let service = "com.chulan.renqingadvisor"
    private let account = "deepseek-api-key"

    private init() {}

    func save(apiKey: String) throws {
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attrs = query
            attrs[kSecValueData as String] = data
            let added = SecItemAdd(attrs as CFDictionary, nil)
            guard added == errSecSuccess else {
                throw KeychainError(status: added, operation: "保存")
            }
        } else if status != errSecSuccess {
            throw KeychainError(status: status, operation: "保存")
        }
    }

    func loadAPIKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status, operation: "读取") }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: errSecDecode, operation: "读取")
        }
        return key
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus
        let operation: String
        var errorDescription: String? {
            "钥匙串密钥\(operation)失败（\(status)）。请检查钥匙串访问权限后重试，已有密钥不会被删除。"
        }
    }
}
