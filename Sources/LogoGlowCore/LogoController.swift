// SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
// SPDX-License-Identifier: GPL-2.0-only

import Foundation

/// Hands the logo back and forth between macOS and the app's saved settings.
///
/// Taking control saves the system's mapping and mode so that handing back restores exactly
/// what was there. The saved copy survives crashes, and is only cleared once a restore
/// succeeds.
@MainActor
public final class LogoController {
    public let backlight: LogoBacklight
    private let defaults: UserDefaults

    private enum Key {
        static let isControlling = "isControlling"
        static let isLightOn = "isLightOn"
        static let brightness = "brightness"
        static let systemSettings = "systemSettings"
    }

    public init(backlight: LogoBacklight, defaults: UserDefaults = .standard) {
        self.backlight = backlight
        self.defaults = defaults
        defaults.register(defaults: [Key.isLightOn: true, Key.brightness: 0.5])
    }

    /// Whether the app, rather than macOS, should drive the logo. Saved across launches.
    public private(set) var isControlling: Bool {
        get { defaults.bool(forKey: Key.isControlling) }
        set { defaults.set(newValue, forKey: Key.isControlling) }
    }

    public private(set) var isLightOn: Bool {
        get { defaults.bool(forKey: Key.isLightOn) }
        set { defaults.set(newValue, forKey: Key.isLightOn) }
    }

    /// Slider position, 0…1.
    public private(set) var brightness: Double {
        get { defaults.double(forKey: Key.brightness).clamped(to: 0...1) }
        set { defaults.set(newValue.clamped(to: 0...1), forKey: Key.brightness) }
    }

    /// Squared so the low end, where the eye is most sensitive, gets more of the slider.
    public static func nits(forBrightness brightness: Double) -> Double {
        let b = brightness.clamped(to: 0...1)
        return FullRange.maxNits * b * b
    }

    /// Re-applies the saved settings, e.g. at launch or after corebrightnessd restarts.
    @discardableResult
    public func resume() -> Bool {
        isControlling ? takeControl() : true
    }

    /// Returns false, leaving macOS in control, when the system settings can't be saved.
    @discardableResult
    public func setControlling(_ controlling: Bool) -> Bool {
        guard controlling else {
            isControlling = false
            return handBack()
        }
        guard takeControl() else { return false }
        isControlling = true
        return true
    }

    public func setLightOn(_ on: Bool) {
        isLightOn = on
        if isControlling { backlight.setMode(on ? .on : .off) }
    }

    public func setBrightness(_ value: Double) {
        brightness = value
        if isControlling { backlight.setBrightnessMapping(.constant(Self.nits(forBrightness: brightness))) }
    }

    /// Gives the logo back to macOS without changing the saved preference, so the next
    /// launch resumes control. For quitting.
    public func suspend() {
        if isControlling { handBack() }
    }

    private func takeControl() -> Bool {
        if savedSystemSettings == nil {
            guard let mapping = backlight.brightnessMapping else { return false }
            savedSystemSettings = SystemSettings(mapping: mapping, mode: backlight.mode)
        }
        return backlight.setBrightnessMapping(.constant(Self.nits(forBrightness: brightness)))
            && backlight.setMode(isLightOn ? .on : .off)
    }

    @discardableResult
    private func handBack() -> Bool {
        guard let saved = savedSystemSettings else {
            return backlight.setMode(.on)
        }
        let restored = backlight.setBrightnessMapping(saved.mapping)
            && backlight.setMode(saved.mode ?? .on)
        if restored { savedSystemSettings = nil }
        return restored
    }

    private struct SystemSettings {
        let mapping: NitsMapping
        /// Nil when macOS had a mode the app can't represent; restores to `.on`.
        let mode: LogoBacklightMode?
    }

    private var savedSystemSettings: SystemSettings? {
        get {
            guard let dict = defaults.dictionary(forKey: Key.systemSettings),
                  let mapping = NitsMapping(propertyList: dict["mapping"])
            else { return nil }
            let mode = (dict["mode"] as? Int).flatMap(LogoBacklightMode.init(rawValue:))
            return SystemSettings(mapping: mapping, mode: mode)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.systemSettings)
                return
            }
            var dict: [String: Any] = ["mapping": newValue.mapping.propertyList]
            dict["mode"] = newValue.mode?.rawValue
            defaults.set(dict, forKey: Key.systemSettings)
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        isNaN ? range.lowerBound : min(max(self, range.lowerBound), range.upperBound)
    }
}
