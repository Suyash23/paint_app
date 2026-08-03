import Foundation

/// A shape QuickShape can recognise from a freehand stroke.
public enum QuickShapeKind: String, Hashable, Codable, Sendable, CaseIterable {
    case line
    case ellipse
    case rectangle
}

/// The result of fitting a freehand stroke to an ideal shape.
public struct QuickShape: Hashable, Sendable {
    public let kind: QuickShapeKind
    /// The idealised outline, in canvas space. Closed shapes repeat the first
    /// point at the end so the renderer can stroke them without special-casing.
    public let points: [Point]
    /// How well the original stroke matched, 0...1. Higher is a better fit.
    public let confidence: Double

    public init(kind: QuickShapeKind, points: [Point], confidence: Double) {
        self.kind = kind
        self.points = points
        self.confidence = confidence
    }
}

/// Recognises geometric shapes in freehand strokes — Procreate's QuickShape.
///
/// Pure geometry, no timers or gesture state: the caller decides *when* to ask
/// (usually after `PauseDetector` reports the pencil has held still), and this
/// decides *what* the stroke was meant to be.
public struct QuickShapeRecognizer {

    /// How closely a stroke must match a candidate shape to be snapped, 0...1.
    public var confidenceThreshold: Double
    /// Number of segments used to approximate a fitted ellipse.
    public var ellipseSegmentCount: Int

    public init(confidenceThreshold: Double = 0.8, ellipseSegmentCount: Int = 64) {
        self.confidenceThreshold = confidenceThreshold
        self.ellipseSegmentCount = ellipseSegmentCount
    }

    /// The best-fitting shape for `points`, or `nil` when nothing fits well
    /// enough and the freehand stroke should be kept as drawn.
    public func recognize(_ points: [Point]) -> QuickShape? {
        // Two points can only ever be a line; fewer is not a stroke at all.
        guard points.count >= 2 else { return nil }
        guard let bounds = Rect(bounding: points) else { return nil }

        let candidates = [
            fitLine(points),
            fitRectangle(points, bounds: bounds),
            fitEllipse(points, bounds: bounds)
        ].compactMap { $0 }

        // Ties favour the simpler shape, which is the order candidates are built in.
        guard let best = candidates.max(by: { $0.confidence < $1.confidence }),
              best.confidence >= confidenceThreshold else { return nil }
        return best
    }

    // MARK: - Line

    /// Fits a straight line from the first to the last sample. Confidence falls
    /// off with how far the stroke bowed away from that chord.
    public func fitLine(_ points: [Point]) -> QuickShape? {
        guard let start = points.first, let end = points.last else { return nil }
        let chord = start.distance(to: end)
        guard chord > QuickShapeRecognizer.epsilon else { return nil }

        let maxDeviation = points
            .map { QuickShapeRecognizer.distance(from: $0, toSegment: start, end) }
            .max() ?? 0

        // Deviation is judged relative to length: a 5pt wobble matters far more
        // over a 20pt stroke than over a 900pt one.
        let confidence = max(0, 1 - (maxDeviation / chord) * 4)
        return QuickShape(kind: .line, points: [start, end], confidence: confidence)
    }

    // MARK: - Ellipse

    /// Fits an axis-aligned ellipse inscribed in the stroke's bounding box.
    public func fitEllipse(_ points: [Point], bounds: Rect) -> QuickShape? {
        let rx = bounds.width / 2, ry = bounds.height / 2
        guard rx > QuickShapeRecognizer.epsilon, ry > QuickShapeRecognizer.epsilon else { return nil }

        let center = bounds.center
        // Mean absolute error of the implicit ellipse equation, which is ~0 on
        // the curve and grows away from it.
        let error = points.reduce(0.0) { sum, p in
            let nx = (p.x - center.x) / rx
            let ny = (p.y - center.y) / ry
            return sum + abs((nx * nx + ny * ny).squareRoot() - 1)
        } / Double(points.count)

        var confidence = max(0, 1 - error * 4)
        // An ellipse must close; an open arc is not a circle the user drew.
        confidence *= closureScore(points, bounds: bounds)

        var outline = (0..<ellipseSegmentCount).map { i in
            let t = 2 * Double.pi * Double(i) / Double(ellipseSegmentCount)
            return Point(center.x + rx * cos(t), center.y + ry * sin(t))
        }
        // Repeat the exact first point rather than evaluating cos(2π), which
        // lands a few ULPs off and leaves a hairline gap when stroked.
        outline.append(outline[0])
        return QuickShape(kind: .ellipse, points: outline, confidence: confidence)
    }

    // MARK: - Rectangle

    /// Fits an axis-aligned rectangle to the stroke's bounding box.
    public func fitRectangle(_ points: [Point], bounds: Rect) -> QuickShape? {
        guard bounds.width > QuickShapeRecognizer.epsilon,
              bounds.height > QuickShapeRecognizer.epsilon else { return nil }

        let corners = [
            Point(bounds.minX, bounds.minY), Point(bounds.maxX, bounds.minY),
            Point(bounds.maxX, bounds.maxY), Point(bounds.minX, bounds.maxY)
        ]
        let edges = [
            (corners[0], corners[1]), (corners[1], corners[2]),
            (corners[2], corners[3]), (corners[3], corners[0])
        ]

        // Every sample should lie on *some* edge of the box.
        let diagonal = Point(bounds.width, bounds.height).length
        let error = points.reduce(0.0) { sum, p in
            let nearest = edges
                .map { QuickShapeRecognizer.distance(from: p, toSegment: $0.0, $0.1) }
                .min() ?? 0
            return sum + nearest
        } / Double(points.count)

        var confidence = max(0, 1 - (error / diagonal) * 12)
        confidence *= closureScore(points, bounds: bounds)

        return QuickShape(
            kind: .rectangle,
            points: corners + [corners[0]],
            confidence: confidence
        )
    }

    // MARK: - Helpers

    /// How closed the stroke is, 0...1 — the gap between its endpoints measured
    /// against its own size. Closed shapes score ~1.
    private func closureScore(_ points: [Point], bounds: Rect) -> Double {
        guard let start = points.first, let end = points.last else { return 0 }
        let diagonal = Point(bounds.width, bounds.height).length
        guard diagonal > QuickShapeRecognizer.epsilon else { return 0 }
        return max(0, 1 - (start.distance(to: end) / diagonal) * 1.5)
    }

    /// Shortest distance from `p` to the segment `a`–`b` (not the infinite line,
    /// so strokes that overshoot an endpoint are penalised correctly).
    static func distance(from p: Point, toSegment a: Point, _ b: Point) -> Double {
        let ab = b - a
        let lengthSquared = ab.x * ab.x + ab.y * ab.y
        guard lengthSquared > epsilon else { return p.distance(to: a) }
        let t = ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lengthSquared
        let clamped = min(max(t, 0), 1)
        return p.distance(to: Point(a.x + ab.x * clamped, a.y + ab.y * clamped))
    }

    static let epsilon: Double = 1e-9
}
