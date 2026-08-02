import Foundation

/// A small, fast, fully deterministic PRNG (SplitMix64).
///
/// Jitter must be reproducible: because rendering is a pure function of stroke
/// data, a stroke re-rendered later has to produce byte-identical marks. Seeding
/// from the stroke's UUID gives every stroke its own stable random sequence,
/// independent of render order or how many times it is redrawn.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        // Avoid the all-zero state, which would degenerate.
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    /// Derives a stable seed from a UUID.
    public init(uuid: UUID) {
        let bytes = withUnsafeBytes(of: uuid.uuid) { raw -> (UInt64, UInt64) in
            var high: UInt64 = 0
            var low: UInt64 = 0
            for i in 0..<8 { high = (high << 8) | UInt64(raw[i]) }
            for i in 8..<16 { low = (low << 8) | UInt64(raw[i]) }
            return (high, low)
        }
        self.init(seed: bytes.0 ^ bytes.1)
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform value in 0..<1.
    public mutating func nextUnit() -> Double {
        // Use the top 53 bits for a clean double mantissa.
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }

    /// Uniform value in -1...1.
    public mutating func nextSigned() -> Double {
        nextUnit() * 2 - 1
    }
}
