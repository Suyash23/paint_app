import Foundation

/// One sampled Apple Pencil / touch input event along a stroke.
public struct StrokePoint: Hashable, Codable, Sendable {
    public var position: Point
    /// Normalized pressure, 0...1. Touch fallback reports 0.5.
    public var pressure: Double
    /// Pencil altitude in radians (π/2 == perpendicular to the screen).
    public var altitude: Double
    /// Pencil azimuth in radians.
    public var azimuth: Double
    /// Seconds since the start of the stroke.
    public var timestamp: Double

    public init(
        position: Point,
        pressure: Double = 0.5,
        altitude: Double = .pi / 2,
        azimuth: Double = 0,
        timestamp: Double = 0
    ) {
        self.position = position
        self.pressure = pressure
        self.altitude = altitude
        self.azimuth = azimuth
        self.timestamp = timestamp
    }
}

/// A committed mark on a layer: brush settings plus the input path.
/// Rendering is a pure function of this data — no pixels are stored in the document.
public struct Stroke: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var brushID: String
    public var color: RGBA
    /// Brush size as a fraction of the max brush diameter, 0...1 (Procreate's Size %).
    public var size: Double
    /// Brush opacity, 0...1.
    public var opacity: Double
    public var points: [StrokePoint]

    public init(
        id: UUID = UUID(),
        brushID: String,
        color: RGBA,
        size: Double,
        opacity: Double,
        points: [StrokePoint]
    ) {
        self.id = id
        self.brushID = brushID
        self.color = color
        self.size = size
        self.opacity = opacity
        self.points = points
    }
}
