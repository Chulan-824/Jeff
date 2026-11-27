import AppKit
import QuartzCore

final class SnipOverlayView: NSView {
    var onFinish: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private let screenshot = CALayer()
    private let maskLayer = CAShapeLayer()
    private var startPoint: CGPoint?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        screenshot.frame = bounds
        screenshot.actions = ["contents": NSNull()]
        maskLayer.frame = bounds
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = NSColor.black.withAlphaComponent(0.45).cgColor
        maskLayer.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        maskLayer.lineWidth = 1.5
        maskLayer.actions = ["path": NSNull()]
        layer?.addSublayer(screenshot)
        layer?.addSublayer(maskLayer)
        updateMask(selection: .zero)
    }

    required init?(coder: NSCoder) { nil }

    func show(_ image: CGImage) { screenshot.contents = image }

    private func selection(to point: CGPoint) -> CGRect {
        guard let startPoint else { return .zero }
        return CGRect(
            x: min(startPoint.x, point.x), y: min(startPoint.y, point.y),
            width: abs(point.x - startPoint.x), height: abs(point.y - startPoint.y)
        ).intersection(bounds)
    }

    private func updateMask(selection: CGRect) {
        let path = CGMutablePath()
        path.addRect(bounds.insetBy(dx: -2, dy: -2))
        if !selection.isEmpty { path.addRect(selection) }
        maskLayer.path = path
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        updateMask(selection: selection(to: convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        let rect = selection(to: convert(event.locationInWindow, from: nil))
        startPoint = nil
        if rect.width >= 8 && rect.height >= 8 { onFinish?(rect) } else { onCancel?() }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
}
