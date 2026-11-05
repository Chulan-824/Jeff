import AppKit
import SwiftUI

/// Floating borderless-ish panel shown near the mouse, like Bob's popup.
final class AdvisorPanel: NSPanel {
    var onClose: (() -> Void)?

    override func close() {
        onClose?()
        super.close()
    }

    init(contentView: NSView, size: NSSize = NSSize(width: 480, height: 380)) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Jeff"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView.frame = contentRect(forFrameRect: frame)
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { true }

    func showNearMouse(activate: Bool = true) {
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - frame.height - 12)

        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX), visible.maxX - frame.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)
        }
        setFrameOrigin(origin)
        orderFrontRegardless()
        if activate {
            makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
