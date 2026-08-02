import Foundation

/// Drives one drawing gesture from first touch to commit.
///
/// Pure orchestration: owns no UIKit and no GPU objects, so the whole gesture
/// lifecycle — including cancellation and the locked-layer case — is testable
/// with synthetic input.
public struct StrokeSession {

    public enum State: Equatable {
        case idle
        /// A stroke is in progress on the given layer.
        case drawing(layerID: UUID)
    }

    public private(set) var state: State = .idle
    private var builder: StrokeBuilder?
    /// Stable id for the in-flight stroke, so jitter does not reshuffle per frame.
    private var liveID = UUID()

    public init() {}

    public var isDrawing: Bool { state != .idle }

    /// The stroke to render this frame, prediction included.
    public var liveStroke: Stroke? {
        builder?.liveStroke(id: liveID)
    }

    // MARK: - Gesture lifecycle

    /// Begins a stroke, or returns nil when the target layer cannot accept paint.
    ///
    /// Refusing here rather than at commit time means no marks appear on a locked
    /// or hidden layer, instead of appearing and then vanishing.
    @discardableResult
    public mutating func begin(
        layer: Layer,
        brushID: String,
        color: RGBA,
        size: Double,
        opacity: Double,
        at timestamp: Double,
        minimumDistance: Double = 0.75
    ) -> Bool {
        guard layer.isPaintable else { return false }

        var newBuilder = StrokeBuilder(
            brushID: brushID,
            color: color,
            size: size,
            opacity: opacity,
            minimumDistance: minimumDistance
        )
        newBuilder.begin(at: timestamp)
        builder = newBuilder
        liveID = UUID()
        state = .drawing(layerID: layer.id)
        return true
    }

    /// Feeds settled samples, optionally replacing the predicted tail.
    @discardableResult
    public mutating func move(
        coalesced: [StrokePoint],
        predicted: [StrokePoint] = []
    ) -> Bool {
        guard case .drawing = state, builder != nil else { return false }
        builder!.append(contentsOf: coalesced)
        builder!.setPredicted(predicted)
        return true
    }

    /// Ends the stroke and returns the command to apply, or nil if nothing was drawn.
    ///
    /// Prediction is dropped here: speculative samples are for display only and
    /// must never reach the document.
    public mutating func end() -> (command: DocumentCommand, stroke: Stroke)? {
        guard case let .drawing(layerID) = state, var finished = builder else {
            reset()
            return nil
        }
        finished.clearPredicted()
        defer { reset() }

        guard let stroke = finished.finalStroke() else { return nil }
        return (.addStroke(layerID: layerID, stroke: stroke), stroke)
    }

    /// Abandons the stroke, discarding everything.
    public mutating func cancel() {
        reset()
    }

    private mutating func reset() {
        builder = nil
        state = .idle
    }
}
