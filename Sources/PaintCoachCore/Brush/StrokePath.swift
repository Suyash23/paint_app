import Foundation

/// Catmull-Rom interpolation over the sampled input points.
///
/// The spline passes exactly through every input point, so smoothing never pulls
/// the stroke away from where the user drew.
public enum StrokePath {

    /// Interpolates a point on the centripetal Catmull-Rom spline through
    /// `p1`...`p2`, where `p0` and `p3` are the surrounding control points.
    public static func interpolate(
        _ p0: Point, _ p1: Point, _ p2: Point, _ p3: Point, t: Double
    ) -> Point {
        let t2 = t * t
        let t3 = t2 * t
        // Standard Catmull-Rom basis with tension 0.5.
        let x = 0.5 * ((2 * p1.x)
            + (-p0.x + p2.x) * t
            + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
            + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
        let y = 0.5 * ((2 * p1.y)
            + (-p0.y + p2.y) * t
            + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
            + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
        return Point(x, y)
    }

    /// Densifies a stroke's input points into a smooth polyline, carrying the
    /// per-point pencil data along by interpolation.
    ///
    /// `subdivisions` is the number of segments generated between each pair of
    /// input points. Returns the input unchanged when there is nothing to smooth.
    public static func smooth(_ points: [StrokePoint], subdivisions: Int = 8) -> [StrokePoint] {
        guard points.count > 2, subdivisions > 1 else { return points }

        var result: [StrokePoint] = [points[0]]
        result.reserveCapacity(points.count * subdivisions)

        for i in 0..<(points.count - 1) {
            // Clamp the control points at the ends of the stroke.
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(i + 2, points.count - 1)]

            for step in 1...subdivisions {
                let t = Double(step) / Double(subdivisions)
                let position = interpolate(p0.position, p1.position, p2.position, p3.position, t: t)
                result.append(
                    StrokePoint(
                        position: position,
                        pressure: lerp(p1.pressure, p2.pressure, t),
                        altitude: lerp(p1.altitude, p2.altitude, t),
                        azimuth: lerp(p1.azimuth, p2.azimuth, t),
                        timestamp: lerp(p1.timestamp, p2.timestamp, t)
                    )
                )
            }
        }
        return result
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}
