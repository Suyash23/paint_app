import XCTest
@testable import PaintCoachCore

final class StampGeometryTests: XCTestCase {

    func testCircularStampBoundsAreCenteredOnPosition() {
        let stamp = BrushStamp(position: Point(100, 50), diameter: 20, opacity: 1)
        let bounds = StampGeometry.bounds(of: stamp)
        XCTAssertEqual(bounds, Rect(x: 90, y: 40, width: 20, height: 20))
        XCTAssertEqual(bounds.center, stamp.position)
    }

    func testStampBoundsAlwaysContainStampCenter() {
        let stamp = BrushStamp(position: Point(-30, 12), diameter: 8, opacity: 1)
        XCTAssertTrue(StampGeometry.bounds(of: stamp).contains(stamp.position))
    }

    func testEccentricStampBoundsGrowWithMajorAxis() {
        let round = BrushStamp(position: .zero, diameter: 10, opacity: 1, eccentricity: 1)
        let wide = BrushStamp(position: .zero, diameter: 10, opacity: 1, eccentricity: 3)
        XCTAssertEqual(StampGeometry.bounds(of: round).width, 10)
        XCTAssertEqual(StampGeometry.bounds(of: wide).width, 30)
    }

    func testBoundsAreRotationIndependent() {
        // The conservative circular bound must not shrink at any rotation, or a
        // rotated stamp would paint outside its own dirty region.
        let reference = StampGeometry.bounds(
            of: BrushStamp(position: .zero, diameter: 10, opacity: 1, rotation: 0, eccentricity: 2)
        )
        for rotation in [0.0, 0.3, .pi / 4, .pi / 2, .pi, 2 * .pi] {
            let rotated = StampGeometry.bounds(
                of: BrushStamp(position: .zero, diameter: 10, opacity: 1, rotation: rotation, eccentricity: 2)
            )
            XCTAssertEqual(rotated, reference)
        }
    }

    func testEccentricityBelowOneDoesNotShrinkBoundsBelowDiameter() {
        let squashed = BrushStamp(position: .zero, diameter: 10, opacity: 1, eccentricity: 0.5)
        // Height is still `diameter`, so bounds must not fall below it.
        XCTAssertEqual(StampGeometry.bounds(of: squashed).width, 10)
    }

    func testBoundsOfManyStampsCoversEveryStamp() {
        let stamps = [
            BrushStamp(position: Point(0, 0), diameter: 10, opacity: 1),
            BrushStamp(position: Point(100, 0), diameter: 10, opacity: 1),
            BrushStamp(position: Point(50, 80), diameter: 20, opacity: 1)
        ]
        let union = StampGeometry.bounds(of: stamps)!
        for stamp in stamps {
            let individual = StampGeometry.bounds(of: stamp)
            XCTAssertEqual(union.union(individual), union, "union failed to cover \(stamp.position)")
        }
    }

    func testBoundsOfEmptyStampsIsNil() {
        XCTAssertNil(StampGeometry.bounds(of: [BrushStamp]()))
    }

    func testStrokeBoundsCoverTheGeneratedStamps() {
        let stroke = Stroke(
            brushID: "test", color: .black, size: 1, opacity: 1,
            points: (0..<6).map { StrokePoint(position: Point(Double($0) * 50, 0), pressure: 0.6) }
        )
        let brush = Brush.studioPen
        let bounds = StampGeometry.bounds(of: stroke, brush: brush)!
        let stamps = BrushEngine(brush: brush).stamps(for: stroke)

        XCTAssertFalse(stamps.isEmpty)
        for stamp in stamps {
            XCTAssertEqual(bounds.union(StampGeometry.bounds(of: stamp)), bounds)
        }
    }

    func testStrokeBoundsAccountForJitterSpill() {
        // softPencil jitters perpendicular to travel; bounds must include it.
        let stroke = Stroke(
            brushID: "soft-pencil", color: .black, size: 1, opacity: 1,
            points: (0..<8).map { StrokePoint(position: Point(Double($0) * 40, 100), pressure: 0.8) }
        )
        let bounds = StampGeometry.bounds(of: stroke, brush: .softPencil)!
        for stamp in BrushEngine(brush: .softPencil).stamps(for: stroke) {
            XCTAssertEqual(bounds.union(StampGeometry.bounds(of: stamp)), bounds)
        }
    }

    func testEmptyStrokeHasNoBounds() {
        let stroke = Stroke(brushID: "test", color: .black, size: 1, opacity: 1, points: [])
        XCTAssertNil(StampGeometry.bounds(of: stroke, brush: .studioPen))
    }

    // MARK: - Batching

    func testBatchingPreservesEveryStampInOrder() {
        let stamps = (0..<50).map {
            BrushStamp(position: Point(Double($0) * 20, 0), diameter: 10, opacity: 1)
        }
        let batches = StampGeometry.batches(of: stamps, maxArea: 5000)
        XCTAssertGreaterThan(batches.count, 1, "expected the run to be split")
        XCTAssertEqual(batches.flatMap { $0 }, stamps)
    }

    func testBatchesRespectMaxAreaWhereverPossible() {
        let stamps = (0..<40).map {
            BrushStamp(position: Point(Double($0) * 15, 0), diameter: 10, opacity: 1)
        }
        let maxArea = 4000.0
        for batch in StampGeometry.batches(of: stamps, maxArea: maxArea) {
            guard batch.count > 1 else { continue }  // a lone stamp may exceed the budget
            let bounds = StampGeometry.bounds(of: batch)!
            XCTAssertLessThanOrEqual(bounds.width * bounds.height, maxArea)
        }
    }

    func testSingleOversizedStampStillFormsItsOwnBatch() {
        let huge = BrushStamp(position: .zero, diameter: 1000, opacity: 1)
        let batches = StampGeometry.batches(of: [huge], maxArea: 10)
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches[0].count, 1)
    }

    func testBatchingEmptyInputGivesNoBatches() {
        XCTAssertTrue(StampGeometry.batches(of: [], maxArea: 100).isEmpty)
    }

    func testNonPositiveMaxAreaYieldsOneBatch() {
        let stamps = (0..<10).map { BrushStamp(position: Point(Double($0), 0), diameter: 5, opacity: 1) }
        XCTAssertEqual(StampGeometry.batches(of: stamps, maxArea: 0), [stamps])
    }
}
