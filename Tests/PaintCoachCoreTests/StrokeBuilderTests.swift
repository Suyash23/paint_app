import XCTest
@testable import PaintCoachCore

final class StrokeBuilderTests: XCTestCase {

    private func builder(minimumDistance: Double = 0.75) -> StrokeBuilder {
        var b = StrokeBuilder(
            brushID: "studio-pen", color: .black, size: 0.5, opacity: 1,
            minimumDistance: minimumDistance
        )
        b.begin(at: 100)  // deliberately non-zero, to prove rebasing
        return b
    }

    private func point(_ x: Double, _ y: Double, pressure: Double = 0.5, t: Double = 100) -> StrokePoint {
        StrokePoint(position: Point(x, y), pressure: pressure, timestamp: t)
    }

    // MARK: - Intake

    func testStartsEmpty() {
        XCTAssertTrue(builder().isEmpty)
        XCTAssertNil(builder().finalStroke())
    }

    func testFirstSampleIsAlwaysAccepted() {
        var b = builder()
        XCTAssertTrue(b.append(point(0, 0)))
        XCTAssertEqual(b.committed.count, 1)
    }

    func testSamplesBelowMinimumDistanceAreFiltered() {
        var b = builder(minimumDistance: 5)
        b.append(point(0, 0))
        XCTAssertFalse(b.append(point(1, 0)), "1px move should be filtered at 5px threshold")
        XCTAssertEqual(b.committed.count, 1)
    }

    func testSamplesAboveMinimumDistanceAreAccepted() {
        var b = builder(minimumDistance: 5)
        b.append(point(0, 0))
        XCTAssertTrue(b.append(point(10, 0)))
        XCTAssertEqual(b.committed.count, 2)
    }

    func testPressureChangeSurvivesTheDistanceFilter() {
        var b = builder(minimumDistance: 5)
        b.append(point(0, 0, pressure: 0.2))
        // Pressing harder without moving is a real gesture and must not be dropped.
        XCTAssertTrue(b.append(point(0, 0, pressure: 0.9)))
        XCTAssertEqual(b.committed.count, 2)
    }

    func testTinyPressureNoiseIsStillFiltered() {
        var b = builder(minimumDistance: 5)
        b.append(point(0, 0, pressure: 0.50))
        XCTAssertFalse(b.append(point(0, 0, pressure: 0.505)))
    }

    func testBatchAppendReportsAcceptedCount() {
        var b = builder(minimumDistance: 5)
        let accepted = b.append(contentsOf: [
            point(0, 0), point(1, 0), point(20, 0), point(21, 0), point(40, 0)
        ])
        XCTAssertEqual(accepted, 3)
        XCTAssertEqual(b.committed.count, 3)
    }

    // MARK: - Timestamp rebasing

    func testTimestampsAreRebasedToStrokeStart() {
        var b = builder()  // begins at t=100
        b.append(point(0, 0, t: 100))
        b.append(point(50, 0, t: 100.5))
        XCTAssertEqual(b.committed[0].timestamp, 0, accuracy: 1e-9)
        XCTAssertEqual(b.committed[1].timestamp, 0.5, accuracy: 1e-9)
    }

    func testTimestampsStayMonotonic() {
        var b = builder()
        for i in 0..<10 {
            b.append(point(Double(i) * 20, 0, t: 100 + Double(i) * 0.016))
        }
        for (a, c) in zip(b.committed, b.committed.dropFirst()) {
            XCTAssertLessThanOrEqual(a.timestamp, c.timestamp)
        }
    }

    // MARK: - Prediction

    func testPredictedPointsAppearInLiveOutputButNotFinal() {
        var b = builder()
        b.append(point(0, 0))
        b.append(point(50, 0))
        b.setPredicted([point(80, 0), point(100, 0)])

        XCTAssertEqual(b.allPoints.count, 4)
        XCTAssertEqual(b.liveStroke(id: UUID())?.points.count, 4)
        // Speculative samples must never be persisted.
        XCTAssertEqual(b.finalStroke()?.points.count, 2)
    }

    func testPredictionIsReplacedNotAccumulated() {
        var b = builder()
        b.append(point(0, 0))
        b.setPredicted([point(50, 0), point(60, 0)])
        b.setPredicted([point(70, 0)])
        XCTAssertEqual(b.predicted.count, 1, "stale predictions must be discarded")
    }

    func testClearPredictedLeavesCommittedIntact() {
        var b = builder()
        b.append(point(0, 0))
        b.setPredicted([point(50, 0)])
        b.clearPredicted()
        XCTAssertEqual(b.allPoints.count, 1)
        XCTAssertTrue(b.predicted.isEmpty)
    }

    func testPredictedPointsAreAlsoRebased() {
        var b = builder()  // t=100
        b.append(point(0, 0, t: 100))
        b.setPredicted([point(50, 0, t: 100.25)])
        XCTAssertEqual(b.predicted[0].timestamp, 0.25, accuracy: 1e-9)
    }

    // MARK: - Output

    func testLiveStrokeKeepsAStableIDAcrossFrames() {
        var b = builder()
        b.append(point(0, 0))
        let id = UUID()
        // A changing id would reseed jitter and make the stroke shimmer per frame.
        XCTAssertEqual(b.liveStroke(id: id)?.id, b.liveStroke(id: id)?.id)
        XCTAssertEqual(b.liveStroke(id: id)?.id, id)
    }

    func testFinalStrokeCarriesBrushSettings() {
        var b = builder()
        b.append(point(0, 0))
        let stroke = b.finalStroke()
        XCTAssertEqual(stroke?.brushID, "studio-pen")
        XCTAssertEqual(stroke?.size, 0.5)
        XCTAssertEqual(stroke?.opacity, 1)
        XCTAssertEqual(stroke?.color, .black)
    }

    func testLiveStrokeIsNilWhenNothingSampled() {
        XCTAssertNil(builder().liveStroke(id: UUID()))
    }

    func testPredictionAloneDoesNotProduceAFinalStroke() {
        var b = builder()
        b.setPredicted([point(0, 0)])
        XCTAssertNil(b.finalStroke(), "prediction alone is not a stroke")
        XCTAssertNotNil(b.liveStroke(id: UUID()))
    }
}
