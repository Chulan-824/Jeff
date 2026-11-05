import AppKit
import ApplicationServices

/// Captures the currently selected text in the frontmost app.
///
/// Strategy (same as Bob):
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

    /// Returns selected text, or nil when nothing is selected / capture failed.
    static func grabSelectedText() -> String? {
        if let text = axSelectedText(), !text.isEmpty {
            return text
        }
        return clipboardGrab()
    }

    private static func axSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focusedObj: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                system, kAXFocusedUIElementAttribute as CFString, &focusedObj
            ) == .success, let focused = focusedObj
        else { return nil }

        var value: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &value
            ) == .success
        else { return nil }

        if let text = value as? String { return text }
        if let attr = value as? NSAttributedString { return attr.string }
        return nil
    }

    private static func clipboardGrab() -> String? {
        let pb = NSPasteboard.general
        let oldCount = pb.changeCount
        let oldItems =
            pb.pasteboardItems?.compactMap { item -> (String, Data)? in
                guard let type = item.types.first, let data = item.data(forType: type) else {
                    return nil
                }
                return (type.rawValue, data)
            } ?? []

        simulateCopy()
        // Give the target app a moment to write the pasteboard.
        usleep(120_000)

        // If ⌘C did not change the pasteboard, nothing was copied — never send
        // stale clipboard contents to the model.
        guard pb.changeCount != oldCount,
            let text = pb.string(forType: .string), !text.isEmpty
        else { return nil }

        // Restore previous clipboard contents.
        pb.clearContents()
        for (type, data) in oldItems {
            pb.setData(data, forType: NSPasteboard.PasteboardType(type))
        }
        return text
    }

    private static func simulateCopy() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKeyC: CGKeyCode = 0x08
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKeyC, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKeyC, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
