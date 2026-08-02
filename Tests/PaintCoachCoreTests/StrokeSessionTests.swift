import XCTest
@testable import PaintCoachCore

final class StrokeSessionTests: XCTestCase {

    private func point(_ x: Double, _ y: Double, pressure: Double = 0.5, t: Double = 0) -> StrokePoint {
        StrokePoint(position: Point(x, y), pressure: pressure, timestamp: t)
    }

    private func beginDrawing(
        _ session: inout StrokeSession,
        on layer: Layer
    ) -> Bool {
        session.begin(
            layer: layer, brushID: "studio-pen", color: .black,
            size: 0.4, opacity: 1, at: 0, minimumDistance: 1
        )
    }

    // MARK: - Lifecycle

    func testStartsIdle() {
        let session = StrokeSession()
        XCTAssertEqual(session.state, .idle)
        XCTAssertFalse(session.isDrawing)
        XCTAssertNil(session.liveStroke)
    }

    func testBeginEntersDrawingState() {
        var session = StrokeSession()
        let layer = Layer(name: "L")
        XCTAssertTrue(beginDrawing(&session, on: layer))
        XCTAssertEqual(session.state, .drawing(layerID: layer.id))
    }

    func testCannotDrawOnLockedLayer() {
        var session = StrokeSession()
        var layer = Layer(name: "L")
        layer.isLocked = true
        // Refused up front, so no mark ever appears and then vanishes.
        XCTAssertFalse(beginDrawing(&session, on: layer))
        XCTAssertEqual(session.state, .idle)
    }

    func testCannotDrawOnBackgroundColorLayer() {
        var session = StrokeSession()
        let background = Layer(name: "Background Color", kind: .backgroundColor)
        XCTAssertFalse(beginDrawing(&session, on: background))
        XCTAssertEqual(session.state, .idle)
    }

    func testMoveIsIgnoredWhenNotDrawing() {
        var session = StrokeSession()
        XCTAssertFalse(session.move(coalesced: [point(0, 0)]))
        XCTAssertNil(session.liveStroke)
    }

    // MARK: - Sampling

    func testLiveStrokeGrowsAsSamplesArrive() {
        var session = StrokeSession()
        _ = beginDrawing(&session, on: Layer(name: "L"))
        session.move(coalesced: [point(0, 0)])
        XCTAssertEqual(session.liveStroke?.points.count, 1)
        session.move(coalesced: [point(20, 0), point(40, 0)])
        XCTAssertEqual(session.liveStroke?.points.count, 3)
    }

    func testCoalescedAndPredictedBothAppearLive() {
        var session = StrokeSession()
        _ = beginDrawing(&session, on: Layer(name: "L"))
        session.move(coalesced: [point(0, 0), point(20, 0)], predicted: [point(40, 0)])
        XCTAssertEqual(session.liveStroke?.points.count, 3)
    }

    func testLiveStrokeIDIsStableWhileDrawing() {
        var session = StrokeSession()
        _ = beginDrawing(&session, on: Layer(name: "L"))
        session.move(coalesced: [point(0, 0)])
        let first = session.liveStroke?.id
        session.move(coalesced: [point(30, 0)])
        // A changing id reseeds jitter every frame, making the stroke shimmer.
        XCTAssertEqual(first, session.liveStroke?.id)
    }

    func testEachStrokeGetsAFreshID() {
        var session = StrokeSession()
        let layer = Layer(name: "L")

        _ = beginDrawing(&session, on: layer)
        session.move(coalesced: [point(0, 0)])
        let firstID = session.liveStroke?.id
        _ = session.end()

        _ = beginDrawing(&session, on: layer)
        session.move(coalesced: [point(0, 0)])
        XCTAssertNotEqual(firstID, session.liveStroke?.id)
    }

    // MARK: - Commit

    func testEndProducesAnAddStrokeCommand() {
        var session = StrokeSession()
        let layer = Layer(name: "L")
        _ = beginDrawing(&session, on: layer)
        session.move(coalesced: [point(0, 0), point(30, 0), point(60, 0)])

        guard let result = session.end() else {
            return XCTFail("expected a command")
        }
        XCTAssertEqual(result.command, .addStroke(layerID: layer.id, stroke: result.stroke))
        XCTAssertEqual(result.stroke.points.count, 3)
        XCTAssertEqual(session.state, .idle)
    }

    func testCommittedStrokeExcludesPrediction() {
        var session = StrokeSession()
        _ = beginDrawing(&session, on: Layer(name: "L"))
        session.move(coalesced: [point(0, 0), point(30, 0)], predicted: [point(60, 0), point(90, 0)])
        XCTAssertEqual(session.liveStroke?.points.count, 4)

        let result = session.end()
        // Speculative samples must never reach the document.
        XCTAssertEqual(result?.stroke.points.count, 2)
    }

    func testEndWithNoSamplesProducesNothing() {
        var session = StrokeSession()
        _ = beginDrawing(&session, on: Layer(name: "L"))
        XCTAssertNil(session.end())
        XCTAssertEqual(session.state, .idle)
    }

    func testEndWithOnlyPredictionProducesNothing() {
        var session = StrokeSession()
        _ = beginDrawing(&session, on: Layer(name: "L"))
        session.move(coalesced: [], predicted: [point(0, 0), point(30, 0)])
        XCTAssertNil(session.end(), "prediction alone must not commit a stroke")
    }

    func testEndWhenIdleIsHarmless() {
        var session = StrokeSession()
        XCTAssertNil(session.end())
        XCTAssertEqual(session.state, .idle)
    }

    func testCancelDiscardsEverything() {
        var session = StrokeSession()
        _ = beginDrawing(&session, on: Layer(name: "L"))
        session.move(coalesced: [point(0, 0), point(30, 0)])
        session.cancel()

        XCTAssertEqual(session.state, .idle)
        XCTAssertNil(session.liveStroke)
        XCTAssertNil(session.end())
    }

    // MARK: - Integration with the document

    func testCommittedStrokeAppliesCleanlyToTheStore() throws {
        var store = DocumentStore()
        var session = StrokeSession()
        let layer = store.document.activeLayer

        _ = beginDrawing(&session, on: layer)
        session.move(coalesced: [point(10, 10), point(40, 20), point(70, 30)])

        guard let result = session.end() else { return XCTFail("expected a stroke") }
        try store.perform(result.command)

        XCTAssertEqual(store.document.activeLayer.strokes.count, 1)
        XCTAssertTrue(store.canUndo)

        try store.undo()
        XCTAssertTrue(store.document.activeLayer.strokes.isEmpty)
    }

    func testTimestampsAreRebasedFromTheGestureStart() {
        var session = StrokeSession()
        let layer = Layer(name: "L")
        // Begin at a large absolute time, as UIKit event timestamps are.
        _ = session.begin(
            layer: layer, brushID: "studio-pen", color: .black,
            size: 0.4, opacity: 1, at: 5000, minimumDistance: 1
        )
        session.move(coalesced: [
            point(0, 0, t: 5000),
            point(30, 0, t: 5000.016),
            point(60, 0, t: 5000.032)
        ])
        let points = session.liveStroke?.points ?? []
        XCTAssertEqual(points.first?.timestamp ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(points.last?.timestamp ?? -1, 0.032, accuracy: 1e-9)
    }
}
