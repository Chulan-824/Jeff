import AppKit

@MainActor
final class SnipController {
    static let shared = SnipController()

    enum Outcome {
        case image(CGImage)
        case cancelled
        case awaitingScreenPermission
        case failed(String)
    }

    private var windows: [NSWindow] = []
    private var completion: ((Outcome) -> Void)?

    func start(completion: @escaping (Outcome) -> Void) {
        let screens = NSScreen.screens
        guard let primary = screens.first else {
            completion(.failed("没有可用屏幕，请稍后重试。"))
            return
        }
        if !CGPreflightScreenCaptureAccess() {
            let preference = "didRequestScreenCaptureAccess"
            if UserDefaults.standard.bool(forKey: preference) {
                let settings = URL(
                    string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                )!
                completion(
                    NSWorkspace.shared.open(settings)
                        ? .awaitingScreenPermission
                        : .failed("请在系统设置的「隐私与安全性」中允许 Jeff 录制屏幕，再重新打开 Jeff。"))
                return
            }
            UserDefaults.standard.set(true, forKey: preference)
            guard CGRequestScreenCaptureAccess() else {
                completion(.awaitingScreenPermission)
                return
            }
        }

        self.completion = completion
        for screen in screens {
            let frame = screen.frame
            let view = SnipOverlayView(frame: CGRect(origin: .zero, size: frame.size))
            let window = SnipWindow(
                contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.hasShadow = false
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = view
            window.setFrame(frame, display: false)
            windows.append(window)
            window.orderFrontRegardless()
            if frame.contains(NSEvent.mouseLocation) {
                window.makeKey()
                window.makeFirstResponder(view)
            }

            let rect = CGRect(
                x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width,
                height: frame.height)
            let windowID = CGWindowID(window.windowNumber)
            // Capture below the live selection overlay so its dimming never reaches Vision.
            let snapshot = Task.detached(priority: .userInitiated) {
                CGWindowListCreateImage(
                    rect, .optionOnScreenBelowWindow, windowID,
                    [.bestResolution, .boundsIgnoreFraming])
            }
            var selected = false
            Task { [weak window, weak view] in
                let image = await snapshot.value
                guard let window, windows.contains(window) else { return }
                guard let image else {
                    window.orderOut(nil)
                    windows.removeAll { $0 === window }
                    if windows.isEmpty || selected { finish(.failed("无法截取屏幕，请检查屏幕录制权限后重试。")) }
                    return
                }
                view?.show(image)
            }

            view.onCancel = { self.cancel() }
            view.onFinish = { [weak window] selection in
                selected = true
                for overlay in self.windows { overlay.ignoresMouseEvents = true }
                Task {
                    let image = await snapshot.value
                    // A cancelled session may already have been replaced by another snip.
                    guard let window, self.windows.contains(window) else { return }
                    guard let image else {
                        self.finish(.failed("无法取得所选区域，请重新框选。"))
                        return
                    }
                    let scaleX = CGFloat(image.width) / frame.width
                    let scaleY = CGFloat(image.height) / frame.height
                    let pixels = CGRect(
                        x: selection.minX * scaleX, y: (frame.height - selection.maxY) * scaleY,
                        width: selection.width * scaleX, height: selection.height * scaleY
                    ).integral
                    if let cropped = image.cropping(to: pixels) {
                        self.finish(.image(cropped))
                    } else {
                        self.finish(.failed("无法取得所选区域，请重新框选。"))
                    }
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        AppleOCR.prepare()
    }

    func cancel() { finish(.cancelled) }

    private func finish(_ outcome: Outcome) {
        guard let completion else { return }
        self.completion = nil
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
        completion(outcome)
    }
}

private final class SnipWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
