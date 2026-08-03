import XCTest
@testable import PaintCoachCore

/// Covers UI_GAPS finding #4 — QuickShape detection and snapping.
final class QuickShapeTests: XCTestCase {

    private let recognizer = QuickShapeRecognizer()

    /// Samples along a straight line, optionally bowed sideways by `sag`.
    private func linePoints(
        from a: Point, to b: Point, count: Int = 20, sag: Double = 0
    ) -> [Point] {
        (0..<count).map { i in
            let t = Double(i) / Double(count - 1)
            let base = a.lerp(to: b, t)
            // Peak displacement at the midpoint, perpendicular to the chord.
            let bow = sin(t * .pi) * sag
            let d = b - a
            let len = d.length
            guard len > 0 else { return base }
            let normal = Point(-d.y / len, d.x / len)
            return base + normal * bow
        }
    }

    private func ellipsePoints(
        center: Point, rx: Double, ry: Double, count: Int = 48, closed: Bool = true
    ) -> [Point] {
        let span = closed ? 2 * Double.pi : 1.2 * Double.pi
        return (0..<count).map { i in
            let t = span * Double(i) / Double(count - 1)
            return Point(center.x + rx * cos(t), center.y + ry * sin(t))
        }
    }

    private func rectanglePoints(_ rect: Rect, perSide: Int = 12) -> [Point] {
        let corners = [
            Point(rect.minX, rect.minY), Point(rect.maxX, rect.minY),
            Point(rect.maxX, rect.maxY), Point(rect.minX, rect.maxY)
        ]
        var out: [Point] = []
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4]
            for j in 0..<perSide {
                out.append(a.lerp(to: b, Double(j) / Double(perSide)))
            }
        }
        out.append(corners[0])
        return out
    }

    // MARK: - Guards

    func testTooFewPointsIsNotAShape() {
        XCTAssertNil(recognizer.recognize([]))
        XCTAssertNil(recognizer.recognize([Point(1, 1)]))
    }

    func testDegenerateStrokeIsNotAShape() {
        // Every sample identical — no length, so nothing to fit.
        XCTAssertNil(recognizer.recognize(Array(repeating: Point(5, 5), count: 10)))
    }

    // MARK: - Line

    func testCleanLineIsRecognisedAsALine() {
        let shape = recognizer.recognize(linePoints(from: Point(0, 0), to: Point(400, 0)))
        XCTAssertEqual(shape?.kind, .line)
    }

    func testDiagonalLineIsRecognised() {
        let shape = recognizer.recognize(linePoints(from: Point(10, 10), to: Point(310, 260)))
        XCTAssertEqual(shape?.kind, .line)
    }

    func testSnappedLineUsesTheStrokeEndpoints() {
        let a = Point(20, 35), b = Point(300, 35)
        let shape = recognizer.recognize(linePoints(from: a, to: b))
        XCTAssertEqual(shape?.points.count, 2)
        XCTAssertEqual(shape?.points.first, a)
        XCTAssertEqual(shape?.points.last, b)
    }

    func testSlightlyWobblyLineStillSnaps() {
        let shape = recognizer.recognize(
            linePoints(from: Point(0, 0), to: Point(500, 0), sag: 3)
        )
        XCTAssertEqual(shape?.kind, .line)
    }

    func testStronglyCurvedStrokeIsNotALine() {
        // A deep bow is a deliberate curve, not a failed straight line.
        let curved = linePoints(from: Point(0, 0), to: Point(300, 0), sag: 120)
        XCTAssertNotEqual(recognizer.fitLine(curved)?.kind, .ellipse)
        XCTAssertLessThan(recognizer.fitLine(curved)!.confidence, 0.8)
    }

    func testLineConfidenceIsScaleInvariant() {
        // The same relative wobble should score the same at any size.
        let small = recognizer.fitLine(linePoints(from: Point(0, 0), to: Point(100, 0), sag: 2))!
        let large = recognizer.fitLine(linePoints(from: Point(0, 0), to: Point(1000, 0), sag: 20))!
        XCTAssertEqual(small.confidence, large.confidence, accuracy: 1e-6)
    }

    // MARK: - Ellipse

    func testCleanCircleIsRecognisedAsAnEllipse() {
        let shape = recognizer.recognize(ellipsePoints(center: Point(200, 200), rx: 100, ry: 100))
        XCTAssertEqual(shape?.kind, .ellipse)
    }

    func testStretchedEllipseIsRecognised() {
        let shape = recognizer.recognize(ellipsePoints(center: Point(0, 0), rx: 200, ry: 80))
        XCTAssertEqual(shape?.kind, .ellipse)
    }

    func testSnappedEllipseIsClosed() {
        let shape = recognizer.recognize(ellipsePoints(center: Point(0, 0), rx: 90, ry: 90))
        XCTAssertEqual(shape?.points.first, shape?.points.last, "outline must close")
    }

    func testSnappedEllipseIsCentredOnTheStrokeBounds() {
        let center = Point(150, 90)
        let shape = recognizer.recognize(ellipsePoints(center: center, rx: 60, ry: 40))
        let bounds = Rect(bounding: shape!.points)!
        XCTAssertEqual(bounds.center.x, center.x, accuracy: 0.5)
        XCTAssertEqual(bounds.center.y, center.y, accuracy: 0.5)
    }

    func testOpenArcIsNotSnappedToAnEllipse() {
        // A wide-open arc leaves a large endpoint gap, so closure fails.
        let arc = ellipsePoints(center: Point(0, 0), rx: 100, ry: 100, closed: false)
        let fit = recognizer.fitEllipse(arc, bounds: Rect(bounding: arc)!)!
        XCTAssertLessThan(fit.confidence, 0.8, "an open arc should not snap")
    }

    // MARK: - Rectangle

    func testCleanRectangleIsRecognised() {
        let rect = Rect(x: 50, y: 60, width: 300, height: 180)
        XCTAssertEqual(recognizer.recognize(rectanglePoints(rect))?.kind, .rectangle)
    }

    func testSnappedRectangleHasFiveClosingPoints() {
        let shape = recognizer.recognize(rectanglePoints(Rect(x: 0, y: 0, width: 200, height: 120)))
        XCTAssertEqual(shape?.points.count, 5)
        XCTAssertEqual(shape?.points.first, shape?.points.last)
    }

    func testSnappedRectangleMatchesStrokeBounds() {
        let rect = Rect(x: 30, y: 40, width: 260, height: 150)
        let shape = recognizer.recognize(rectanglePoints(rect))
        let bounds = Rect(bounding: shape!.points)!
        XCTAssertEqual(bounds.minX, rect.minX, accuracy: 0.5)
        XCTAssertEqual(bounds.minY, rect.minY, accuracy: 0.5)
        XCTAssertEqual(bounds.width, rect.width, accuracy: 0.5)
        XCTAssertEqual(bounds.height, rect.height, accuracy: 0.5)
    }

    // MARK: - Discrimination

    func testCircleIsNotMistakenForARectangle() {
        let shape = recognizer.recognize(ellipsePoints(center: Point(0, 0), rx: 120, ry: 120))
        XCTAssertNotEqual(shape?.kind, .rectangle)
    }

    func testRectangleIsNotMistakenForAnEllipse() {
        let shape = recognizer.recognize(rectanglePoints(Rect(x: 0, y: 0, width: 240, height: 240)))
        XCTAssertNotEqual(shape?.kind, .ellipse)
    }

    func testScribbleIsNotSnappedToAnything() {
        // Random-ish zig-zag: deliberately not any of the candidates.
        let scribble = (0..<40).map { i -> Point in
            let t = Double(i)
            return Point(t * 7, sin(t * 2.3) * 60 + cos(t * 0.7) * 25)
        }
        XCTAssertNil(recognizer.recognize(scribble), "freehand scribble must stay freehand")
    }

    func testRaisingTheThresholdRejectsMarginalFits() {
        let wobbly = linePoints(from: Point(0, 0), to: Point(300, 0), sag: 12)
        var strict = QuickShapeRecognizer(confidenceThreshold: 0.99)
        XCTAssertNil(strict.recognize(wobbly))
        strict.confidenceThreshold = 0.1
        XCTAssertNotNil(strict.recognize(wobbly))
    }

    // MARK: - Segment distance helper

    func testDistanceToSegmentClampsAtEndpoints() {
        let a = Point(0, 0), b = Point(10, 0)
        // Beyond b, distance is measured to b itself, not the infinite line.
        XCTAssertEqual(QuickShapeRecognizer.distance(from: Point(20, 0), toSegment: a, b), 10, accuracy: 1e-9)
        XCTAssertEqual(QuickShapeRecognizer.distance(from: Point(5, 3), toSegment: a, b), 3, accuracy: 1e-9)
    }

    func testDistanceToDegenerateSegmentIsPointDistance() {
        let a = Point(4, 4)
        XCTAssertEqual(
            QuickShapeRecognizer.distance(from: Point(4, 9), toSegment: a, a), 5, accuracy: 1e-9
        )
    }
}
