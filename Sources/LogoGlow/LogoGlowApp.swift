// SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
// SPDX-License-Identifier: GPL-2.0-only

import AppKit

@main
@MainActor
enum LogoGlowApp {
    static func main() {
        let app = NSApplication.shared
        // NSApplication holds its delegate weakly; this local keeps it alive for the
        // lifetime of run().
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBar?.applicationWillTerminate()
    }
}
