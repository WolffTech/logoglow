// SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
// SPDX-License-Identifier: GPL-2.0-only

import Foundation

/// A piecewise-linear lookup table in CoreBrightness's format: `[[input, outputNits], …]`.
/// Inputs are display nits or ambient lux depending on the table. corebrightnessd rejects
/// malformed tables, so construction enforces the same shape.
public struct NitsMapping: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public let input: Double
        public let output: Double

        public init(input: Double, output: Double) {
            self.input = input
            self.output = output
        }
    }

    /// The last input CoreBrightness uses to cover "everything above": `FLT_MAX`.
    public static let unboundedInput = Double(Float.greatestFiniteMagnitude)

    public let points: [Point]

    /// Fails unless there is at least one point, every value is finite, outputs are not
    /// negative, and inputs strictly increase.
    public init?(_ points: [Point]) {
        guard !points.isEmpty,
              points.allSatisfy({ $0.input.isFinite && $0.output.isFinite && $0.output >= 0 }),
              zip(points, points.dropFirst()).allSatisfy({ $0.input < $1.input })
        else { return nil }
        self.points = points
    }

    /// The same output for every input.
    public static func constant(_ nits: Double) -> NitsMapping {
        let nits = max(0, nits)
        // Two increasing finite points always validate.
        return NitsMapping([
            Point(input: 0, output: nits),
            Point(input: unboundedInput, output: nits),
        ])!
    }

    public init?(propertyList: Any?) {
        guard let rows = propertyList as? [[NSNumber]],
              rows.allSatisfy({ $0.count == 2 })
        else { return nil }
        self.init(rows.map { Point(input: $0[0].doubleValue, output: $0[1].doubleValue) })
    }

    public var propertyList: [[NSNumber]] {
        // CoreBrightness stores these as floats.
        points.map { [NSNumber(value: Float($0.input)), NSNumber(value: Float($0.output))] }
    }
}
