import XCTest
@testable import PaintCoachCore

final class BrushEngineTests: XCTestCase {

    /// A predictable brush: no jitter, no dynamics, so geometry is exactly checkable.
    private var plainBrush: Brush {
        Brush(
            id: "test",
            name: "Test",
            maxDiameter: 100,
            spacing: 0.5,
            sizeDynamics: .flat,
            opacityDynamics: .flat,
            tiltDynamics: .flat
        )
    }

    private func horizontalStroke(
        length: Double = 500,
        samples: Int = 6,
        size: Double = 1,
        opacity: Double = 1,
        pressure: Double = 0.5,
        id: UUID = UUID()
    ) -> Stroke {
        let points = (0..<samples).map { i -> StrokePoint in
            let t = Double(i) / Double(samples - 1)
            return StrokePoint(position: Point(t * length, 0), pressure: pressure, timestamp: t)
        }
        return Stroke(id: id, brushID: "test", color: .black, size: size, opacity: opacity, points: points)
    }

    // MARK: - Degenerate input

    func testEmptyStrokeProducesNoStamps() {
        let stroke = Stroke(brushID: "test", color: .black, size: 1, opacity: 1, points: [])
        XCTAssertTrue(BrushEngine(brush: plainBrush).stamps(for: stroke).isEmpty)
    }

    func testSingleTapProducesExactlyOneStamp() {
        let stroke = Stroke(
            brushID: "test", color: .black, size: 1, opacity: 1,
            points: [StrokePoint(position: Point(10, 10), pressure: 0.7)]
        )
        let stamps = BrushEngine(brush: plainBrush).stamps(for: stroke)
        XCTAssertEqual(stamps.count, 1)
        XCTAssertEqual(stamps[0].position, Point(10, 10))
    }

    func testZeroLengthStrokeDoesNotHangOrExplode() {
        let repeated = (0..<5).map { StrokePoint(position: Point(50, 50), pressure: 0.5, timestamp: Double($0)) }
        let stroke = Stroke(brushID: "test", color: .black, size: 1, opacity: 1, points: repeated)
        let stamps = BrushEngine(brush: plainBrush).stamps(for: stroke)
        // All input is one location, so only the initial stamp should be emitted.
        XCTAssertEqual(stamps.count, 1)
    }

    // MARK: - Spacing

    func testStampsAreEvenlySpacedAtTheExpectedInterval() {
        let engine = BrushEngine(brush: plainBrush)
        let stamps = engine.stamps(for: horizontalStroke(length: 500))
        XCTAssertGreaterThan(stamps.count, 5)

        // spacing 0.5 × diameter 100 == 50px between stamps.
        for (a, b) in zip(stamps, stamps.dropFirst()) {
            XCTAssertEqual(a.position.distance(to: b.position), 50, accuracy: 1.0)
        }
    }

    func testTighterSpacingYieldsMoreStamps() {
        var dense = plainBrush
        dense.spacing = 0.1
        let sparseCount = BrushEngine(brush: plainBrush).stamps(for: horizontalStroke()).count
        let denseCount = BrushEngine(brush: dense).stamps(for: horizontalStroke()).count
        XCTAssertGreaterThan(denseCount, sparseCount)
    }

    func testStampsFollowThePathInOrder() {
        let stamps = BrushEngine(brush: plainBrush).stamps(for: horizontalStroke())
        for (a, b) in zip(stamps, stamps.dropFirst()) {
            XCTAssertLessThan(a.position.x, b.position.x + 1e-9, "stamps went backwards along the path")
        }
    }

    func testSpacingScalesWithBrushSizeNotJustDiameter() {
        // A half-size stroke has half the diameter, so stamps should be twice as dense.
        let full = BrushEngine(brush: plainBrush).stamps(for: horizontalStroke(size: 1)).count
        let half = BrushEngine(brush: plainBrush).stamps(for: horizontalStroke(size: 0.5)).count
        XCTAssertGreaterThan(half, full)
    }

    // MARK: - Determinism

    func testSameStrokeProducesIdenticalStamps() {
        let stroke = horizontalStroke()
        let engine = BrushEngine(brush: .softPencil)
        XCTAssertEqual(engine.stamps(for: stroke), engine.stamps(for: stroke))
    }

    func testJitterIsStableAcrossSeparateEngineInstances() {
        // Re-rendering later, with a fresh engine, must give byte-identical marks.
        let stroke = horizontalStroke()
        let first = BrushEngine(brush: .softPencil).stamps(for: stroke)
        let second = BrushEngine(brush: .softPencil).stamps(for: stroke)
        XCTAssertEqual(first, second)
    }

    func testDifferentStrokeIDsGiveDifferentJitter() {
        let a = horizontalStroke(id: UUID())
        let b = horizontalStroke(id: UUID())
        let engine = BrushEngine(brush: .softPencil)
        // Same geometry, different identity — jitter should differ.
        XCTAssertNotEqual(engine.stamps(for: a), engine.stamps(for: b))
    }

    func testZeroJitterKeepsStampsExactlyOnPath() {
        let stamps = BrushEngine(brush: plainBrush).stamps(for: horizontalStroke())
        for stamp in stamps {
            XCTAssertEqual(stamp.position.y, 0, accuracy: 1e-9)
        }
    }

    // MARK: - Dynamics

    func testPressureDrivesStampDiameter() {
        var brush = plainBrush
        brush.sizeDynamics = ResponseCurve(minimum: 0.2, maximum: 1)
        let engine = BrushEngine(brush: brush)

        let light = engine.stamps(for: horizontalStroke(pressure: 0.1))
        let heavy = engine.stamps(for: horizontalStroke(pressure: 1.0))
        XCTAssertLessThan(light[0].diameter, heavy[0].diameter)
        XCTAssertEqual(heavy[0].diameter, 100, accuracy: 1e-9)
    }

    func testPressureDrivesStampOpacity() {
        var brush = plainBrush
        brush.opacityDynamics = ResponseCurve(minimum: 0.1, maximum: 1)
        let engine = BrushEngine(brush: brush)
        let light = engine.stamps(for: horizontalStroke(pressure: 0.0))
        let heavy = engine.stamps(for: horizontalStroke(pressure: 1.0))
        XCTAssertEqual(light[0].opacity, 0.1, accuracy: 1e-9)
        XCTAssertEqual(heavy[0].opacity, 1.0, accuracy: 1e-9)
    }

    func testStrokeSizeScalesDiameter() {
        let engine = BrushEngine(brush: plainBrush)
        let stamps = engine.stamps(for: horizontalStroke(size: 0.25))
        XCTAssertEqual(stamps[0].diameter, 25, accuracy: 1e-9)
    }

    func testStrokeOpacityIsRespected() {
        let engine = BrushEngine(brush: plainBrush)
        let stamps = engine.stamps(for: horizontalStroke(opacity: 0.4))
        XCTAssertEqual(stamps[0].opacity, 0.4, accuracy: 1e-9)
    }

    func testOpacityIsClampedToUnitRange() {
        var brush = plainBrush
        brush.opacityDynamics = ResponseCurve(minimum: 2, maximum: 4)
        let stamps = BrushEngine(brush: brush).stamps(for: horizontalStroke(opacity: 1))
        for stamp in stamps {
            XCTAssertLessThanOrEqual(stamp.opacity, 1)
            XCTAssertGreaterThanOrEqual(stamp.opacity, 0)
        }
    }

    func testFlatPencilProducesWiderStampThanPerpendicular() {
        var brush = plainBrush
        brush.tiltDynamics = ResponseCurve(minimum: 1, maximum: 3)
        let engine = BrushEngine(brush: brush)

        let perpendicular = Stroke(
            brushID: "test", color: .black, size: 1, opacity: 1,
            points: [StrokePoint(position: .zero, altitude: .pi / 2)]
        )
        let flat = Stroke(
            brushID: "test", color: .black, size: 1, opacity: 1,
            points: [StrokePoint(position: .zero, altitude: 0)]
        )
        XCTAssertEqual(engine.stamps(for: perpendicular)[0].eccentricity, 1, accuracy: 1e-9)
        XCTAssertEqual(engine.stamps(for: flat)[0].eccentricity, 3, accuracy: 1e-9)
    }

    func testDirectionFollowingRotatesStampsAlongTravel() {
        var brush = plainBrush
        brush.followsDirection = true
        let stamps = BrushEngine(brush: brush).stamps(for: horizontalStroke())
        // Travelling along +x, so rotation should be ~0.
        for stamp in stamps {
            XCTAssertEqual(stamp.rotation, 0, accuracy: 1e-6)
        }
    }

    func testAllStampsHaveUsableGeometry() {
        let stamps = BrushEngine(brush: .softPencil).stamps(for: horizontalStroke())
        XCTAssertFalse(stamps.isEmpty)
        for stamp in stamps {
            XCTAssertGreaterThan(stamp.diameter, 0)
            XCTAssertTrue(stamp.diameter.isFinite)
            XCTAssertTrue(stamp.position.x.isFinite)
            XCTAssertTrue(stamp.position.y.isFinite)
            XCTAssertTrue((0...1).contains(stamp.opacity))
            XCTAssertGreaterThan(stamp.eccentricity, 0)
        }
    }

    // MARK: - Presets

    func testBuiltInPresetsGenerateStamps() {
        for brush in [Brush.studioPen, .softPencil] {
            let stamps = BrushEngine(brush: brush).stamps(for: horizontalStroke())
            XCTAssertGreaterThan(stamps.count, 1, "\(brush.name) produced no stamps")
        }
    }

    func testBrushSurvivesJSONRoundTrip() throws {
        let data = try JSONEncoder().encode(Brush.softPencil)
        XCTAssertEqual(try JSONDecoder().decode(Brush.self, from: data), .softPencil)
    }
}
