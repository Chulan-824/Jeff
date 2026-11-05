import AppKit

/// Screenshot-word-grab orchestrator, mirroring Bob's Snip + OCRWindowController:
/// capture screens via CGWindowList (no Screen Recording permission needed),
/// present a dimmed overlay per screen, crop the dragged rect, run Vision OCR.
@MainActor
final class SnipController {
    static let shared = SnipController()

    private var windows: [NSWindow] = []
    private var captures: [ObjectIdentifier: CGImage] = [:]
    private var quartzRects: [ObjectIdentifier: CGRect] = [:]

    /// Begin snip mode. Completion receives recognized text (nil = cancelled/empty).
    func start(completion: @escaping (String?) -> Void) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            completion(nil)
            return
        }
        let primaryHeight = screens.first?.frame.height ?? 0

        var pending = 0
        var finished = false
        let done: (String?) -> Void = { text in
            guard !finished else { return }
            finished = true
            self.teardown()
            completion(text)
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
                    done(nil)
                    return
                }
                let screenRect = window.convertToScreen(viewRect)
                let cropped = self.crop(
                    image: image,
                    cocoaRect: screenRect,
                    qRect: qRect,
                    primaryHeight: primaryHeight)
                guard let cropped else {
                    done(nil)
                    return
                }
                Task {
                    do {
                        let text = try await AppleOCR.recognize(cropped)
                        done(text.isEmpty ? nil : text)
                    } catch {
                        NSLog("Jeff: OCR failed: \(error)")
                        done(nil)
                    }
                }
            }
            view.onCancel = { done(nil) }

            windows.append(window)
            window.makeKeyAndOrderFront(nil)
        }

        if pending == 0 {
            done(nil)
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
