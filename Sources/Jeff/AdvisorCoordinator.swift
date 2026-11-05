import AppKit
import Carbon
import Foundation
import SwiftUI

@MainActor
final class AdvisorCoordinator: ObservableObject {
    static let shared = AdvisorCoordinator()

    @Published private(set) var selectedText = ""
    @Published private(set) var action: AdviceAction = .auto
    @Published private(set) var context = AdviceContext()
    @Published private(set) var result: AdviceResult?
    @Published private(set) var legacyOutput = ""
    @Published private(set) var previousResult: AdviceRecord?
    @Published private(set) var isResultComplete = false
    @Published private(set) var isStreaming = false
    @Published var errorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published var needsAccessibilityPermission = false
    @Published private(set) var sourceApp = "手动输入"
    @Published private(set) var captureKind: CaptureKind? = .manual
    @Published private(set) var recordID: UUID?
    @Published private(set) var taskID = UUID()

    private var panel: AdvisorPanel?
    private var hud: AdvisorPanel?
    private var streamTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var requestID = UUID()
    private var lastCompleted: AdviceRecord?
    private var isQuiet = false
    private var isCapturing = false

    var output: String { result?.fullText ?? legacyOutput }
    var primaryText: String { result?.content ?? legacyOutput }
    var sourceDescription: String {
        guard let captureKind, captureKind != .manual else { return sourceApp }
        return sourceApp + " · " + captureKind.title
    }
    var canCopyPrimary: Bool {
        isResultComplete && !isStreaming && result?.needsContext != true && !primaryText.isEmpty
    }
    var copyTitle: String { result?.copyTitle ?? "复制完整结果" }
    var actionDescription: String {
        if !legacyOutput.isEmpty { return "旧版结果 · 可选择动作重新处理" }
        if action != .auto { return "本次按「\(action.title)」处理" }
        if let result { return "本次按「\(result.action.title)」处理 · 自动判断" }
        return isStreaming ? "正在判断本次用途…" : "自动判断，也可手动选择动作"
    }
    var progressTitle: String {
        guard isStreaming else { return "" }
        return result.map { "正在\($0.action.title)…" }
            ?? (action == .auto ? "正在判断用途…" : "正在\(action.title)…")
    }

    static let hotkeySelectionKey = "hotkey.selection"
    static let hotkeySnipKey = "hotkey.snip"
    private static let defaultSelectionShortcut = RecordedShortcut(
        keyCode: 0x02, modifiers: UInt32(optionKey))
    private static let defaultSnipShortcut = RecordedShortcut(
        keyCode: 0x01, modifiers: UInt32(optionKey))

    var selectionShortcut: RecordedShortcut? {
        RecordedShortcut.load(
            Self.hotkeySelectionKey, default: Self.defaultSelectionShortcut)
    }
    var snipShortcut: RecordedShortcut? {
        RecordedShortcut.load(
            Self.hotkeySnipKey, default: Self.defaultSnipShortcut)
    }

    func applyHotkeys() {
        GlobalHotKey.shared.unregister(id: 1)
        GlobalHotKey.shared.unregister(id: 2)
        for (key, replacement, previousModifiers) in [
            (
                Self.hotkeySelectionKey, Self.defaultSelectionShortcut,
                [UInt32(optionKey | cmdKey), UInt32(controlKey | optionKey | cmdKey)]
            ),
            (Self.hotkeySnipKey, Self.defaultSnipShortcut, [UInt32(optionKey | cmdKey)]),
        ] {
            guard let shortcut = RecordedShortcut.load(key) else { continue }
            if shortcut.conflictsWithDock
                || (shortcut.keyCode == replacement.keyCode
                    && previousModifiers.contains(shortcut.modifiers))
            {
                RecordedShortcut.save(replacement, forKey: key)
            }
        }
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
        guard shortcut?.conflictsWithDock != true else { return }
        RecordedShortcut.save(shortcut, forKey: Self.hotkeySelectionKey)
        applyHotkeys()
    }
    func saveSnipShortcut(_ shortcut: RecordedShortcut?) {
        guard shortcut?.conflictsWithDock != true else { return }
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
        let sourceApplication = NSWorkspace.shared.frontmostApplication
        let panelWasVisible = panel?.isVisible == true
        let hudWasVisible = hud?.isVisible == true
        cancelStreaming()
        let captureID = requestID
        panel?.orderOut(nil)
        hud?.orderOut(nil)
        isCapturing = true
        SnipController.shared.start { [weak self] outcome in
            guard let self else { return }
            self.isCapturing = false
            guard self.requestID == captureID else { return }
            switch outcome {
            case .cancelled:
                sourceApplication?.activate(options: [])
                if panelWasVisible { self.panel?.showNearMouse(activate: false) }
                if hudWasVisible { self.hud?.showNearMouse(activate: false) }
            case .text(let text):
                self.begin(text: text, source: source, kind: .screenshot)
                self.startStreaming()
            case .failed(let message):
                self.begin(text: "", source: source, kind: .screenshot)
                self.errorMessage = message
            }
        }
    }

    func trigger() {
        let source = frontmostApp()
        needsAccessibilityPermission = !SelectionCapture.isTrusted(prompt: false)
        guard let text = SelectionCapture.grabSelectedText(),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            begin(text: "", source: source, kind: .selection)
            errorMessage =
                needsAccessibilityPermission
                ? "无法取词。请授权辅助功能，或使用剪贴板处理。"
                : "没有捕获到选中内容，请先划选文字，或使用剪贴板处理。"
            return
        }
        begin(text: text, source: source, kind: .selection)
        startStreaming()
    }

    func triggerClipboard() {
        let source = frontmostApp()
        guard let text = NSPasteboard.general.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            begin(text: "", source: source, kind: .clipboard)
            errorMessage = "剪贴板中没有文字，请先复制文本。"
            return
        }
        begin(text: text, source: source, kind: .clipboard)
        startStreaming()
    }

    func showInput() { begin(text: "", source: "手动输入", kind: .manual, quiet: false) }

    private func begin(text: String, source: String, kind: CaptureKind, quiet: Bool? = nil) {
        cancelStreaming()
        taskID = UUID()
        selectedText = text
        sourceApp = source
        captureKind = kind
        action = .auto
        context = AdviceContext()
        result = nil
        legacyOutput = ""
        previousResult = nil
        lastCompleted = nil
        isResultComplete = false
        recordID = nil
        errorMessage = nil
        statusMessage = nil
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

    func changeAction(_ action: AdviceAction) {
        guard self.action != action else { return }
        self.action = action
        if !selectedText.isEmpty { startStreaming() }
    }

    func applyInput(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        selectedText = text
        startStreaming()
    }

    func applyContext(_ context: AdviceContext) {
        self.context = context
        if !selectedText.isEmpty { startStreaming() }
    }

    func startStreaming() {
        cancelStreaming()
        previousResult = lastCompleted
        result = nil
        legacyOutput = ""
        isResultComplete = false
        errorMessage = nil
        statusMessage = nil
        recordID = nil
        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请先输入或选中需要处理的内容。"
            return
        }
        guard UserDefaults.standard.object(forKey: "serviceEnabled") as? Bool ?? true else {
            errorMessage = "处理服务已停用，请在服务设置中开启。"
            return
        }
        let model = UserDefaults.standard.string(forKey: "model") ?? "deepseek-chat"
        let baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? "https://api.deepseek.com"
        let id = requestID
        let input = selectedText
        let source = sourceApp
        let kind = captureKind
        let action = action
        let context = context
        let savesHistory = UserDefaults.standard.bool(forKey: "saveHistory")
        isStreaming = true
        streamTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.requestID == id { self.isStreaming = false } }
            do {
                let prompt = try SkillStore.systemPrompt(action: action, context: context)
                let content = try JSONEncoder().encode(
                    AdviceInput(originalText: input, context: context))
                let credentials = try await CredentialStore.shared.load()
                guard !Task.isCancelled, self.requestID == id else { return }
                if let notice = credentials.notice { self.statusMessage = notice }
                let client = AIClient(
                    apiKey: credentials.apiKey ?? "", model: model, baseURL: baseURL)
                var stream = AdviceStream(requestedAction: action)
                for try await chunk in client.stream(
                    systemPrompt: prompt, userContent: String(decoding: content, as: UTF8.self))
                {
                    guard !Task.isCancelled, self.requestID == id else { return }
                    try stream.append(chunk)
                    self.result = stream.result
                }
                guard !Task.isCancelled, self.requestID == id else { return }
                let result = try stream.finish()
                self.result = result
                self.isResultComplete = true
                self.isStreaming = false
                let record = AdviceRecord(
                    input: input, output: result.fullText, sourceApp: source, model: model,
                    captureKind: kind, action: action, context: context, result: result)
                self.lastCompleted = record
                if savesHistory && UserDefaults.standard.bool(forKey: "saveHistory") {
                    let store = HistoryStore.shared
                    if store.add(record) {
                        self.recordID = record.id
                    } else {
                        self.errorMessage = store.errorMessage
                    }
                }
                if !result.needsContext && UserDefaults.standard.bool(forKey: "autoCopyOutput") {
                    self.copyOutput()
                }
                if self.isQuiet && self.errorMessage == nil && !result.needsContext {
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
        }
    }

    func stop() {
        cancelStreaming()
        statusMessage = "已停止生成，未完成的内容未复制或保存。"
    }

    func regenerate() { startStreaming() }

    func restore(_ record: AdviceRecord) {
        begin(
            text: record.input, source: record.sourceApp, kind: record.captureKind ?? .manual,
            quiet: false)
        captureKind = record.captureKind
        action = record.action ?? .auto
        context = record.context ?? AdviceContext()
        result = record.result
        legacyOutput = record.result == nil ? record.output : ""
        isResultComplete = true
        lastCompleted = record
        recordID =
            HistoryStore.shared.records.contains(where: { $0.id == record.id }) ? record.id : nil
    }

    func restorePrevious() {
        guard let previous = previousResult else { return }
        let replacement = isResultComplete ? lastCompleted : nil
        restore(previous)
        previousResult = replacement
    }

    func dismiss() {
        cancelStreaming()
        panel?.orderOut(nil)
        hud?.orderOut(nil)
    }

    func copyPrimary() {
        guard canCopyPrimary else { return }
        copy(primaryText)
        statusMessage = "已复制"
    }

    func copyOutput() {
        guard isResultComplete, !isStreaming, !output.isEmpty else { return }
        copy(output)
        statusMessage = "已复制完整结果"
    }

    func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func ensurePanel() -> AdvisorPanel {
        if let panel { return panel }
        let panel = AdvisorPanel(
            contentView: NSHostingView(rootView: AdvisorView(coordinator: self)),
            size: NSSize(width: 520, height: 560))
        panel.onClose = { [weak self] in self?.cancelStreaming() }
        self.panel = panel
        return panel
    }

    private func ensureHUD() -> AdvisorPanel {
        if let hud { return hud }
        let hud = AdvisorPanel(
            contentView: NSHostingView(rootView: AdvisorHUD(coordinator: self)),
            size: NSSize(width: 380, height: 250))
        hud.onClose = { [weak self] in self?.cancelStreaming() }
        self.hud = hud
        return hud
    }
}
