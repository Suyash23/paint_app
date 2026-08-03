import XCTest
@testable import PaintCoachCore

/// Covers UI_GAPS finding #5 — transform session, handles and snapping.
final class TransformSessionTests: XCTestCase {

    /// A 100x100 box centred on the origin, so scale/rotation maths is easy to read.
    private let box = Rect(x: -50, y: -50, width: 100, height: 100)

    private func makeSession(
        _ mode: TransformMode = .freeform,
        snapping: Bool = true
    ) -> TransformSession {
        TransformSession(bounds: box, mode: mode, isSnappingEnabled: snapping)
    }

    private func assertPoint(
        _ p: Point, _ x: Double, _ y: Double,
        _ message: String = "", line: UInt = #line
    ) {
        XCTAssertEqual(p.x, x, accuracy: 1e-9, message, line: line)
        XCTAssertEqual(p.y, y, accuracy: 1e-9, message, line: line)
    }

    // MARK: - Initial state

    func testNewSessionIsIdentityAndMatchesItsBounds() {
        let s = makeSession()
        XCTAssertTrue(s.transform.isIdentity)
        XCTAssertEqual(s.currentBounds, box)
    }

    func testResetDiscardsAccumulatedTransform() {
        var s = makeSession()
        s.translate(by: Point(30, 40))
        s.reset()
        XCTAssertTrue(s.transform.isIdentity)
        XCTAssertEqual(s.currentBounds, box)
    }

    // MARK: - Handle positions

    func testCornerHandlesSitOnTheCornersOfTheBox() {
        let s = makeSession()
        assertPoint(s.position(of: .topLeft), -50, -50)
        assertPoint(s.position(of: .topRight), 50, -50)
        assertPoint(s.position(of: .bottomRight), 50, 50)
        assertPoint(s.position(of: .bottomLeft), -50, 50)
    }

    func testEdgeHandlesSitAtEdgeMidpoints() {
        let s = makeSession()
        assertPoint(s.position(of: .top), 0, -50)
        assertPoint(s.position(of: .bottom), 0, 50)
        assertPoint(s.position(of: .left), -50, 0)
        assertPoint(s.position(of: .right), 50, 0)
    }

    func testRotationNodeFloatsAboveTheTopEdge() {
        let s = makeSession()
        assertPoint(s.position(of: .rotation), 0, -50 - TransformSession.rotationNodeOffset)
    }

    func testHandlesFollowTheTransform() {
        var s = makeSession()
        s.translate(by: Point(10, 20))
        assertPoint(s.position(of: .topLeft), -40, -30)
    }

    // MARK: - Handle opposites

    func testEveryScaleHandleHasAnOppositeAndRotationDoesNot() {
        for handle in TransformHandle.allCases where handle != .rotation {
            XCTAssertNotNil(handle.opposite, "\(handle) should have an opposite")
            XCTAssertEqual(handle.opposite?.opposite, handle, "\(handle) opposite must be symmetric")
        }
        XCTAssertNil(TransformHandle.rotation.opposite)
    }

    func testOnlyDiagonalHandlesAreCorners() {
        XCTAssertEqual(
            Set(TransformHandle.allCases.filter(\.isCorner)),
            [.topLeft, .topRight, .bottomRight, .bottomLeft]
        )
    }

    // MARK: - Hit testing

    func testHitTestFindsTheNearestHandle() {
        let s = makeSession()
        XCTAssertEqual(s.handle(at: Point(-48, -48), radius: 10), .topLeft)
    }

    func testHitTestMissesWhenOutsideRadius() {
        let s = makeSession()
        XCTAssertNil(s.handle(at: Point(0, 0), radius: 10))
    }

    func testHitTestPrefersCornerOverEdgeHandle() {
        // A tiny box makes corner and edge handles overlap; the corner must win.
        let s = TransformSession(bounds: Rect(x: 0, y: 0, width: 2, height: 2))
        let hit = s.handle(at: Point(0, 0), radius: 5)
        XCTAssertEqual(hit, .topLeft, "corners must stay grabbable where handles overlap")
    }

    // MARK: - Translation

    func testTranslateMovesBoundsWithoutResizing() {
        var s = makeSession()
        s.translate(by: Point(25, -15))
        XCTAssertEqual(s.currentBounds, Rect(x: -25, y: -65, width: 100, height: 100))
    }

    func testTranslationsAccumulate() {
        var s = makeSession()
        s.translate(by: Point(10, 0))
        s.translate(by: Point(5, 5))
        XCTAssertEqual(s.currentBounds.origin, Point(-35, -45))
    }

    // MARK: - Freeform scaling

    func testDraggingCornerScalesAndKeepsOppositeCornerFixed() {
        var s = makeSession()
        let anchor = s.position(of: .bottomRight)
        // Drag the top-left corner to double the box away from bottom-right.
        s.scale(handle: .topLeft, to: Point(-150, -150))
        assertPoint(s.position(of: .bottomRight), anchor.x, anchor.y, "anchor must not move")
        XCTAssertEqual(s.currentBounds.width, 200, accuracy: 1e-9)
        XCTAssertEqual(s.currentBounds.height, 200, accuracy: 1e-9)
    }

    func testFreeformEdgeHandleScalesOneAxisOnly() {
        var s = makeSession(.freeform)
        // The right edge shares its anchor's y, so height must be untouched.
        s.scale(handle: .right, to: Point(150, 0))
        XCTAssertEqual(s.currentBounds.width, 200, accuracy: 1e-9)
        XCTAssertEqual(s.currentBounds.height, 100, accuracy: 1e-9, "edge drag must not scale y")
    }

    // MARK: - Uniform scaling

    func testUniformModePreservesAspectRatio() {
        var s = makeSession(.uniform)
        // An uneven drag must still produce a square result from a square box.
        s.scale(handle: .topLeft, to: Point(-150, -60))
        XCTAssertEqual(s.currentBounds.width, s.currentBounds.height, accuracy: 1e-9)
    }

    func testUniformModeUsesTheLargerDragAxis() {
        var s = makeSession(.uniform)
        s.scale(handle: .topLeft, to: Point(-150, -60))
        // max(|2|, |1.1|) = 2 → 100 becomes 200.
        XCTAssertEqual(s.currentBounds.width, 200, accuracy: 1e-9)
    }

    func testFreeformModeDoesNotPreserveAspectRatio() {
        var s = makeSession(.freeform)
        s.scale(handle: .topLeft, to: Point(-150, -60))
        XCTAssertNotEqual(s.currentBounds.width, s.currentBounds.height, accuracy: 1e-6)
    }

    func testOnlyUniformModePreservesAspectRatio() {
        XCTAssertTrue(TransformMode.uniform.preservesAspectRatio)
        for mode in TransformMode.allCases where mode != .uniform {
            XCTAssertFalse(mode.preservesAspectRatio, "\(mode) must not constrain aspect")
        }
    }

    func testScalingViaRotationHandleIsANoOp() {
        var s = makeSession()
        let before = s.transform
        s.scale(handle: .rotation, to: Point(999, 999))
        XCTAssertEqual(s.transform, before, "rotation node is not a scale handle")
    }

    // MARK: - Rotation and snapping

    func testRotationKeepsTheCentreFixed() {
        var s = makeSession(snapping: false)
        s.rotate(to: 0.6)
        assertPoint(s.currentBounds.center, box.center.x, box.center.y)
    }

    func testRotationSnapsToNearbyIncrement() {
        var s = makeSession(snapping: true)
        // 1° shy of 45° is inside the 5° tolerance, so it snaps.
        s.rotate(to: .pi / 4 - (.pi / 180))
        let corner = s.position(of: .topRight)
        let expected = Transform2D.rotation(.pi / 4, about: box.center)
            .apply(to: Point(box.maxX, box.minY))
        assertPoint(corner, expected.x, expected.y, "should snap to 45°")
    }

    func testRotationDoesNotSnapWhenOutsideTolerance() {
        var s = makeSession(snapping: true)
        let angle = Double.pi / 4 - (.pi / 12)  // 15° shy of 45°, beyond tolerance
        s.rotate(to: angle)
        let expected = Transform2D.rotation(angle, about: box.center)
            .apply(to: Point(box.maxX, box.minY))
        assertPoint(s.position(of: .topRight), expected.x, expected.y, "should not snap")
    }

    func testSnappingCanBeDisabled() {
        var s = makeSession(snapping: false)
        let angle = Double.pi / 4 - (.pi / 180)
        s.rotate(to: angle)
        let expected = Transform2D.rotation(angle, about: box.center)
            .apply(to: Point(box.maxX, box.minY))
        assertPoint(s.position(of: .topRight), expected.x, expected.y)
    }

    func testSnapHelperRoundsToNearestMultipleWithinTolerance() {
        XCTAssertEqual(TransformSession.snap(0.98, increment: 1, tolerance: 0.05), 1)
        XCTAssertEqual(TransformSession.snap(0.5, increment: 1, tolerance: 0.05), 0.5)
        XCTAssertEqual(TransformSession.snap(-0.02, increment: 1, tolerance: 0.05), 0)
    }

    func testSnapHelperIgnoresNonPositiveIncrement() {
        XCTAssertEqual(TransformSession.snap(0.7, increment: 0, tolerance: 0.1), 0.7)
    }

    // MARK: - Flips

    func testHorizontalFlipPreservesBounds() {
        var s = makeSession()
        s.flipHorizontally()
        XCTAssertEqual(s.currentBounds.width, 100, accuracy: 1e-9)
        XCTAssertEqual(s.currentBounds.height, 100, accuracy: 1e-9)
        assertPoint(s.currentBounds.center, box.center.x, box.center.y)
    }

    func testHorizontalFlipMirrorsCornersAcrossTheCentre() {
        var s = makeSession()
        s.flipHorizontally()
        // The top-left handle's painted content now appears on the right.
        assertPoint(s.position(of: .topLeft), 50, -50)
        assertPoint(s.position(of: .topRight), -50, -50)
    }

    func testVerticalFlipMirrorsCornersAcrossTheCentre() {
        var s = makeSession()
        s.flipVertically()
        assertPoint(s.position(of: .topLeft), -50, 50)
        assertPoint(s.position(of: .bottomLeft), -50, -50)
    }

    func testFlippingTwiceReturnsToTheOriginalOrientation() {
        var s = makeSession()
        s.flipHorizontally()
        s.flipHorizontally()
        assertPoint(s.position(of: .topLeft), -50, -50)
    }

    func testFlipIsMirroredNotRotated() {
        var s = makeSession()
        s.flipHorizontally()
        // A mirror has negative determinant; a rotation would stay positive.
        XCTAssertLessThan(s.transform.determinant, 0)
    }

    // MARK: - Off-centre boxes

    func testTransformsRespectAnOffCentreBox() {
        let offset = Rect(x: 200, y: 100, width: 80, height: 40)
        var s = TransformSession(bounds: offset)
        s.flipHorizontally()
        XCTAssertEqual(s.currentBounds.center.x, offset.center.x, accuracy: 1e-9)
        XCTAssertEqual(s.currentBounds.center.y, offset.center.y, accuracy: 1e-9)
    }

    func testScalingAnOffCentreBoxKeepsAnchorFixed() {
        var s = TransformSession(bounds: Rect(x: 200, y: 100, width: 80, height: 40))
        let anchor = s.position(of: .bottomRight)
        s.scale(handle: .topLeft, to: Point(120, 60))
        assertPoint(s.position(of: .bottomRight), anchor.x, anchor.y)
    }
}
