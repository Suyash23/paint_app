import Foundation

/// Maps a normalized input (pressure, tilt, velocity) onto an output range.
///
/// `exponent` shapes the response: 1 is linear, > 1 biases toward the minimum
/// (needs firmer press before the value climbs), < 1 biases toward the maximum.
public struct ResponseCurve: Hashable, Codable, Sendable {
    public var minimum: Double
    public var maximum: Double
    public var exponent: Double

    public init(minimum: Double = 0, maximum: Double = 1, exponent: Double = 1) {
        self.minimum = minimum
        self.maximum = maximum
        self.exponent = exponent
    }

    /// Evaluates the curve. `input` is clamped to 0...1.
    public func value(for input: Double) -> Double {
        let t = min(max(input, 0), 1)
        let shaped = exponent == 1 ? t : pow(t, exponent)
        return minimum + (maximum - minimum) * shaped
    }

    /// Ignores the input and always returns 1 — used to disable a dynamic.
    public static let flat = ResponseCurve(minimum: 1, maximum: 1)

    /// Straight 0...1 passthrough.
    public static let linear = ResponseCurve()
}
