import AppKit

/// Capture the selected screen region and recognize text locally with Vision.
@MainActor
final class SnipController {
    static let shared = SnipController()

    private var windows: [NSWindow] = []
    private var captures: [ObjectIdentifier: CGImage] = [:]
    private var quartzRects: [ObjectIdentifier: CGRect] = [:]

    enum Outcome {
        case text(String)
        case cancelled
        case failed(String)
    }

    func start(completion: @escaping (Outcome) -> Void) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            completion(.failed("没有可用屏幕，请稍后重试。"))
            return
        }
        let primaryHeight = screens.first?.frame.height ?? 0

        var pending = 0
        var finished = false
        let done: (Outcome) -> Void = { outcome in
            guard !finished else { return }
            finished = true
            self.teardown()
            completion(outcome)
        }

        for screen in screens {
            let cocoa = screen.frame
            // Cocoa -> Quartz display coords (top-left origin of primary screen).
            let qRect = CGRect(
                x: cocoa.origin.x,
                y: primaryHeight - cocoa.origin.y - cocoa.height,
                width: cocoa.width, height: cocoa.height
            )
            guard
                let image = CGWindowListCreateImage(
                    qRect, .optionOnScreenOnly, kCGNullWindowID,
                    [.bestResolution, .boundsIgnoreFraming]
                )
            else { continue }

            let nsImage = NSImage(cgImage: image, size: cocoa.size)
            let view = SnipOverlayView(
                frame: NSRect(origin: .zero, size: cocoa.size),
                screenshot: nsImage)
            let window = NSWindow(
                contentRect: cocoa,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = view

            let key = ObjectIdentifier(window)
            captures[key] = image
            quartzRects[key] = qRect
            pending += 1

            view.onFinish = { [weak self] viewRect in
                guard let self else {
                    done(.cancelled)
                    return
                }
                let screenRect = window.convertToScreen(viewRect)
                let cropped = self.crop(
                    image: image,
                    cocoaRect: screenRect,
                    qRect: qRect,
                    primaryHeight: primaryHeight)
                guard let cropped else {
                    done(.failed("无法取得所选区域，请重新框选。"))
                    return
                }
                Task {
                    do {
                        let recognized = try await AppleOCR.recognize(cropped)
                        let text = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
                        done(text.isEmpty ? .failed("未识别到文字，请框选包含文字的区域。") : .text(text))
                    } catch {
                        NSLog("Jeff: OCR failed: \(error)")
                        done(.failed("文字识别失败，请重新截图。"))
                    }
                }
            }
            view.onCancel = { done(.cancelled) }

            windows.append(window)
            window.makeKeyAndOrderFront(nil)
        }

        if pending == 0 {
            done(.failed("无法截取屏幕，请检查屏幕录制权限后重试。"))
            return
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Crop the selected Cocoa screen rect out of the captured CGImage.
    /// CGWindowListCreateImage is in Quartz coords (top-left origin, pixels).
    private func crop(
        image: CGImage, cocoaRect: NSRect,
        qRect: CGRect, primaryHeight: CGFloat
    ) -> CGImage? {
        // Cocoa rect -> Quartz rect relative to the captured region.
        let relX = cocoaRect.origin.x - qRect.origin.x
        let relY = (primaryHeight - cocoaRect.origin.y - cocoaRect.height) - qRect.origin.y

        let scale = CGFloat(image.width) / qRect.width
        let pixel = CGRect(
            x: relX * scale, y: relY * scale,
            width: cocoaRect.width * scale,
            height: cocoaRect.height * scale
        )
        .integral
        return image.cropping(to: pixel)
    }

    private func teardown() {
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        captures.removeAll()
        quartzRects.removeAll()
    }
}
