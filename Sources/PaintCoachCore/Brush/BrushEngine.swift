import Foundation

/// Turns a `Stroke` into evenly-spaced `BrushStamp`s.
///
/// Pure and deterministic: the same stroke and brush always produce identical
/// stamps, which is what lets the renderer treat stroke data as the sole source
/// of truth and re-render freely.
public struct BrushEngine {
    public var brush: Brush
    /// Catmull-Rom segments generated between each pair of input points.
    public var subdivisions: Int

    public init(brush: Brush, subdivisions: Int = 8) {
        self.brush = brush
        self.subdivisions = subdivisions
    }

    /// Generates the stamps for a stroke, in order from start to end.
    public func stamps(for stroke: Stroke) -> [BrushStamp] {
        guard !stroke.points.isEmpty else { return [] }

        var rng = SeededGenerator(uuid: stroke.id)

        // A single tap still deposits one stamp.
        guard stroke.points.count > 1 else {
            return [stamp(at: stroke.points[0], direction: 0, stroke: stroke, rng: &rng)]
        }

        let path = StrokePath.smooth(stroke.points, subdivisions: subdivisions)
        var stamps: [BrushStamp] = []
        stamps.reserveCapacity(path.count)

        // Emit the first stamp, then walk the path depositing one every
        // `spacing * diameter` pixels of arc length.
        var previous = path[0]
        var distanceSinceLastStamp = 0.0
        stamps.append(stamp(at: previous, direction: direction(from: path[0], to: path[1]), stroke: stroke, rng: &rng))

        for current in path.dropFirst() {
            let segment = previous.position.distance(to: current.position)
            guard segment > 0 else { continue }

            let heading = direction(from: previous, to: current)
            var travelled = 0.0

            while true {
                let diameter = self.diameter(for: current, stroke: stroke)
                let step = max(brush.spacing * diameter, 0.01)
                let remaining = step - distanceSinceLastStamp

                guard travelled + remaining <= segment else {
                    // Not enough room left in this segment; carry the surplus over.
                    distanceSinceLastStamp += segment - travelled
                    break
                }

                travelled += remaining
                distanceSinceLastStamp = 0

                let t = travelled / segment
                let interpolated = StrokePoint(
                    position: previous.position.lerp(to: current.position, t),
                    pressure: previous.pressure + (current.pressure - previous.pressure) * t,
                    altitude: previous.altitude + (current.altitude - previous.altitude) * t,
                    azimuth: previous.azimuth + (current.azimuth - previous.azimuth) * t,
                    timestamp: previous.timestamp + (current.timestamp - previous.timestamp) * t
                )
                stamps.append(stamp(at: interpolated, direction: heading, stroke: stroke, rng: &rng))
            }
            previous = current
        }
        return stamps
    }

    // MARK: - Per-stamp evaluation

    private func diameter(for point: StrokePoint, stroke: Stroke) -> Double {
        let base = brush.maxDiameter * stroke.size
        return base * brush.sizeDynamics.value(for: point.pressure)
    }

    private func stamp(
        at point: StrokePoint,
        direction heading: Double,
        stroke: Stroke,
        rng: inout SeededGenerator
    ) -> BrushStamp {
        let diameter = self.diameter(for: point, stroke: stroke)
        let opacity = stroke.opacity * brush.opacityDynamics.value(for: point.pressure)

        // Altitude π/2 is perpendicular; 0 is flat against the screen.
        let flatness = 1 - min(max(point.altitude / (.pi / 2), 0), 1)
        let eccentricity = brush.tiltDynamics.value(for: flatness)

        var position = point.position
        if brush.jitterAmount > 0 {
            // Scatter perpendicular to the direction of travel.
            let offset = rng.nextSigned() * brush.jitterAmount * diameter
            position = Point(
                position.x + cos(heading + .pi / 2) * offset,
                position.y + sin(heading + .pi / 2) * offset
            )
        }

        var rotation = brush.followsDirection ? heading : 0
        if brush.rotationJitter > 0 {
            rotation += rng.nextSigned() * brush.rotationJitter
        }

        return BrushStamp(
            position: position,
            diameter: diameter,
            opacity: min(max(opacity, 0), 1),
            rotation: rotation,
            eccentricity: eccentricity
        )
    }

    private func direction(from a: StrokePoint, to b: StrokePoint) -> Double {
        atan2(b.position.y - a.position.y, b.position.x - a.position.x)
    }
}
