import XCTest
@testable import PaintCoachCore

/// Covers UI_GAPS finding #4 — the hold-still gesture that arms QuickShape.
final class PauseDetectorTests: XCTestCase {

    func testFirstSampleNeverFires() {
        var d = PauseDetector()
        XCTAssertFalse(d.accept(position: Point(0, 0), timestamp: 0))
    }

    func testHoldingStillLongEnoughFires() {
        var d = PauseDetector(pauseDuration: 0.4)
        XCTAssertFalse(d.accept(position: Point(10, 10), timestamp: 0))
        XCTAssertFalse(d.accept(position: Point(10, 10), timestamp: 0.2))
        XCTAssertTrue(d.accept(position: Point(10, 10), timestamp: 0.45))
    }

    func testFiresOnlyOncePerHold() {
        var d = PauseDetector(pauseDuration: 0.3)
        d.accept(position: Point(0, 0), timestamp: 0)
        XCTAssertTrue(d.accept(position: Point(0, 0), timestamp: 0.35))
        // Still holding — must not re-arm QuickShape every frame.
        XCTAssertFalse(d.accept(position: Point(0, 0), timestamp: 0.5))
        XCTAssertFalse(d.accept(position: Point(0, 0), timestamp: 1.0))
    }

    func testShortPauseDoesNotFire() {
        var d = PauseDetector(pauseDuration: 0.4)
        d.accept(position: Point(0, 0), timestamp: 0)
        XCTAssertFalse(d.accept(position: Point(0, 0), timestamp: 0.39))
    }

    func testSmallDriftStillCountsAsAPause() {
        var d = PauseDetector(pauseDuration: 0.3, movementTolerance: 5)
        d.accept(position: Point(0, 0), timestamp: 0)
        // Pencil noise inside tolerance must not cancel the hold.
        XCTAssertTrue(d.accept(position: Point(3, 0), timestamp: 0.35))
    }

    func testMovingOutsideToleranceCancelsThePause() {
        var d = PauseDetector(pauseDuration: 0.3, movementTolerance: 5)
        d.accept(position: Point(0, 0), timestamp: 0)
        d.accept(position: Point(50, 0), timestamp: 0.1)
        // The clock restarts from the new anchor, so the old elapsed time is void.
        XCTAssertFalse(d.accept(position: Point(50, 0), timestamp: 0.35))
    }

    func testPauseCanBeDetectedAfterMoving() {
        var d = PauseDetector(pauseDuration: 0.3, movementTolerance: 5)
        d.accept(position: Point(0, 0), timestamp: 0)
        d.accept(position: Point(100, 0), timestamp: 0.2)
        XCTAssertTrue(d.accept(position: Point(100, 0), timestamp: 0.55))
    }

    func testDetectorRearmsAfterMovingAwayFromAFiredPause() {
        var d = PauseDetector(pauseDuration: 0.3, movementTolerance: 5)
        d.accept(position: Point(0, 0), timestamp: 0)
        XCTAssertTrue(d.accept(position: Point(0, 0), timestamp: 0.35))
        // Draw on, then hold again — a second shape in one stroke must be possible.
        d.accept(position: Point(200, 0), timestamp: 0.5)
        XCTAssertTrue(d.accept(position: Point(200, 0), timestamp: 0.9))
    }

    func testIsPausedReflectsLatchedState() {
        var d = PauseDetector(pauseDuration: 0.2)
        d.accept(position: Point(0, 0), timestamp: 0)
        XCTAssertFalse(d.isPaused)
        d.accept(position: Point(0, 0), timestamp: 0.25)
        XCTAssertTrue(d.isPaused)
    }

    func testResetClearsState() {
        var d = PauseDetector(pauseDuration: 0.2)
        d.accept(position: Point(0, 0), timestamp: 0)
        d.accept(position: Point(0, 0), timestamp: 0.25)
        XCTAssertTrue(d.isPaused)

        d.reset()
        XCTAssertFalse(d.isPaused)
        // After reset the next sample is a fresh anchor, so it cannot fire.
        XCTAssertFalse(d.accept(position: Point(0, 0), timestamp: 5))
    }

    // MARK: - Integration with the recognizer

    func testHoldingAfterDrawingALineArmsQuickShape() {
        var detector = PauseDetector(pauseDuration: 0.3, movementTolerance: 4)
        let recognizer = QuickShapeRecognizer()
        var samples: [Point] = []
        var armed = false

        // Draw a rough line over 10 samples...
        for i in 0..<10 {
            let p = Point(Double(i) * 30, sin(Double(i)) * 1.5)
            samples.append(p)
            armed = detector.accept(position: p, timestamp: Double(i) * 0.02)
        }
        XCTAssertFalse(armed, "still moving, should not arm")

        // ...then hold at the end.
        armed = detector.accept(position: samples.last!, timestamp: 0.6)
        XCTAssertTrue(armed, "holding should arm QuickShape")
        XCTAssertEqual(recognizer.recognize(samples)?.kind, .line)
    }
}
