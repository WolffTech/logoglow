// SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
// SPDX-License-Identifier: GPL-2.0-only

import Foundation
import Testing
@testable import LogoGlowCore

/// In-memory stand-in for corebrightnessd.
final class FakeStore: BrightnessPropertyStore {
    enum LightingWrite: Equatable {
        case fadeDuration(Double)
        case logo(Int)
        case keyboards(Int)
    }

    var values: [String: Any]
    var rejectedKeys: Set<String> = []
    var writtenKeys: [String] = []
    var lightingWrites: [LightingWrite] = []

    init(values: [String: Any]) { self.values = values }

    func value(forKey key: String) -> Any? { values[key] }

    func setValue(_ value: Any, forKey key: String) -> Bool {
        guard !rejectedKeys.contains(key) else { return false }
        values[key] = value
        writtenKeys.append(key)
        switch key {
        case "LEPWMFactorFadeDuration": lightingWrites.append(.fadeDuration((value as! NSNumber).doubleValue))
        case "DisplayLogicalState": lightingWrites.append(.logo((value as! NSNumber).intValue))
        default: break
        }
        return true
    }

    func setValueOnKeyboards(_ value: Any, forKey key: String) {
        #expect(key == "DisplayLogicalState")
        lightingWrites.append(.keyboards((value as! NSNumber).intValue))
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

@Suite struct LogoEffectTests {
    @Test func stepsMatchTheTestedTimings() {
        #expect(LogoEffect.breathe.steps == [.dip(lasting: 2.5), .rise(over: 3.5, hold: 0.3)])
        #expect(LogoEffect.pulse.steps == [.dip(lasting: 0.8), .rise(over: 1.2, hold: 0.15)])
        #expect(LogoEffect.heartbeat.steps == [
            .rise(over: 0.12, hold: 0.05), .dip(lasting: 0.26),
            .rise(over: 0.12, hold: 0.05), .dip(lasting: 0.95),
        ])
        #expect(abs(LogoEffect.breathe.cycleLength - 6.3) < 1e-9)
        #expect(abs(LogoEffect.pulse.cycleLength - 2.15) < 1e-9)
        #expect(abs(LogoEffect.heartbeat.cycleLength - 1.55) < 1e-9)
    }

    @Test func stepsAlternateSoEveryDipIsFollowedByARise() {
        for effect in LogoEffect.allCases {
            let directions = effect.steps.map(\.direction)
            #expect(zip(directions, directions.dropFirst() + directions.prefix(1)).allSatisfy { $0 != $1 })
        }
    }

    @Test func dipsAreCutBeforeTheLogoReachesDark() {
        for step in LogoEffect.allCases.flatMap(\.steps) where step.direction == .dip {
            #expect(abs(step.length / step.fadeDuration - FadeStep.dipCutFraction) < 1e-9)
        }
        let heartbeatInnerDip = FadeStep.dip(lasting: 0.26)
        #expect(abs(heartbeatInnerDip.fadeDuration - 0.361) < 0.001)
    }

    @Test func riseHoldsAfterItsFade() {
        let rise = FadeStep.rise(over: 3.5, hold: 0.3)
        #expect(rise.fadeDuration == 3.5)
        #expect(abs(rise.length - 3.8) < 1e-9)
    }
}

@Suite struct LogoBacklightFadeTests {
    @Test func dipSetsDurationBeforeBlankingAndKeepsKeyboardsLit() {
        let store = systemStore()
        LogoBacklight(store: store)!.fade(.dip, over: 2)
        #expect(store.lightingWrites == [.fadeDuration(2), .logo(1), .keyboards(2)])
    }

    @Test func riseLeavesKeyboardsAlone() {
        let store = systemStore()
        LogoBacklight(store: store)!.fade(.rise, over: 0.12)
        #expect(store.lightingWrites == [.fadeDuration(0.12), .logo(2)])
    }

    @Test func rejectedDurationSkipsTheFade() {
        let store = systemStore()
        store.rejectedKeys = ["LEPWMFactorFadeDuration"]
        #expect(!LogoBacklight(store: store)!.fade(.dip, over: 2))
        #expect(store.lightingWrites.isEmpty)
    }
}

@Suite @MainActor struct EffectLifecycleTests {
    let defaults: UserDefaults
    let store = systemStore()
    let clock = ManualClock()
    let restoreWrites: [FakeStore.LightingWrite] = [.fadeDuration(0.3), .logo(1), .keyboards(2)]
    let restoreFinishWrites: [FakeStore.LightingWrite] = [.fadeDuration(0.3), .logo(2), .fadeDuration(0)]

    init() {
        let suite = "LogoGlowCoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    func makeController() -> LogoController {
        LogoController(backlight: LogoBacklight(store: store)!, defaults: defaults, clock: clock)
    }

    func controllingBreathe() async -> LogoController {
        let controller = makeController()
        controller.setControlling(true)
        controller.setEffect(.breathe)
        await clock.settle()
        store.lightingWrites = []
        return controller
    }

    func finishRestore() async -> [FakeStore.LightingWrite] {
        store.lightingWrites = []
        await clock.advance(by: .milliseconds(50))
        await clock.advance(by: .seconds(1))
        return store.lightingWrites
    }

    @Test func effectLoopsThroughItsStepsOnSchedule() async {
        let controller = makeController()
        controller.setControlling(true)
        controller.setEffect(.pulse)
        await clock.settle()
        #expect(store.lightingWrites == [.fadeDuration(0.8 / 0.72), .logo(1), .keyboards(2)])

        store.lightingWrites = []
        await clock.advance(by: .milliseconds(799))
        #expect(store.lightingWrites.isEmpty)
        await clock.advance(by: .milliseconds(1))
        #expect(store.lightingWrites == [.fadeDuration(1.2), .logo(2)])

        store.lightingWrites = []
        await clock.advance(by: .milliseconds(1350))
        #expect(store.lightingWrites.first == .fadeDuration(0.8 / 0.72))
    }

    @Test func choosingSteadyStopsTheLoopAndRestoresNormalLighting() async {
        let controller = await controllingBreathe()
        controller.setEffect(nil)
        #expect(store.lightingWrites == restoreWrites)
        #expect(await finishRestore() == restoreFinishWrites)

        store.lightingWrites = []
        await clock.advance(by: .seconds(30))
        #expect(store.lightingWrites.isEmpty)
    }

    @Test func stepAlreadyDueWhenStoppingIsDropped() async {
        let controller = await controllingBreathe()
        clock.advanceWithoutRunning(by: .milliseconds(2500))
        controller.setEffect(nil)
        await clock.settle()
        #expect(store.lightingWrites == restoreWrites)
    }

    @Test func turningTheLogoOffRestoresAndTurningOnResumes() async {
        let controller = await controllingBreathe()
        controller.setLightOn(false)
        #expect(store.lightingWrites == restoreWrites)
        #expect(store.mode == 0)
        #expect(await finishRestore() == restoreFinishWrites)

        store.lightingWrites = []
        controller.setEffect(.pulse)
        await clock.settle()
        #expect(store.lightingWrites.isEmpty)

        controller.setLightOn(true)
        await clock.settle()
        #expect(store.lightingWrites.prefix(2) == [.fadeDuration(0.8 / 0.72), .logo(1)])
    }

    @Test func handingBackRestoresLightingAndSystemSettings() async {
        let controller = await controllingBreathe()
        controller.setControlling(false)
        #expect(store.lightingWrites == restoreWrites)
        #expect(store.mapping == systemMapping)
        #expect(await finishRestore() == restoreFinishWrites)
    }

    @Test func quittingWaitsForTheRestore() async {
        let controller = await controllingBreathe()
        controller.suspend()
        let waiter = Task { await controller.waitUntilRestored() }
        await clock.advance(by: .milliseconds(50))
        await clock.advance(by: .seconds(1))
        await waiter.value
        #expect(store.lightingWrites.last == .fadeDuration(0))
        #expect(controller.effect == .breathe)
    }

    @Test func displaySleepResetsFadeDurationAndWakeRestarts() async {
        let controller = await controllingBreathe()
        controller.displayDidSleep()
        #expect(store.lightingWrites == [.fadeDuration(0)])

        await clock.advance(by: .seconds(30))
        #expect(store.lightingWrites == [.fadeDuration(0)])

        store.lightingWrites = []
        controller.displayDidWake()
        await clock.settle()
        #expect(store.lightingWrites.prefix(2) == [.fadeDuration(2.5 / 0.72), .logo(1)])
    }

    @Test func steadyIgnoresDisplaySleepAndSkipsRestore() async {
        let controller = makeController()
        controller.setControlling(true)
        controller.displayDidSleep()
        controller.displayDidWake()
        controller.setControlling(false)
        await clock.advance(by: .seconds(5))
        #expect(store.lightingWrites.isEmpty)
    }

    @Test func chosenEffectSurvivesRelaunch() async {
        _ = await controllingBreathe()
        let relaunched = makeController()
        #expect(relaunched.effect == .breathe)
        relaunched.resume()
        await clock.settle()
        #expect(store.lightingWrites.prefix(2) == [.fadeDuration(2.5 / 0.72), .logo(1)])
    }
}
