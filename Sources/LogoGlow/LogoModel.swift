// SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
// SPDX-License-Identifier: GPL-2.0-only

import AppKit
import LogoGlowCore
import Observation

enum LightMode: CaseIterable, Identifiable {
    case steady
    case breathe
    case pulse
    case heartbeat

    init(effect: LogoEffect?) {
        switch effect {
        case nil: self = .steady
        case .breathe: self = .breathe
        case .pulse: self = .pulse
        case .heartbeat: self = .heartbeat
        }
    }

    var effect: LogoEffect? {
        switch self {
        case .steady: nil
        case .breathe: .breathe
        case .pulse: .pulse
        case .heartbeat: .heartbeat
        }
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .steady: "Steady"
        case .breathe: "Breathe"
        case .pulse: "Pulse"
        case .heartbeat: "Heartbeat"
        }
    }

    var symbol: String {
        switch self {
        case .steady: "circle.fill"
        case .breathe: "wind"
        case .pulse: "dot.radiowaves.left.and.right"
        case .heartbeat: "heart.fill"
        }
    }
}

enum GlowStatus: Equatable {
    case unsupported
    case systemControlled
    case off
    case glowing(limitedByAmbientLight: Bool)

    var title: String {
        switch self {
        case .unsupported: "No illuminated logo"
        case .systemControlled: "Controlled by macOS"
        case .off: "Off"
        case .glowing(limitedByAmbientLight: false): "Glowing"
        case .glowing(limitedByAmbientLight: true): "Glowing · limited by ambient light"
        }
    }
}

@MainActor
@Observable
final class LogoModel {
    private let controller: LogoController?

    private(set) var isControlling = false
    private(set) var isLightOn = true
    private(set) var brightness = 0.5
    private(set) var mode = LightMode.steady
    private(set) var state: LogoState?
    private(set) var isFullRangeUnlocked = false
    private(set) var isChangingRange = false

    init() {
        controller = CoreBrightnessStore()
            .flatMap { LogoBacklight(store: $0) }
            .map { LogoController(backlight: $0) }
        refresh()
    }

    var isSupported: Bool { controller != nil }

    var canAdjustLight: Bool { isControlling && isLightOn }

    var status: GlowStatus {
        guard isSupported else { return .unsupported }
        guard isControlling else { return .systemControlled }
        guard isLightOn else { return .off }
        guard !isFullRangeUnlocked, let state else { return .glowing(limitedByAmbientLight: false) }
        let target = LogoController.nits(forBrightness: brightness)
        let limits = state.minNitsRestriction...state.maxNitsRestriction
        return .glowing(limitedByAmbientLight: !limits.contains(target))
    }

    func previewIntensity(brightness draft: Double) -> Double {
        guard isSupported else { return 0 }
        guard isControlling else {
            guard let state else { return 0 }
            return (state.appliedNits / FullRange.maxNits).clamped(to: 0...1).squareRoot()
        }
        return isLightOn ? draft : 0
    }

    func resume() {
        controller?.resume()
        refresh()
    }

    func suspend() {
        controller?.suspend()
    }

    func waitUntilRestored() async {
        await controller?.waitUntilRestored()
    }

    func displayDidSleep() {
        controller?.displayDidSleep()
    }

    func displayDidWake() {
        controller?.displayDidWake()
    }

    func refresh() {
        guard let controller else { return }
        isControlling = controller.isControlling
        isLightOn = controller.isLightOn
        brightness = controller.brightness
        mode = LightMode(effect: controller.effect)
        state = controller.backlight.state
        isFullRangeUnlocked = controller.backlight.isFullRangeUnlocked
    }

    func setControlling(_ controlling: Bool) {
        guard let controller else { return }
        if !controller.setControlling(controlling) {
            Alerts.showError(controller.isControlling
                ? "Logo Glow couldn't hand the logo back to macOS. Try again."
                : "Logo Glow couldn't read the system's logo settings, so it left macOS in control.")
        }
        refreshNowAndAfterRamp()
    }

    func setLightOn(_ on: Bool) {
        controller?.setLightOn(on)
        refreshNowAndAfterRamp()
    }

    func setMode(_ mode: LightMode) {
        controller?.setEffect(mode.effect)
        refresh()
    }

    func setBrightness(_ value: Double) {
        controller?.setBrightness(value)
        refreshNowAndAfterRamp()
    }

    func toggleFullRange() {
        guard let controller, !isChangingRange else { return }
        let action: FullRange.Action = controller.backlight.isFullRangeUnlocked ? .restore : .unlock
        guard Alerts.confirm(action) else { return }

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
            refresh()
            if case .failed(let message) = outcome {
                Alerts.showError("The brightness limits weren't changed.\n\n\(message)")
            }
        }
    }

    private func refreshNowAndAfterRamp() {
        refresh()
        Task {
            try? await Task.sleep(for: .seconds(1))
            refresh()
        }
    }
}

@MainActor
private enum Alerts {
    static func confirm(_ action: FullRange.Action) -> Bool {
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
                Logo Glow Settings at any time.
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

    static func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Logo Glow"
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
