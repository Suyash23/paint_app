import Foundation

/// A single stamp of the brush tip along a stroke path.
///
/// This is the brush engine's entire output — the renderer consumes stamps and
/// knows nothing about pressure, tilt, or interpolation.
public struct BrushStamp: Hashable, Sendable {
    /// Centre of the stamp in canvas space.
    public var position: Point
    /// Stamp diameter in canvas pixels.
    public var diameter: Double
    /// Per-stamp alpha, 0...1.
    public var opacity: Double
    /// Rotation in radians.
    public var rotation: Double
    /// Width/height ratio, 1 being circular. Driven by pencil tilt.
    public var eccentricity: Double

    public init(
        position: Point,
        diameter: Double,
        opacity: Double,
        rotation: Double = 0,
        eccentricity: Double = 1
    ) {
        self.position = position
        self.diameter = diameter
        self.opacity = opacity
        self.rotation = rotation
        self.eccentricity = eccentricity
    }
}

/// Static configuration for a brush. Contains no per-stroke state, so a single
/// value can safely render any number of strokes.
public struct Brush: Hashable, Codable, Sendable {
    public var id: String
    public var name: String

    /// Brush diameter in canvas pixels at `Stroke.size == 1`.
    public var maxDiameter: Double

    /// Gap between stamps as a fraction of the current stamp diameter.
    /// 0.05 is dense (solid line); 1.0 leaves stamps just touching.
    public var spacing: Double

    /// Pressure → stamp diameter, as a fraction of the stroke's size.
    public var sizeDynamics: ResponseCurve
    /// Pressure → stamp alpha, as a fraction of the stroke's opacity.
    public var opacityDynamics: ResponseCurve
    /// Tilt → eccentricity. Evaluated on *flatness*, so a perpendicular pencil
    /// gives input 0 and a flat pencil gives input 1.
    public var tiltDynamics: ResponseCurve

    /// Positional scatter perpendicular to the path, as a fraction of diameter.
    public var jitterAmount: Double
    /// Random per-stamp rotation, in radians.
    public var rotationJitter: Double

    /// Whether stamps rotate to follow the direction of travel.
    public var followsDirection: Bool

    public init(
        id: String,
        name: String,
        maxDiameter: Double,
        spacing: Double = 0.1,
        sizeDynamics: ResponseCurve = ResponseCurve(minimum: 0.25, maximum: 1),
        opacityDynamics: ResponseCurve = .flat,
        tiltDynamics: ResponseCurve = .flat,
        jitterAmount: Double = 0,
        rotationJitter: Double = 0,
        followsDirection: Bool = false
    ) {
        self.id = id
        self.name = name
        self.maxDiameter = maxDiameter
        self.spacing = spacing
        self.sizeDynamics = sizeDynamics
        self.opacityDynamics = opacityDynamics
        self.tiltDynamics = tiltDynamics
        self.jitterAmount = jitterAmount
        self.rotationJitter = rotationJitter
        self.followsDirection = followsDirection
    }
}

extension Brush {
    /// Hard-edged inking pen: pressure drives size, opacity stays solid.
    public static let studioPen = Brush(
        id: "studio-pen",
        name: "Studio Pen",
        maxDiameter: 120,
        spacing: 0.05,
        sizeDynamics: ResponseCurve(minimum: 0.3, maximum: 1, exponent: 1.2)
    )

    /// Soft pencil: pressure drives opacity, tilt broadens the stroke.
    public static let softPencil = Brush(
        id: "soft-pencil",
        name: "Soft Pencil",
        maxDiameter: 90,
        spacing: 0.08,
        sizeDynamics: ResponseCurve(minimum: 0.6, maximum: 1),
        opacityDynamics: ResponseCurve(minimum: 0.15, maximum: 0.9, exponent: 1.5),
        tiltDynamics: ResponseCurve(minimum: 1, maximum: 2.2),
        jitterAmount: 0.04,
        rotationJitter: .pi
    )
}
