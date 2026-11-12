// SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
// SPDX-License-Identifier: GPL-2.0-only

import AppKit
import SwiftUI

@main
struct LogoGlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: appDelegate.model, updates: appDelegate.updates)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: appDelegate.model, updates: appDelegate.updates)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = LogoModel()
    let updates = UpdateController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        observeDisplaySleep()
        model.resume()
    }

    /// Hands the logo back to macOS on quit. The preference stays, so the next launch resumes.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.suspend()
        Task {
            await model.waitUntilRestored()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func observeDisplaySleep() {
        let center = NSWorkspace.shared.notificationCenter
        let model = model
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { model.displayDidSleep() }
            }
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { model.displayDidWake() }
        }
    }
}

@MainActor
enum MenuBarIcon {
    /// Monochrome version of the app icon's lid-and-orb mark. Drawn as a template so
    /// AppKit tints it for light, dark, and highlighted menu bars.
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let lid = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 3.5, width: 15, height: 11), xRadius: 2, yRadius: 2)
            lid.lineWidth = 1.25
            lid.stroke()
            NSBezierPath(ovalIn: NSRect(x: 7, y: 7, width: 4, height: 4)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Logo Glow"
        return image
    }()
}
