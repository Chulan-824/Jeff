import AppKit
import ApplicationServices

/// Captures the currently selected text in the frontmost app.
///
/// Strategy:
/// 1. Accessibility API — read `AXSelectedText` of the focused element.
///    Requires Accessibility permission (TCC), asked once via `isTrusted(prompt:)`.
/// 2. Clipboard fallback — snapshot the pasteboard, simulate ⌘C, read, restore.
enum SelectionCapture {

    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func grabSelectedText(from pid: pid_t) async -> String? {
        if let text = axSelectedText(from: pid), !text.isEmpty { return text }
        guard !Task.isCancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        else { return nil }
        return await clipboardGrab(from: pid)
    }

    private static func axSelectedText(from pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var focusedObj: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                app, kAXFocusedUIElementAttribute as CFString, &focusedObj
            ) == .success, let focusedObj, CFGetTypeID(focusedObj) == AXUIElementGetTypeID()
        else { return nil }

        let focused = focusedObj as! AXUIElement
        AXUIElementSetMessagingTimeout(focused, 0.25)
        var value: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                focused, kAXSelectedTextAttribute as CFString, &value
            ) == .success
        else { return nil }
        return value as? String ?? (value as? NSAttributedString)?.string
    }

    private static func clipboardGrab(from pid: pid_t) async -> String? {
        let pb = NSPasteboard.general
        let oldCount = pb.changeCount
        var backup: [NSPasteboardItem] = []
        for item in pb.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type), copy.setData(data, forType: type) else {
                    return nil
                }
            }
            backup.append(copy)
        }

        guard !Task.isCancelled, pb.changeCount == oldCount,
            NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        else { return nil }
        simulateCopy(to: pid)
        // Finish the clipboard transaction even if the originating request is cancelled.
        return await Task.detached(priority: .userInitiated) {
            let deadline = ContinuousClock.now + .milliseconds(120)
            while true {
                let count = pb.changeCount
                if count != oldCount {
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
                    else { return nil }
                    // Some apps clear the pasteboard before publishing the text.
                    let text = pb.string(forType: .string)
                    if text != nil || ContinuousClock.now >= deadline {
                        guard pb.changeCount == count else { return nil }
                        pb.clearContents()
                        if !backup.isEmpty { pb.writeObjects(backup) }
                        return text
                    }
                }
                guard ContinuousClock.now < deadline else { return nil }
                try? await Task.sleep(for: .milliseconds(8))
            }
        }.value
    }

    private static func simulateCopy(to pid: pid_t) {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKeyC: CGKeyCode = 0x08
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKeyC, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKeyC, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.postToPid(pid)
        up?.postToPid(pid)
    }
}
