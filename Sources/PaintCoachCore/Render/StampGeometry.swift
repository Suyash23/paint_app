import Foundation

/// Pure geometry helpers bridging brush stamps to the regions a renderer must
/// touch. Kept free of GPU concepts so it stays unit-testable.
public enum StampGeometry {

    /// The axis-aligned bounds a single stamp can paint into.
    ///
    /// A stamp is an ellipse of width `diameter * eccentricity` and height
    /// `diameter`, rotated by `rotation`. Rather than solving the exact rotated
    /// ellipse extent, this bounds it by the circle enclosing its major axis:
    /// slightly conservative, never too small, and rotation-independent.
    public static func bounds(of stamp: BrushStamp) -> Rect {
        let major = stamp.diameter * max(stamp.eccentricity, 1)
        let radius = major / 2
        return Rect(
            x: stamp.position.x - radius,
            y: stamp.position.y - radius,
            width: major,
            height: major
        )
    }

    /// The bounds covering every stamp, or `nil` when there are none.
    public static func bounds(of stamps: [BrushStamp]) -> Rect? {
        guard !stamps.isEmpty else { return nil }
        return stamps.dropFirst().reduce(bounds(of: stamps[0])) { $0.union(bounds(of: $1)) }
    }

    /// The region a stroke will paint into, given the brush that draws it.
    ///
    /// This runs the engine, so it is exact rather than an estimate from the
    /// input points — pressure-driven size and jitter are already accounted for.
    public static func bounds(of stroke: Stroke, brush: Brush, subdivisions: Int = 8) -> Rect? {
        bounds(of: BrushEngine(brush: brush, subdivisions: subdivisions).stamps(for: stroke))
    }

    /// Splits a stamp run into contiguous batches whose bounds stay within
    /// `maxArea`. Lets a renderer flush incrementally on long strokes instead of
    /// dirtying one enormous region.
    public static func batches(of stamps: [BrushStamp], maxArea: Double) -> [[BrushStamp]] {
        guard !stamps.isEmpty else { return [] }
        guard maxArea > 0 else { return [stamps] }

        var batches: [[BrushStamp]] = []
        var current: [BrushStamp] = []
        var currentBounds = Rect.zero

        for stamp in stamps {
            let candidate = currentBounds.union(bounds(of: stamp))
            if !current.isEmpty, candidate.width * candidate.height > maxArea {
                batches.append(current)
                current = [stamp]
                currentBounds = bounds(of: stamp)
            } else {
                current.append(stamp)
                currentBounds = candidate
            }
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }
}
