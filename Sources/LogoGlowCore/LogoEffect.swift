// SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
// SPDX-License-Identifier: GPL-2.0-only

import Foundation

public enum FadeDirection: Sendable {
    case rise
    case dip
}

public struct FadeStep: Equatable, Sendable {
    public let direction: FadeDirection
    public let fadeDuration: Double
    public let length: Double

    public static func rise(over fadeDuration: Double, hold: Double) -> FadeStep {
        FadeStep(direction: .rise, fadeDuration: fadeDuration, length: fadeDuration + hold)
    }

    public static func dip(lasting length: Double) -> FadeStep {
        FadeStep(direction: .dip, fadeDuration: length / dipCutFraction, length: length)
    }

    public static let dipCutFraction = 0.72
}

public enum LogoEffect: String, CaseIterable, Sendable {
    case breathe
    case pulse
    case heartbeat

    public var steps: [FadeStep] {
        switch self {
        case .breathe:
            [.dip(lasting: 2.5), .rise(over: 3.5, hold: 0.3)]
        case .pulse:
            [.dip(lasting: 0.8), .rise(over: 1.2, hold: 0.15)]
        case .heartbeat:
            [
                .rise(over: 0.12, hold: 0.05),
                .dip(lasting: 0.26),
                .rise(over: 0.12, hold: 0.05),
                .dip(lasting: 0.95),
            ]
        }
    }

    public var cycleLength: Double {
        steps.reduce(0) { $0 + $1.length }
    }
}
