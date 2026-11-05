import AppKit

/// Fullscreen dimmed layer showing the captured screenshot.
/// User drags a rect; Esc cancels. Mirrors Bob's SnipViewController role.
final class SnipOverlayView: NSView {
    var onFinish: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private let screenshot: NSImage?
    private var startPoint = NSPoint.zero
    private var currentPoint = NSPoint.zero
    private var dragging = false

    init(frame: NSRect, screenshot: NSImage?) {
        self.screenshot = screenshot
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { nil }

    private var selection: NSRect {
        guard dragging else { return .zero }
        return NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        if let screenshot {
            screenshot.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()

        let sel = selection
        if !sel.isEmpty {
            // Cut a clear hole for the selected region, then re-draw the
            // screenshot portion at full brightness inside it.
            let clear = NSBezierPath(rect: sel)
            NSColor.clear.setFill()
            clear.fill()
            if let screenshot {
                screenshot.draw(in: sel, from: sel, operation: .sourceOver, fraction: 1.0)
            }
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let border = NSBezierPath(rect: sel)
            border.lineWidth = 1.5
            border.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        dragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        let sel = selection
        dragging = false
        if sel.width >= 8 && sel.height >= 8 {
            onFinish?(sel)
        } else {
            onCancel?()  // click without drag = cancel
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }  // Esc
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
}
