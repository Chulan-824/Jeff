import Foundation

struct AdviceRecord: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var input: String
    var output: String
    var sourceApp: String
    var model: String
    var isFavorite = false
    var captureKind: CaptureKind?
    var action: AdviceAction?
    var context: AdviceContext?
    var result: AdviceResult?

    var taskDescription: String {
        guard let action else { return "旧版结果" }
        let title = action == .auto ? "自动 → \(result?.action.title ?? "处理")" : action.title
        return title + " · " + (context?.scene.title ?? "通用")
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    @Published private(set) var records: [AdviceRecord] = []
    @Published private(set) var errorMessage: String?
    private var loadFailed = false

    private var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.chulan.renqingadvisor", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    private init() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            records = try JSONDecoder().decode([AdviceRecord].self, from: Data(contentsOf: fileURL))
        } catch {
            loadFailed = true
            errorMessage = "历史记录读取失败，原文件已保留。请先备份 history.json，再处理文件或清空记录。"
        }
    }

    @discardableResult
    func add(_ record: AdviceRecord) -> Bool {
        guard !loadFailed else { return false }
        return persist(limited([record] + records))
    }

    func toggleFavorite(_ id: UUID) {
        var updated = records
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].isFavorite.toggle()
        persist(limited(updated))
    }

    func remove(_ id: UUID) { persist(records.filter { $0.id != id }) }

    func clear() {
        if persist([]) { loadFailed = false }
    }

    // Keep favorites while bounding ordinary history to the latest 100 results.
    private func limited(_ records: [AdviceRecord]) -> [AdviceRecord] {
        var ordinaryCount = 0
        return records.filter { record in
            if record.isFavorite { return true }
            ordinaryCount += 1
            return ordinaryCount <= 100
        }
    }

    @discardableResult
    private func persist(_ updated: [AdviceRecord]) -> Bool {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try JSONEncoder().encode(updated).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            records = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = "历史记录保存失败，请检查磁盘空间和目录权限。当前结果仍可复制。"
            return false
        }
    }
}
