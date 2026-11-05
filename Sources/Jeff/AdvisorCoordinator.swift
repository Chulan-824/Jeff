import AppKit
import Carbon
import Foundation
import SwiftUI

@MainActor
final class AdvisorCoordinator: ObservableObject {
    static let shared = AdvisorCoordinator()

    @Published var selectedText = ""
    @Published var output = ""
    @Published var isStreaming = false
    @Published var errorMessage: String?
    @Published var needsAccessibilityPermission = false
    @Published private(set) var sourceApp = "手动输入"
    @Published private(set) var recordID: UUID?

    private var panel: AdvisorPanel?
    private var hud: AdvisorPanel?
    private var streamTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var requestID = UUID()
    private var isQuiet = false
    private var isCapturing = false

    static let hotkeySelectionKey = "hotkey.selection"
    static let hotkeySnipKey = "hotkey.snip"

    var selectionShortcut: RecordedShortcut? {
        RecordedShortcut.load(
            Self.hotkeySelectionKey,
            default: RecordedShortcut(keyCode: 0x02, modifiers: UInt32(optionKey | cmdKey)))
    }
    var snipShortcut: RecordedShortcut? {
        RecordedShortcut.load(
            Self.hotkeySnipKey,
            default: RecordedShortcut(keyCode: 0x01, modifiers: UInt32(optionKey | cmdKey)))
    }

    func applyHotkeys() {
        GlobalHotKey.shared.unregister(id: 1)
        GlobalHotKey.shared.unregister(id: 2)
        if let shortcut = selectionShortcut {
            GlobalHotKey.shared.register(
                id: 1, keyCode: shortcut.keyCode, modifiers: shortcut.modifiers
            ) {
                AdvisorCoordinator.shared.trigger()
            }
        }
        if let shortcut = snipShortcut {
            GlobalHotKey.shared.register(
                id: 2, keyCode: shortcut.keyCode, modifiers: shortcut.modifiers
            ) {
                AdvisorCoordinator.shared.triggerSnip()
            }
        }
        objectWillChange.send()
    }

    func saveSelectionShortcut(_ shortcut: RecordedShortcut?) {
        RecordedShortcut.save(shortcut, forKey: Self.hotkeySelectionKey)
        applyHotkeys()
    }
    func saveSnipShortcut(_ shortcut: RecordedShortcut?) {
        RecordedShortcut.save(shortcut, forKey: Self.hotkeySnipKey)
        applyHotkeys()
    }

    private func frontmostApp() -> String {
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.bundleIdentifier != Bundle.main.bundleIdentifier
        else { return "未知应用" }
        return app.localizedName ?? "未知应用"
    }

    func triggerSnip() {
        guard !isCapturing else { return }
        let source = frontmostApp()
        cancelStreaming()
        let captureID = requestID
        panel?.orderOut(nil)
        hud?.orderOut(nil)
        isCapturing = true
        SnipController.shared.start { [weak self] text in
            guard let self else { return }
            self.isCapturing = false
            guard self.requestID == captureID else { return }
            self.begin(text: text ?? "", source: source)
            if let text, !text.isEmpty {
                self.startStreaming()
            } else {
                self.errorMessage = "未识别到文字，可能已取消、区域无文本或缺少屏幕录制权限。"
            }
        }
    }

    func trigger() {
        let source = frontmostApp()
        needsAccessibilityPermission = !SelectionCapture.isTrusted(prompt: false)
        guard let text = SelectionCapture.grabSelectedText(),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            begin(text: "", source: source)
            errorMessage =
                needsAccessibilityPermission
                ? "无法取词。请授权辅助功能，或使用剪贴板分析。"
                : "没有捕获到选中内容，请先划选文字，或使用剪贴板分析。"
            return
        }
        begin(text: text, source: source)
        startStreaming()
    }

    func triggerClipboard() {
        let source = frontmostApp()
        guard let text = NSPasteboard.general.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            begin(text: "", source: "剪贴板")
            errorMessage = "剪贴板中没有文字，请先复制文本。"
            return
        }
        begin(text: text, source: "剪贴板 · 触发时应用：\(source)")
        startStreaming()
    }

    func showInput() {
        begin(text: "", source: "手动输入", quiet: false)
    }

    private func begin(text: String, source: String, quiet: Bool? = nil) {
        cancelStreaming()
        selectedText = text
        sourceApp = source
        output = ""
        recordID = nil
        errorMessage = nil
        isQuiet = quiet ?? UserDefaults.standard.bool(forKey: "quietMode")
        if isQuiet {
            panel?.orderOut(nil)
            ensureHUD().showNearMouse(activate: false)
        } else {
            showResult()
        }
    }

    func showResult() {
        hideTask?.cancel()
        hud?.orderOut(nil)
        isQuiet = false
        ensurePanel().showNearMouse()
    }

    private func cancelStreaming() {
        requestID = UUID()
        streamTask?.cancel()
        hideTask?.cancel()
        isStreaming = false
    }

    func startStreaming() {
        cancelStreaming()
        output = ""
        errorMessage = nil
        recordID = nil
        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请先输入或选中需要分析的内容。"
            return
        }
        guard UserDefaults.standard.object(forKey: "serviceEnabled") as? Bool ?? true else {
            errorMessage = "分析服务已停用，请在服务设置中开启。"
            return
        }
        let model = UserDefaults.standard.string(forKey: "model") ?? "deepseek-chat"
        let baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? "https://api.deepseek.com"
        let id = requestID
        let input = selectedText
        let source = sourceApp
        let savesHistory = UserDefaults.standard.bool(forKey: "saveHistory")
        isStreaming = true
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let apiKey = try await KeychainStore.shared.loadAPIKey() ?? ""
                guard !Task.isCancelled, self.requestID == id else { return }
                let client = AIClient(apiKey: apiKey, model: model, baseURL: baseURL)
                _ = try client.validatedEndpoint()
                for try await chunk in client.stream(
                    systemPrompt: SkillStore.systemPrompt(), userContent: input)
                {
                    guard !Task.isCancelled, self.requestID == id else { return }
                    self.output += chunk
                }
                guard !Task.isCancelled, self.requestID == id else { return }
                guard !self.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw AIClient.ClientError.invalidResponse
                }
                if savesHistory && UserDefaults.standard.bool(forKey: "saveHistory") {
                    let store = HistoryStore.shared
                    store.add(input: input, output: self.output, sourceApp: source, model: model)
                    if let error = store.errorMessage {
                        self.errorMessage = error
                    } else {
                        self.recordID = store.records.first?.id
                    }
                }
                if UserDefaults.standard.bool(forKey: "autoCopyOutput") { self.copyOutput() }
                if self.isQuiet && self.errorMessage == nil {
                    self.hideTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(12))
                        guard !Task.isCancelled else { return }
                        self?.hud?.orderOut(nil)
                    }
                }
            } catch {
                guard !Task.isCancelled, self.requestID == id else { return }
                self.errorMessage = error.localizedDescription
            }
            guard self.requestID == id else { return }
            self.isStreaming = false
        }
    }

    func regenerate() { startStreaming() }

    func restore(_ record: AdviceRecord) {
        begin(text: record.input, source: record.sourceApp, quiet: false)
        output = record.output
        recordID = record.id
    }

    func dismiss() {
        cancelStreaming()
        panel?.orderOut(nil)
        hud?.orderOut(nil)
    }

    func copyOutput() { copy(output) }

    func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func ensurePanel() -> AdvisorPanel {
        if let panel { return panel }
        let panel = AdvisorPanel(
            contentView: NSHostingView(rootView: AdvisorView(coordinator: self)))
        panel.onClose = { [weak self] in self?.cancelStreaming() }
        self.panel = panel
        return panel
    }

    private func ensureHUD() -> AdvisorPanel {
        if let hud { return hud }
        let hud = AdvisorPanel(
            contentView: NSHostingView(rootView: AdvisorHUD(coordinator: self)),
            size: NSSize(width: 360, height: 220))
        hud.onClose = { [weak self] in self?.cancelStreaming() }
        self.hud = hud
        return hud
    }
}
