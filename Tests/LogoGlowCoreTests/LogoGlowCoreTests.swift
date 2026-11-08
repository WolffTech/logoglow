// SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
// SPDX-License-Identifier: GPL-2.0-only

import Foundation
import Testing
@testable import LogoGlowCore

/// In-memory stand-in for corebrightnessd.
final class FakeStore: BrightnessPropertyStore {
    var values: [String: Any]
    var rejectedKeys: Set<String> = []
    var writtenKeys: [String] = []

    init(values: [String: Any]) { self.values = values }

    func value(forKey key: String) -> Any? { values[key] }

    func setValue(_ value: Any, forKey key: String) -> Bool {
        guard !rejectedKeys.contains(key) else { return false }
        values[key] = value
        writtenKeys.append(key)
        return true
    }

    var mapping: NitsMapping? { NitsMapping(propertyList: values["LEPWMBrightnessNitsMapping"]) }
    var mode: Int? { (values["LEBacklightMode"] as? NSNumber)?.intValue }
}

let systemMapping = NitsMapping([
    .init(input: 0, output: 0),
    .init(input: 140, output: 150),
    .init(input: NitsMapping.unboundedInput, output: 1000),
])!

func state(min: Double = 67.5, max: Double = 508) -> [String: Any] {
    ["AppliedNits": 120.0, "DisplayNits": 113.6, "Lux": 76.0, "MinNitsRestriction": min, "MaxNitsRestriction": max]
}

func systemStore(mode: Int = 2) -> FakeStore {
    FakeStore(values: [
        "LEPWMState": state(),
        "LEBacklightMode": NSNumber(value: mode),
        "LEPWMBrightnessNitsMapping": systemMapping.propertyList,
        "DisplayNitsKey": NSNumber(value: 33.05),
    ])
}

@Suite struct NitsMappingTests {
    @Test func rejectsMalformedTables() {
        #expect(NitsMapping([]) == nil)
        #expect(NitsMapping([.init(input: 0, output: -1)]) == nil)
        #expect(NitsMapping([.init(input: 5, output: 1), .init(input: 5, output: 2)]) == nil)
        #expect(NitsMapping([.init(input: .infinity, output: 1)]) == nil)
        #expect(NitsMapping(propertyList: [[NSNumber(value: 1)]]) == nil)
    }

    @Test func roundTripsThroughPropertyList() {
        #expect(NitsMapping(propertyList: systemMapping.propertyList) == systemMapping)
        #expect(NitsMapping(propertyList: NitsMapping.constant(250).propertyList) == .constant(250))
    }
}

@Suite struct LogoBacklightTests {
    @Test func unsupportedWithoutLogoState() {
        #expect(LogoBacklight(store: FakeStore(values: [:])) == nil)
    }

    @Test func unknownModeReadsAsNil() {
        #expect(LogoBacklight(store: systemStore(mode: 1))?.mode == nil)
        #expect(LogoBacklight(store: systemStore(mode: 0))?.mode == .off)
    }

    @Test func newMappingResendsUnchangedScreenNitsToApplyImmediately() {
        let store = systemStore()
        LogoBacklight(store: store)!.setBrightnessMapping(.constant(300))
        #expect(store.writtenKeys == ["LEPWMBrightnessNitsMapping", "DisplayNitsKey"])
        #expect(store.values["DisplayNitsKey"] as? NSNumber == NSNumber(value: 33.05))
    }

    @Test func screenOffSkipsResend() {
        let store = systemStore()
        store.values["DisplayNitsKey"] = NSNumber(value: 0)
        LogoBacklight(store: store)!.setBrightnessMapping(.constant(300))
        #expect(store.writtenKeys == ["LEPWMBrightnessNitsMapping"])
    }

    @Test func fullRangeFollowsLoadedRestrictionTables() {
        let store = systemStore()
        let backlight = LogoBacklight(store: store)!
        store.values["LEPWMLuxToMinNitsRestrictionMapping"] = NitsMapping.constant(0).propertyList
        #expect(!backlight.isFullRangeUnlocked)
        store.values["LEPWMLuxToMaxNitsRestrictionMapping"] = NitsMapping.constant(1000).propertyList
        #expect(backlight.isFullRangeUnlocked)
    }
}

@Suite @MainActor struct LogoControllerTests {
    let defaults: UserDefaults

    init() {
        let suite = "LogoGlowCoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func takingAndReleasingControlRestoresSystemSettings() {
        let store = systemStore(mode: 0)
        let controller = LogoController(backlight: LogoBacklight(store: store)!, defaults: defaults)

        #expect(controller.setControlling(true))
        #expect(store.mapping == .constant(LogoController.nits(forBrightness: 0.5)))
        #expect(store.mode == 2)

        controller.setLightOn(false)
        controller.setBrightness(1)
        #expect(store.mode == 0)
        #expect(store.mapping == .constant(1000))

        #expect(controller.setControlling(false))
        #expect(store.mapping == systemMapping)
        #expect(store.mode == 0)
    }

    @Test func settingsDoNothingWhileMacOSControls() {
        let store = systemStore()
        let controller = LogoController(backlight: LogoBacklight(store: store)!, defaults: defaults)
        controller.setLightOn(false)
        controller.setBrightness(0.1)
        #expect(store.mapping == systemMapping)
        #expect(store.mode == 2)
    }

    @Test func relaunchAfterCrashKeepsOriginalSystemSettings() {
        let store = systemStore()
        LogoController(backlight: LogoBacklight(store: store)!, defaults: defaults).setControlling(true)

        // No suspend(): the app died while in control, so the logo still has our mapping.
        let relaunched = LogoController(backlight: LogoBacklight(store: store)!, defaults: defaults)
        #expect(relaunched.resume())
        relaunched.setControlling(false)
        #expect(store.mapping == systemMapping)
    }

    @Test func suspendHandsBackButResumesNextLaunch() {
        let store = systemStore()
        let controller = LogoController(backlight: LogoBacklight(store: store)!, defaults: defaults)
        controller.setControlling(true)
        controller.suspend()
        #expect(store.mapping == systemMapping)
        #expect(controller.isControlling)

        LogoController(backlight: LogoBacklight(store: store)!, defaults: defaults).resume()
        #expect(store.mapping == .constant(LogoController.nits(forBrightness: 0.5)))
    }

    @Test func failedRestoreKeepsSavedSettingsForRetry() {
        let store = systemStore()
        let controller = LogoController(backlight: LogoBacklight(store: store)!, defaults: defaults)
        controller.setControlling(true)

        store.rejectedKeys = ["LEPWMBrightnessNitsMapping"]
        #expect(!controller.setControlling(false))
        store.rejectedKeys = []
        #expect(controller.setControlling(false))
        #expect(store.mapping == systemMapping)
    }

    @Test func refusesControlWhenSystemMappingIsUnreadable() {
        let store = systemStore()
        store.values["LEPWMBrightnessNitsMapping"] = nil
        let controller = LogoController(backlight: LogoBacklight(store: store)!, defaults: defaults)
        #expect(!controller.setControlling(true))
        #expect(!controller.isControlling)
    }
}

@Suite struct FullRangeTests {
    @Test func unlockWritesTypedFlatTablesThenRestarts() {
        let command = FullRange.Action.unlock.command
        #expect(command.contains("LEPWMLuxToMinNitsRestrictionMapping '<array><array><real>0.0</real><real>0.0</real></array>"))
        #expect(command.contains("LEPWMLuxToMaxNitsRestrictionMapping '<array><array><real>0.0</real><real>1000.0</real></array>"))
        #expect(command.hasSuffix("&& /usr/bin/killall corebrightnessd"))
    }

    @Test func restoreRestartsEvenIfKeysAreMissing() {
        let command = FullRange.Action.restore.command
        #expect(command.contains("defaults delete com.apple.CoreBrightness LEPWMLuxToMinNitsRestrictionMapping 2>/dev/null;"))
        #expect(command.hasSuffix("; /usr/bin/killall corebrightnessd"))
    }

    @Test func commandsNeedNoAppleScriptEscaping() {
        for action in [FullRange.Action.unlock, .restore] {
            #expect(!action.command.contains("\"") && !action.command.contains("\\"))
        }
    }
}
