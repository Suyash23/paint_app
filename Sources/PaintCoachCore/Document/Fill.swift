import Foundation

/// A ColorDrop / bucket fill applied to a layer.
///
/// Like `Stroke`, this is stored as intent rather than pixels, so the renderer
/// can reproduce it at any resolution and undo stays a command-log operation.
public struct Fill: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var color: RGBA
    /// Where the drop landed, in canvas space. The renderer flood-fills from here.
    public var origin: Point
    /// Procreate's ColorDrop Threshold, 0...1 — how far a neighbouring colour may
    /// differ from the sampled colour and still be filled. 0 fills only an exact
    /// colour match; 1 fills the whole layer.
    public var threshold: Double

    public init(
        id: UUID = UUID(),
        color: RGBA,
        origin: Point,
        threshold: Double = 0.5
    ) {
        self.id = id
        self.color = color
        self.origin = origin
        self.threshold = Fill.clampThreshold(threshold)
    }

    /// Thresholds are clamped rather than rejected — the UI drags this value and
    /// overshoot at the ends of the gesture should saturate, not throw.
    static func clampThreshold(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
