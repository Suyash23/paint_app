import Foundation

/// Accumulates input samples into a stroke while the user is drawing.
///
/// Pure and platform-free, so touch handling can be tested with synthetic input.
/// The UIKit layer's only job is to translate `UITouch` into `StrokePoint` and
/// feed it here.
public struct StrokeBuilder {

    /// Settled samples — these will not change.
    public private(set) var committed: [StrokePoint] = []
    /// Speculative samples from touch prediction, replaced on every update and
    /// discarded when the stroke ends. Drawn but never committed.
    public private(set) var predicted: [StrokePoint] = []

    public let brushID: String
    public let color: RGBA
    public let size: Double
    public let opacity: Double

    /// Minimum distance between accepted samples, in canvas pixels. Filters the
    /// jitter a stationary pencil produces without losing genuine slow strokes.
    public var minimumDistance: Double

    /// Time of the first sample, used to make timestamps stroke-relative.
    private var startTime: Double?

    public init(
        brushID: String,
        color: RGBA,
        size: Double,
        opacity: Double,
        minimumDistance: Double = 0.75
    ) {
        self.brushID = brushID
        self.color = color
        self.size = size
        self.opacity = opacity
        self.minimumDistance = minimumDistance
    }

    public var isEmpty: Bool { committed.isEmpty }

    /// Every sample to draw this frame: settled followed by predicted.
    public var allPoints: [StrokePoint] {
        committed + predicted
    }

    // MARK: - Sample intake

    /// Adds a settled sample. Returns false when it was filtered out.
    ///
    /// `timestamp` is an absolute time; it is rebased so the first sample of a
    /// stroke is t=0, which is what the brush engine's dynamics expect.
    @discardableResult
    public mutating func append(_ point: StrokePoint) -> Bool {
        let rebased = rebase(point)

        guard let last = committed.last else {
            committed.append(rebased)
            return true
        }
        // Always keep a sample that carries new pressure, even if the pencil has
        // barely moved — a press without motion is a real gesture.
        let moved = last.position.distance(to: rebased.position)
        let pressureChanged = abs(last.pressure - rebased.pressure) > 0.02
        guard moved >= minimumDistance || pressureChanged else { return false }

        committed.append(rebased)
        return true
    }

    /// Adds several settled samples, e.g. from `coalescedTouches`.
    /// Returns how many survived filtering.
    @discardableResult
    public mutating func append(contentsOf points: [StrokePoint]) -> Int {
        points.reduce(0) { count, point in
            append(point) ? count + 1 : count
        }
    }

    /// Replaces the speculative tail from `predictedTouches`.
    ///
    /// Prediction is always replaced wholesale rather than accumulated — stale
    /// predictions are wrong by definition once real samples arrive.
    public mutating func setPredicted(_ points: [StrokePoint]) {
        predicted = points.map(rebase)
    }

    public mutating func clearPredicted() {
        predicted.removeAll()
    }

    private func rebase(_ point: StrokePoint) -> StrokePoint {
        var copy = point
        copy.timestamp = point.timestamp - (startTime ?? point.timestamp)
        return copy
    }

    /// Records the stroke's start time so timestamps can be made relative.
    /// Call before the first `append`.
    public mutating func begin(at timestamp: Double) {
        startTime = timestamp
    }

    // MARK: - Output

    /// The stroke as it should be drawn *right now*, including prediction.
    ///
    /// Uses a stable id so the brush engine's UUID-seeded jitter does not
    /// reshuffle every frame while the stroke is being drawn.
    public func liveStroke(id: UUID) -> Stroke? {
        let points = allPoints
        guard !points.isEmpty else { return nil }
        return Stroke(id: id, brushID: brushID, color: color, size: size, opacity: opacity, points: points)
    }

    /// The finished stroke, excluding prediction. This is what gets committed to
    /// the document — speculative samples must never be persisted.
    public func finalStroke(id: UUID = UUID()) -> Stroke? {
        guard !committed.isEmpty else { return nil }
        return Stroke(id: id, brushID: brushID, color: color, size: size, opacity: opacity, points: committed)
    }
}
