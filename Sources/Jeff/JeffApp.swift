import AppKit
import SwiftUI

@main
struct JeffApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu()
        } label: {
            Image(nsImage: MenuBarIcon.image())
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }

        Window("历史与收藏", id: "history") {
            HistoryView()
        }
        .defaultSize(width: 840, height: 520)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        AdvisorCoordinator.shared.showResult()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let current = NSRunningApplication.current
        if let id = current.bundleIdentifier,
            NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: {
                peer in
                guard peer.processIdentifier != current.processIdentifier else { return false }
                if let start = current.launchDate, let otherStart = peer.launchDate,
                    start != otherStart
                {
                    return otherStart < start
                }
                // Command-line launches may have no Launch Services timestamp.
                return peer.isFinishedLaunching
                    || peer.processIdentifier < current.processIdentifier
            })
        {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)

        AdvisorCoordinator.shared.applyHotkeys()

        if !SelectionCapture.isTrusted(prompt: false) {
            AdvisorCoordinator.shared.needsAccessibilityPermission = true
        }
    }
}
