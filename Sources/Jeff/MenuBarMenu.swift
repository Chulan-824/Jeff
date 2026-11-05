import AppKit
import SwiftUI

/// Native dropdown menu (Bob-style): standard menu items, icons, shortcuts.
struct MenuBarMenu: View {
    @ObservedObject private var coordinator = AdvisorCoordinator.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Disabled header line, like Bob's menu title.
        Text("Jeff")
            .font(.headline)

        Divider()

        Button {
            coordinator.trigger()
        } label: {
            Label(
                "分析选中文字  \(coordinator.selectionShortcut?.display ?? "")",
                systemImage: "text.magnifyingglass")
        }

        Button {
            coordinator.triggerSnip()
        } label: {
            Label(
                "截图取词分析  \(coordinator.snipShortcut?.display ?? "")",
                systemImage: "viewfinder")
        }

        if coordinator.needsAccessibilityPermission {
            Button {
                _ = SelectionCapture.isTrusted(prompt: true)
                SelectionCapture.openAccessibilitySettings()
            } label: {
                Label("授权辅助功能权限", systemImage: "lock.shield")
            }
        }

        Divider()

        Button("分析剪贴板文字", action: coordinator.triggerClipboard)
        Button("输入内容分析…", action: coordinator.showInput)
        Button("显示上次结果", action: coordinator.showResult)
        Button("历史与收藏…") {
            openWindow(id: "history")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        SettingsLink {
            Label("设置…", systemImage: "gearshape")
        }
        .keyboardShortcut(",")

        Button {
            NSApp.orderFrontStandardAboutPanel(nil)
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("关于", systemImage: "info.circle")
        }

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("退出", systemImage: "power")
        }
        .keyboardShortcut("q")
    }
}

/// The bundled vector template adapts to the menu bar appearance;「J」is the fallback.
enum MenuBarIcon {
    static func image() -> NSImage {
        let side: CGFloat = 18
        let bundledImage = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf")
            .flatMap { NSImage(contentsOf: $0) }
        let img =
            bundledImage
            ?? NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 13.5, weight: .bold),
                    .foregroundColor: NSColor.black,
                ]
                let str = NSAttributedString(string: "J", attributes: attrs)
                let strSize = str.size()
                str.draw(
                    at: NSPoint(
                        x: (rect.width - strSize.width) / 2,
                        y: (rect.height - strSize.height) / 2 - 0.5
                    ))
                return true
            }
        img.size = NSSize(width: side, height: side)
        img.isTemplate = true
        return img
    }
}
