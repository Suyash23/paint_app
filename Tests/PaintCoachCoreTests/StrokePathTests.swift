import XCTest
@testable import PaintCoachCore

final class StrokePathTests: XCTestCase {

    private func line(_ count: Int, spacing: Double = 100) -> [StrokePoint] {
        (0..<count).map { StrokePoint(position: Point(Double($0) * spacing, 0), pressure: 0.5) }
    }

    // MARK: - Interpolation

    func testInterpolationHitsSegmentEndpoints() {
        let p0 = Point(0, 0), p1 = Point(10, 5), p2 = Point(20, 5), p3 = Point(30, 0)
        let start = StrokePath.interpolate(p0, p1, p2, p3, t: 0)
        let end = StrokePath.interpolate(p0, p1, p2, p3, t: 1)
        XCTAssertEqual(start.x, p1.x, accuracy: 1e-9)
        XCTAssertEqual(start.y, p1.y, accuracy: 1e-9)
        XCTAssertEqual(end.x, p2.x, accuracy: 1e-9)
        XCTAssertEqual(end.y, p2.y, accuracy: 1e-9)
    }

    func testCollinearPointsInterpolateOnTheLine() {
        let result = StrokePath.interpolate(Point(0, 0), Point(10, 0), Point(20, 0), Point(30, 0), t: 0.5)
        XCTAssertEqual(result.y, 0, accuracy: 1e-9)
        XCTAssertEqual(result.x, 15, accuracy: 1e-9)
    }

    // MARK: - Smoothing

    func testSmoothingPassesThroughEveryInputPoint() {
        let input = [
            StrokePoint(position: Point(0, 0)),
            StrokePoint(position: Point(50, 40)),
            StrokePoint(position: Point(100, 0)),
            StrokePoint(position: Point(150, 60))
        ]
        let smoothed = StrokePath.smooth(input, subdivisions: 8)
        // Every original point must still appear on the densified path.
        for point in input {
            let found = smoothed.contains {
                abs($0.position.x - point.position.x) < 1e-6 &&
                abs($0.position.y - point.position.y) < 1e-6
            }
            XCTAssertTrue(found, "input point \(point.position) was lost by smoothing")
        }
    }

    func testSmoothingIncreasesPointCount() {
        let smoothed = StrokePath.smooth(line(4), subdivisions: 8)
        XCTAssertGreaterThan(smoothed.count, 4)
    }

    func testShortStrokesArePassedThroughUnchanged() {
        XCTAssertEqual(StrokePath.smooth([], subdivisions: 8).count, 0)
        XCTAssertEqual(StrokePath.smooth(line(1), subdivisions: 8).count, 1)
        XCTAssertEqual(StrokePath.smooth(line(2), subdivisions: 8).count, 2)
    }

    func testSubdivisionsBelowTwoDisablesSmoothing() {
        let input = line(5)
        XCTAssertEqual(StrokePath.smooth(input, subdivisions: 1).count, input.count)
    }

    func testStraightLineStaysStraight() {
        let smoothed = StrokePath.smooth(line(5), subdivisions: 6)
        for point in smoothed {
            XCTAssertEqual(point.position.y, 0, accuracy: 1e-9)
        }
    }

    func testPencilDataIsCarriedAndStaysInRange() {
        let input = [
            StrokePoint(position: Point(0, 0), pressure: 0.0, timestamp: 0),
            StrokePoint(position: Point(50, 0), pressure: 0.5, timestamp: 1),
            StrokePoint(position: Point(100, 0), pressure: 1.0, timestamp: 2),
            StrokePoint(position: Point(150, 0), pressure: 1.0, timestamp: 3)
        ]
        let smoothed = StrokePath.smooth(input, subdivisions: 4)
        for point in smoothed {
            XCTAssertTrue((0...1).contains(point.pressure), "pressure escaped 0...1: \(point.pressure)")
        }
        // Timestamps must stay monotonic so velocity dynamics remain sane.
        for (a, b) in zip(smoothed, smoothed.dropFirst()) {
            XCTAssertLessThanOrEqual(a.timestamp, b.timestamp + 1e-9)
        }
    }

    func testSmoothingIsDeterministic() {
        let input = line(6)
        XCTAssertEqual(StrokePath.smooth(input, subdivisions: 8), StrokePath.smooth(input, subdivisions: 8))
    }
}
