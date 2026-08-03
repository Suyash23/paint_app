import Foundation

/// Detects the "hold still" gesture that arms QuickShape.
///
/// Pure and clock-free: timestamps arrive with the samples, so this can be
/// tested with synthetic input and never needs a real timer.
public struct PauseDetector {

    /// How long the pencil must stay within `movementTolerance` to count as a pause.
    public var pauseDuration: Double
    /// How far the pencil may drift during a pause, in canvas pixels.
    public var movementTolerance: Double

    /// Where the current candidate pause began.
    private var anchor: Point?
    private var anchorTime: Double?
    /// Latches so a single sustained hold arms QuickShape exactly once.
    private var hasFired: Bool = false

    public init(pauseDuration: Double = 0.4, movementTolerance: Double = 4) {
        self.pauseDuration = pauseDuration
        self.movementTolerance = movementTolerance
    }

    /// True once the current hold has been reported.
    public var isPaused: Bool { hasFired }

    /// Feeds a sample. Returns true on the single sample where a pause is first
    /// recognised, so the caller can arm QuickShape without re-firing.
    @discardableResult
    public mutating func accept(position: Point, timestamp: Double) -> Bool {
        guard let anchor, let anchorTime else {
            self.anchor = position
            self.anchorTime = timestamp
            return false
        }

        // Drifting outside the tolerance restarts the candidate pause, which also
        // re-arms the detector for a later hold in the same stroke.
        if position.distance(to: anchor) > movementTolerance {
            self.anchor = position
            self.anchorTime = timestamp
            hasFired = false
            return false
        }

        guard !hasFired, timestamp - anchorTime >= pauseDuration else { return false }
        hasFired = true
        return true
    }

    /// Clears all state, ready for the next stroke.
    public mutating func reset() {
        anchor = nil
        anchorTime = nil
        hasFired = false
    }
}
