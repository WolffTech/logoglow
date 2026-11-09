// SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
// SPDX-License-Identifier: GPL-2.0-only

import Foundation

/// `LEBacklightMode` values. corebrightnessd also accepts 1, whose behavior is unknown, so
/// it is deliberately not representable.
public enum LogoBacklightMode: Int, Sendable {
    /// Light disabled immediately (no fade). Persists across restarts and into Recovery.
    case off = 0
    /// macOS default: lit, with brightness from the mapping tables. Fades in.
    case on = 2
}

/// Snapshot of corebrightnessd's `LEPWMState`.
public struct LogoState: Equatable, Sendable {
    /// Nits currently driven to the LED, after rate limiting.
    public let appliedNits: Double
    /// Built-in display brightness the mapping table reads from.
    public let displayNits: Double
    public let lux: Double
    /// Lux-based clamp applied to the mapping output.
    public let minNitsRestriction: Double
    public let maxNitsRestriction: Double

    public init?(propertyList: Any?) {
        guard let dict = propertyList as? [String: Any],
              let applied = (dict["AppliedNits"] as? NSNumber)?.doubleValue,
              let display = (dict["DisplayNits"] as? NSNumber)?.doubleValue,
              let lux = (dict["Lux"] as? NSNumber)?.doubleValue,
              let minNits = (dict["MinNitsRestriction"] as? NSNumber)?.doubleValue,
              let maxNits = (dict["MaxNitsRestriction"] as? NSNumber)?.doubleValue
        else { return nil }
        appliedNits = applied
        displayNits = display
        self.lux = lux
        minNitsRestriction = minNits
        maxNitsRestriction = maxNits
    }
}

/// The illuminated Apple logo, as exposed by corebrightnessd.
public struct LogoBacklight {
    enum Key {
        static let mode = "LEBacklightMode"
        static let state = "LEPWMState"
        static let brightnessMapping = "LEPWMBrightnessNitsMapping"
        static let minRestriction = "LEPWMLuxToMinNitsRestrictionMapping"
        static let maxRestriction = "LEPWMLuxToMaxNitsRestrictionMapping"
        static let displayNits = "DisplayNitsKey"
    }

    private let store: any BrightnessPropertyStore

    /// Returns nil on Macs without an illuminated logo.
    public init?(store: any BrightnessPropertyStore) {
        guard LogoState(propertyList: store.value(forKey: Key.state)) != nil else { return nil }
        self.store = store
    }

    /// Nil when the mode is unreadable or set to an unsupported value.
    public var mode: LogoBacklightMode? {
        (store.value(forKey: Key.mode) as? NSNumber).flatMap { LogoBacklightMode(rawValue: $0.intValue) }
    }

    @discardableResult
    public func setMode(_ mode: LogoBacklightMode) -> Bool {
        store.setValue(NSNumber(value: mode.rawValue), forKey: Key.mode)
    }

    public var state: LogoState? {
        LogoState(propertyList: store.value(forKey: Key.state))
    }

    /// Display nits → logo nits. corebrightnessd saves writes to its preferences, so they
    /// outlive the app.
    public var brightnessMapping: NitsMapping? {
        NitsMapping(propertyList: store.value(forKey: Key.brightnessMapping))
    }

    @discardableResult
    public func setBrightnessMapping(_ mapping: NitsMapping) -> Bool {
        guard store.setValue(mapping.propertyList, forKey: Key.brightnessMapping) else { return false }
        resendCurrentDisplayNits()
        return true
    }

    private func resendCurrentDisplayNits() {
        guard let nits = store.value(forKey: Key.displayNits) as? NSNumber, nits.doubleValue > 0 else { return }
        _ = store.setValue(nits, forKey: Key.displayNits)
    }

    /// True when corebrightnessd loaded the tables `FullRange.Action.unlock` writes. The live
    /// clamp in `state` can stay above 0 nits even then, so it can't tell.
    public var isFullRangeUnlocked: Bool {
        NitsMapping(propertyList: store.value(forKey: Key.minRestriction)) == .constant(FullRange.minNits)
            && NitsMapping(propertyList: store.value(forKey: Key.maxRestriction)) == .constant(FullRange.maxNits)
    }
}
