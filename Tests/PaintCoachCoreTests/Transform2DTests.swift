import XCTest
@testable import PaintCoachCore

/// Covers UI_GAPS finding #5 — transform / bounding-box math.
final class Transform2DTests: XCTestCase {

    private let tol = 1e-9

    private func assertPoint(
        _ p: Point, _ x: Double, _ y: Double,
        _ message: String = "", line: UInt = #line
    ) {
        XCTAssertEqual(p.x, x, accuracy: 1e-9, message, line: line)
        XCTAssertEqual(p.y, y, accuracy: 1e-9, message, line: line)
    }

    // MARK: - Identity

    func testIdentityLeavesPointsUnchanged() {
        assertPoint(Transform2D.identity.apply(to: Point(3, -7)), 3, -7)
        XCTAssertTrue(Transform2D.identity.isIdentity)
    }

    // MARK: - Primitives

    func testTranslation() {
        assertPoint(Transform2D.translation(x: 10, y: -4).apply(to: Point(1, 1)), 11, -3)
    }

    func testScale() {
        assertPoint(Transform2D.scale(x: 2, y: 3).apply(to: Point(4, 5)), 8, 15)
    }

    func testRotationByNinetyDegrees() {
        // (1,0) rotated +90° about the origin lands on (0,1).
        assertPoint(Transform2D.rotation(.pi / 2).apply(to: Point(1, 0)), 0, 1)
    }

    func testRotationAboutPivotLeavesPivotFixed() {
        let pivot = Point(50, 20)
        let rotated = Transform2D.rotation(.pi / 3, about: pivot).apply(to: pivot)
        assertPoint(rotated, pivot.x, pivot.y)
    }

    func testScaleAboutPivotLeavesPivotFixed() {
        let pivot = Point(-12, 8)
        let scaled = Transform2D.scale(x: 4, y: 0.5, about: pivot).apply(to: pivot)
        assertPoint(scaled, pivot.x, pivot.y)
    }

    // MARK: - Composition

    func testConcatenationAppliesSelfBeforeOther() {
        // Scale by 2, then translate by 10 → (1,1) becomes (12,12), not (22,22).
        let t = Transform2D.scale(x: 2, y: 2)
            .concatenating(.translation(x: 10, y: 10))
        assertPoint(t.apply(to: Point(1, 1)), 12, 12)
    }

    func testConcatenationIsOrderSensitive() {
        let scaleThenMove = Transform2D.scale(x: 2, y: 2)
            .concatenating(.translation(x: 10, y: 10))
        let moveThenScale = Transform2D.translation(x: 10, y: 10)
            .concatenating(.scale(x: 2, y: 2))
        XCTAssertNotEqual(scaleThenMove.apply(to: Point(1, 1)), moveThenScale.apply(to: Point(1, 1)))
        assertPoint(moveThenScale.apply(to: Point(1, 1)), 22, 22)
    }

    func testConcatenatingIdentityIsANoOp() {
        let t = Transform2D.rotation(0.7).concatenating(.translation(x: 3, y: 4))
        XCTAssertEqual(t.concatenating(.identity), t)
    }

    // MARK: - Inversion

    func testInverseUndoesTheTransform() {
        let t = Transform2D.rotation(.pi / 5, about: Point(9, 3))
            .concatenating(.scale(x: 2, y: 3))
            .concatenating(.translation(x: -7, y: 11))
        let inverse = t.inverted()
        XCTAssertNotNil(inverse)

        let original = Point(13, -2)
        let roundTrip = inverse!.apply(to: t.apply(to: original))
        assertPoint(roundTrip, original.x, original.y, "inverse must round-trip")
    }

    func testDegenerateTransformHasNoInverse() {
        // Collapsing the y axis destroys information, so there is no inverse.
        XCTAssertNil(Transform2D.scale(x: 1, y: 0).inverted())
        XCTAssertEqual(Transform2D.scale(x: 1, y: 0).determinant, 0)
    }

    // MARK: - Rect mapping

    func testTranslatingARectMovesItWithoutResizing() {
        let rect = Rect(x: 10, y: 10, width: 100, height: 50)
        let moved = Transform2D.translation(x: 5, y: -5).apply(to: rect)
        XCTAssertEqual(moved, Rect(x: 15, y: 5, width: 100, height: 50))
    }

    func testRotatingARectGrowsItsAxisAlignedBounds() {
        // A square rotated 45° has bounds sqrt(2)x larger on each axis.
        let square = Rect(x: -50, y: -50, width: 100, height: 100)
        let bounds = Transform2D.rotation(.pi / 4).apply(to: square)
        XCTAssertEqual(bounds.width, 100 * 2.0.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(bounds.height, 100 * 2.0.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(bounds.center.x, 0, accuracy: 1e-9)
        XCTAssertEqual(bounds.center.y, 0, accuracy: 1e-9)
    }

    func testRotatingARectByNinetyDegreesSwapsExtents() {
        let rect = Rect(x: -10, y: -20, width: 20, height: 40)
        let bounds = Transform2D.rotation(.pi / 2).apply(to: rect)
        XCTAssertEqual(bounds.width, 40, accuracy: 1e-9)
        XCTAssertEqual(bounds.height, 20, accuracy: 1e-9)
    }

    // MARK: - Codable

    func testTransformSurvivesCodingRoundTrip() throws {
        let t = Transform2D.rotation(0.42, about: Point(5, 6))
        let decoded = try JSONDecoder().decode(
            Transform2D.self, from: JSONEncoder().encode(t)
        )
        XCTAssertEqual(decoded, t)
    }
}
