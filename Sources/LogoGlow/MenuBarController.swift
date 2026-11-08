// SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
// SPDX-License-Identifier: GPL-2.0-only

import AppKit
import LogoGlowCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    /// Nil on Macs without an illuminated logo (or if macOS changed the private API).
    private let controller: LogoController?

    private let controlItem = NSMenuItem(title: "Control Logo", action: #selector(toggleControl), keyEquivalent: "")
    private let lightItem = NSMenuItem(title: "Light On", action: #selector(toggleLight), keyEquivalent: "")
    private let brightnessItem = NSMenuItem()
    private var slider = NSSlider()
    private let statusLine = NSMenuItem()
    private let rangeItem = NSMenuItem(title: "", action: #selector(toggleFullRange), keyEquivalent: "")
    private var isChangingRange = false

    override init() {
        controller = CoreBrightnessStore()
            .flatMap { LogoBacklight(store: $0) }
            .map { LogoController(backlight: $0) }
        super.init()

        statusItem.button?.image = Self.makeIcon()
        statusItem.menu = controller == nil ? makeUnsupportedMenu() : makeMenu()
        controller?.resume()
    }

    /// Hands the logo back to macOS on quit. The preference stays, so the next launch resumes.
    func applicationWillTerminate() {
        controller?.suspend()
    }

    // MARK: Menu

    private func makeUnsupportedMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(infoItem("This Mac has no illuminated logo."))
        menu.addItem(.separator())
        menu.addItem(quitItem())
        return menu
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        for item in [controlItem, lightItem, rangeItem] { item.target = self }
        lightItem.indentationLevel = 1

        statusLine.isEnabled = false

        menu.addItem(controlItem)
        menu.addItem(.separator())
        menu.addItem(lightItem)
        menu.addItem(brightnessItem)
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(rangeItem)
        menu.addItem(.separator())
        menu.addItem(quitItem())
        return menu
    }

    private func replaceSlider() {
        slider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: self, action: #selector(brightnessChanged))
        // One corebrightnessd write per drag, on release.
        slider.isContinuous = false
        brightnessItem.view = makeSliderView()
    }

    private func makeSliderView() -> NSView {
        let low = NSImageView(image: NSImage(systemSymbolName: "sun.min", accessibilityDescription: "Dimmer")!)
        let high = NSImageView(image: NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Brighter")!)
        for image in [low, high] { image.contentTintColor = .secondaryLabelColor }
        slider.setAccessibilityLabel("Logo brightness")

        let stack = NSStackView(views: [low, slider, high])
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 32, bottom: 4, right: 16)
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 28)
        stack.autoresizingMask = [.width]
        return stack
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func quitItem() -> NSMenuItem {
        NSMenuItem(title: "Quit Logo Glow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        replaceSlider()
        refresh()
    }

    private func refresh() {
        guard let controller else { return }
        let controlling = controller.isControlling
        let unlocked = controller.backlight.isFullRangeUnlocked

        controlItem.state = controlling ? .on : .off
        lightItem.state = controller.isLightOn ? .on : .off
        lightItem.isEnabled = controlling
        slider.doubleValue = controller.brightness
        slider.isEnabled = controlling && controller.isLightOn

        statusLine.title = statusText(controlling: controlling, unlocked: unlocked)

        rangeItem.title = unlocked ? "Restore Ambient Light Limits…" : "Unlock Full Range…"
        rangeItem.isEnabled = !isChangingRange
    }

    private func statusText(controlling: Bool, unlocked: Bool) -> String {
        guard let controller, let state = controller.backlight.state else { return "Logo status unavailable" }
        guard controlling else { return "macOS is controlling the logo" }
        guard controller.isLightOn else { return "Logo is off" }

        let target = LogoController.nits(forBrightness: controller.brightness)
        var text = "Now \(Int(state.appliedNits.rounded())) nits, set to \(Int(target.rounded()))"
        if !unlocked {
            let range = "\(Int(state.minNitsRestriction.rounded()))–\(Int(state.maxNitsRestriction.rounded()))"
            text += ", limited to \(range) by ambient light"
        }
        return text
    }

    // MARK: Actions

    @objc private func toggleControl() {
        guard let controller else { return }
        if !controller.setControlling(!controller.isControlling) {
            showError(controller.isControlling
                ? "Logo Glow couldn't hand the logo back to macOS. Try again."
                : "Logo Glow couldn't read the system's logo settings, so it left macOS in control.")
        }
        refreshNowAndAfterRamp()
    }

    @objc private func toggleLight() {
        guard let controller else { return }
        controller.setLightOn(!controller.isLightOn)
        refresh()
    }

    @objc private func brightnessChanged() {
        controller?.setBrightness(slider.doubleValue)
        refreshNowAndAfterRamp()
    }

    private func refreshNowAndAfterRamp() {
        refresh()
        Task {
            try? await Task.sleep(for: .seconds(1))
            refresh()
        }
    }

    @objc private func toggleFullRange() {
        guard let controller else { return }
        let action: FullRange.Action = controller.backlight.isFullRangeUnlocked ? .restore : .unlock
        guard confirm(action) else { return }

        isChangingRange = true
        Task {
            let outcome = await FullRange.run(action)
            if outcome == .succeeded {
                // launchd relaunches corebrightnessd. It reloads the saved mapping and mode by
                // itself; re-applying afterwards just guards against a lost write.
                try? await Task.sleep(for: .seconds(2))
                controller.resume()
            }
            isChangingRange = false
            if case .failed(let message) = outcome {
                showError("The brightness limits weren't changed.\n\n\(message)")
            }
        }
    }

    // MARK: Alerts

    private func confirm(_ action: FullRange.Action) -> Bool {
        let alert = NSAlert()
        switch action {
        case .unlock:
            alert.messageText = "Unlock the full brightness range?"
            alert.informativeText = """
                macOS limits how bright or dim the logo can be based on ambient light. \
                Unlocking lets Logo Glow set any brightness from off to full.

                This needs your administrator password, and restarts the macOS brightness \
                service. Your displays' brightness and color may shift for a moment while \
                True Tone and auto-brightness start up again. You can restore the limits from \
                this menu at any time.
                """
            alert.addButton(withTitle: "Unlock")
        case .restore:
            alert.messageText = "Restore the ambient light limits?"
            alert.informativeText = """
                This needs your administrator password, and restarts the macOS brightness \
                service. Your displays' brightness and color may shift for a moment while \
                True Tone and auto-brightness start up again.
                """
            alert.addButton(withTitle: "Restore")
        }
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Logo Glow"
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }

    /// Monochrome version of the app icon's lid-and-orb mark. Drawn as a template so
    /// AppKit tints it for light, dark, and highlighted menu bars.
    private static func makeIcon() -> NSImage {
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
    }
}
