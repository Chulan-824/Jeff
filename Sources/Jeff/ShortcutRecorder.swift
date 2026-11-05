import AppKit
import Carbon
import SwiftUI

/// A recorded hotkey (Carbon key code + Carbon modifier mask).
struct RecordedShortcut: Codable {
    var keyCode: UInt32
    var modifiers: UInt32

    var conflictsWithDock: Bool {
        keyCode == 0x02 && modifiers == UInt32(optionKey | cmdKey)
    }

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        s += KeyCodeMap.string(for: keyCode)
        return s
    }

    static func load(_ key: String, default fallback: RecordedShortcut? = nil) -> RecordedShortcut?
    {
        guard let data = UserDefaults.standard.data(forKey: key) else { return fallback }
        return try? JSONDecoder().decode(RecordedShortcut.self, from: data)
    }

    static func save(_ shortcut: RecordedShortcut?, forKey key: String) {
        // Persist null to distinguish a cleared shortcut from a first-launch default.
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

enum KeyCodeMap {
    static func string(for keyCode: UInt32) -> String {
        let map: [UInt32: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G",
            0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
            0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T", 0x12: "1",
            0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
            0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
            0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P", 0x25: "L",
            0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";", 0x2A: "\\", 0x2B: ",",
            0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x30: "⇥", 0x31: "␣",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}

/// Bob-style recorder with fixed modifier positions and an inline clear button.
struct ShortcutRecorder: NSViewRepresentable {
    var shortcut: RecordedShortcut?
    var isEnabled = true
    var label: String
    var onRecord: (RecordedShortcut?) -> Void

    func makeNSView(context: Context) -> RecorderField {
        RecorderField()
    }

    func updateNSView(_ field: RecorderField, context: Context) {
        field.shortcut = shortcut
        field.isEnabled = isEnabled
        field.onRecord = onRecord
        field.setAccessibilityElement(true)
        field.setAccessibilityRole(.button)
        field.setAccessibilityLabel(label)
        field.setAccessibilityValue(shortcut?.display ?? "未设置")
        field.setAccessibilityEnabled(isEnabled)
        field.toolTip = isEnabled ? "点击录制快捷键，Esc 取消；点击 × 清除" : "此功能暂未接入"
        field.needsDisplay = true
    }
}

final class RecorderField: NSView {
    var shortcut: RecordedShortcut?
    var isEnabled = true
    var onRecord: ((RecordedShortcut?) -> Void)?
    private var recording = false
    private var monitor: Any?
    private let modifierKeys: [(String, UInt32)] = [
        ("⌃", UInt32(controlKey)), ("⌥", UInt32(optionKey)),
        ("⇧", UInt32(shiftKey)), ("⌘", UInt32(cmdKey)),
    ]

    override var intrinsicContentSize: NSSize { NSSize(width: 190, height: 28) }
    override var acceptsFirstResponder: Bool { isEnabled }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.textBackgroundColor.setFill()
        path.fill()
        (recording ? NSColor.keyboardFocusIndicatorColor : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 1.5 : 1
        path.stroke()

        for (index, modifier) in modifierKeys.enumerated() {
            let active = (shortcut?.modifiers ?? 0) & modifier.1 != 0
            drawText(
                modifier.0, x: 9 + CGFloat(index) * 16,
                color: active && isEnabled ? .controlAccentColor : .tertiaryLabelColor)
        }
        if recording {
            drawText("按键…", x: 81, color: .secondaryLabelColor, size: 12)
        } else if let shortcut {
            drawText(
                KeyCodeMap.string(for: shortcut.keyCode), x: 80,
                color: isEnabled ? .controlAccentColor : .tertiaryLabelColor)
            let clearRect = NSRect(
                x: bounds.width - 20, y: (bounds.height - 12) / 2,
                width: 12, height: 12)
            NSColor.tertiaryLabelColor.setFill()
            NSBezierPath(ovalIn: clearRect).fill()
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: clearRect.minX + 4, y: clearRect.minY + 4))
            cross.line(to: NSPoint(x: clearRect.maxX - 4, y: clearRect.maxY - 4))
            cross.move(to: NSPoint(x: clearRect.minX + 4, y: clearRect.maxY - 4))
            cross.line(to: NSPoint(x: clearRect.maxX - 4, y: clearRect.minY + 4))
            NSColor.textBackgroundColor.setStroke()
            cross.lineWidth = 1.5
            cross.stroke()
        }
    }

    private func drawText(_ text: String, x: CGFloat, color: NSColor, size: CGFloat = 16) {
        let string = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .medium),
                .foregroundColor: color,
            ])
        string.draw(at: NSPoint(x: x, y: (bounds.height - string.size().height) / 2))
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        if shortcut != nil && convert(event.locationInWindow, from: nil).x >= bounds.width - 26 {
            stopRecording()
            onRecord?(nil)
            return
        }
        beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 || event.keyCode == 36 {
            beginRecording()
        } else {
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        beginRecording()
        return true
    }

    private func beginRecording() {
        guard isEnabled, !recording else { return }
        window?.makeFirstResponder(self)
        recording = true
        needsDisplay = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var modifiers: UInt32 = 0
            if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
            if flags.contains(.option) { modifiers |= UInt32(optionKey) }
            if flags.contains(.control) { modifiers |= UInt32(controlKey) }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            guard modifiers != 0 else { return nil }
            let recorded = RecordedShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            self.stopRecording()
            self.onRecord?(recorded)
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return true
    }

    override func viewDidMoveToWindow() {
        if window == nil { stopRecording() }
    }
}
