// SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
// SPDX-License-Identifier: GPL-2.0-only

import Foundation

@MainActor
public final class EffectPlayer {
    private enum Activity {
        case idle
        case playing(Task<Void, Never>)
        case restoring(Task<Void, Never>)
    }

    private typealias SleepUntilOffset = @Sendable (Duration) async throws -> Void

    private let backlight: LogoBacklight
    private let startTimeline: @Sendable () -> SleepUntilOffset
    private var activity = Activity.idle

    public init<C: Clock<Duration>>(backlight: LogoBacklight, clock: C) {
        self.backlight = backlight
        startTimeline = {
            let start = clock.now
            return { offset in try await clock.sleep(until: start.advanced(by: offset), tolerance: nil) }
        }
    }

    public var isPlaying: Bool {
        if case .playing = activity { true } else { false }
    }

    public func play(_ effect: LogoEffect) {
        cancelActivity()
        let sleep = startTimeline()
        let backlight = backlight
        activity = .playing(Task {
            var elapsed = Duration.zero
            while true {
                for step in effect.steps {
                    guard !Task.isCancelled else { return }
                    backlight.fade(step.direction, over: step.fadeDuration)
                    elapsed += .seconds(step.length)
                    do { try await sleep(elapsed) } catch { return }
                }
            }
        })
    }

    public func stop() {
        guard isPlaying else { return }
        cancelActivity()
        backlight.fade(.dip, over: Self.restoreFadeDuration)
        let sleep = startTimeline()
        let backlight = backlight
        activity = .restoring(Task {
            do { try await sleep(Self.restoreBlankHold) } catch { return }
            backlight.fade(.rise, over: Self.restoreFadeDuration)
            do { try await sleep(Self.restoreBlankHold + Self.restoreRiseSettle) } catch { return }
            backlight.resetFadeDuration()
        })
    }

    public func pauseForDisplaySleep() {
        if case .idle = activity { return }
        cancelActivity()
        backlight.resetFadeDuration()
    }

    public func waitUntilRestored() async {
        if case .restoring(let task) = activity { await task.value }
    }

    private func cancelActivity() {
        switch activity {
        case .idle: break
        case .playing(let task), .restoring(let task): task.cancel()
        }
        activity = .idle
    }

    static let restoreFadeDuration = 0.3
    static let restoreBlankHold = Duration.milliseconds(50)
    static let restoreRiseSettle = Duration.seconds(1)
}
