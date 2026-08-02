import XCTest
@testable import PaintCoachCore

final class RectTests: XCTestCase {

    func testBasicAccessors() {
        let rect = Rect(x: 10, y: 20, width: 30, height: 40)
        XCTAssertEqual(rect.minX, 10)
        XCTAssertEqual(rect.minY, 20)
        XCTAssertEqual(rect.maxX, 40)
        XCTAssertEqual(rect.maxY, 60)
        XCTAssertEqual(rect.center, Point(25, 40))
        XCTAssertFalse(rect.isEmpty)
    }

    func testNegativeDimensionsAreClampedToEmpty() {
        let rect = Rect(x: 0, y: 0, width: -10, height: -5)
        XCTAssertTrue(rect.isEmpty)
        XCTAssertEqual(rect.width, 0)
        XCTAssertEqual(rect.height, 0)
    }

    func testCornersInitAcceptsAnyOrder() {
        let a = Rect(corners: Point(30, 40), Point(10, 20))
        let b = Rect(corners: Point(10, 20), Point(30, 40))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, Rect(x: 10, y: 20, width: 20, height: 20))
    }

    func testBoundingPoints() {
        let rect = Rect(bounding: [Point(5, 5), Point(-3, 10), Point(12, -2)])
        XCTAssertEqual(rect, Rect(x: -3, y: -2, width: 15, height: 12))
    }

    func testBoundingEmptyArrayIsNil() {
        XCTAssertNil(Rect(bounding: []))
    }

    func testUnion() {
        let a = Rect(x: 0, y: 0, width: 10, height: 10)
        let b = Rect(x: 20, y: 20, width: 10, height: 10)
        XCTAssertEqual(a.union(b), Rect(x: 0, y: 0, width: 30, height: 30))
    }

    func testUnionTreatsEmptyAsNoContribution() {
        let real = Rect(x: 100, y: 100, width: 10, height: 10)
        // A zero rect at the origin must not drag the union back to (0,0).
        XCTAssertEqual(real.union(.zero), real)
        XCTAssertEqual(Rect.zero.union(real), real)
    }

    func testUnionIsCommutativeAndIdempotent() {
        let a = Rect(x: 3, y: 4, width: 10, height: 2)
        let b = Rect(x: -5, y: 1, width: 4, height: 20)
        XCTAssertEqual(a.union(b), b.union(a))
        XCTAssertEqual(a.union(a), a)
    }

    func testIntersectionOfOverlappingRects() {
        let a = Rect(x: 0, y: 0, width: 20, height: 20)
        let b = Rect(x: 10, y: 10, width: 20, height: 20)
        XCTAssertEqual(a.intersection(b), Rect(x: 10, y: 10, width: 10, height: 10))
    }

    func testDisjointRectsDoNotIntersect() {
        let a = Rect(x: 0, y: 0, width: 5, height: 5)
        let b = Rect(x: 100, y: 100, width: 5, height: 5)
        XCTAssertNil(a.intersection(b))
        XCTAssertFalse(a.intersects(b))
    }

    func testTouchingEdgesDoNotCountAsIntersecting() {
        let a = Rect(x: 0, y: 0, width: 10, height: 10)
        let b = Rect(x: 10, y: 0, width: 10, height: 10)
        // Zero-area overlap is not a dirty region worth redrawing.
        XCTAssertNil(a.intersection(b))
    }

    func testContains() {
        let rect = Rect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertTrue(rect.contains(Point(5, 5)))
        XCTAssertTrue(rect.contains(Point(0, 0)))
        XCTAssertTrue(rect.contains(Point(10, 10)))
        XCTAssertFalse(rect.contains(Point(11, 5)))
    }

    func testInsetGrowsAndShrinks() {
        let rect = Rect(x: 10, y: 10, width: 10, height: 10)
        XCTAssertEqual(rect.insetBy(5), Rect(x: 5, y: 5, width: 20, height: 20))
        XCTAssertEqual(rect.insetBy(-2), Rect(x: 12, y: 12, width: 6, height: 6))
    }

    func testIntegralExpandsToWholePixels() {
        let rect = Rect(x: 10.3, y: 20.7, width: 5.2, height: 4.1)
        let integral = rect.integral()
        XCTAssertEqual(integral.minX, 10)
        XCTAssertEqual(integral.minY, 20)
        XCTAssertEqual(integral.maxX, 16)
        XCTAssertEqual(integral.maxY, 25)
        // Must never shrink — a clipped edge pixel is a visible artifact.
        XCTAssertLessThanOrEqual(integral.minX, rect.minX)
        XCTAssertGreaterThanOrEqual(integral.maxX, rect.maxX)
    }

    func testIntegralIsIdempotent() {
        let once = Rect(x: 1.4, y: 2.6, width: 3.3, height: 4.9).integral()
        XCTAssertEqual(once.integral(), once)
    }

    func testClippingToCanvas() {
        let canvas = CanvasSize(width: 100, height: 100)
        let straddling = Rect(x: -10, y: -10, width: 50, height: 50)
        XCTAssertEqual(straddling.clipped(to: canvas), Rect(x: 0, y: 0, width: 40, height: 40))
    }

    func testRectFullyOutsideCanvasClipsToNil() {
        let canvas = CanvasSize(width: 100, height: 100)
        XCTAssertNil(Rect(x: 200, y: 200, width: 10, height: 10).clipped(to: canvas))
    }

    func testCodableRoundTrip() throws {
        let rect = Rect(x: 1.5, y: 2.5, width: 3.5, height: 4.5)
        let data = try JSONEncoder().encode(rect)
        XCTAssertEqual(try JSONDecoder().decode(Rect.self, from: data), rect)
    }
}
