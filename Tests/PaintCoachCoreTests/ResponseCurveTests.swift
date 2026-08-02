import XCTest
@testable import PaintCoachCore

final class ResponseCurveTests: XCTestCase {

    func testLinearCurveMapsEndpointsExactly() {
        let curve = ResponseCurve(minimum: 0.2, maximum: 0.8)
        XCTAssertEqual(curve.value(for: 0), 0.2, accuracy: 1e-12)
        XCTAssertEqual(curve.value(for: 1), 0.8, accuracy: 1e-12)
        XCTAssertEqual(curve.value(for: 0.5), 0.5, accuracy: 1e-12)
    }

    func testInputIsClamped() {
        let curve = ResponseCurve(minimum: 0, maximum: 1)
        XCTAssertEqual(curve.value(for: -5), 0, accuracy: 1e-12)
        XCTAssertEqual(curve.value(for: 5), 1, accuracy: 1e-12)
    }

    func testExponentAboveOneBiasesTowardMinimum() {
        let curve = ResponseCurve(minimum: 0, maximum: 1, exponent: 2)
        // Midpoint input yields a quarter of the range, not half.
        XCTAssertEqual(curve.value(for: 0.5), 0.25, accuracy: 1e-12)
        XCTAssertLessThan(curve.value(for: 0.5), 0.5)
    }

    func testExponentBelowOneBiasesTowardMaximum() {
        let curve = ResponseCurve(minimum: 0, maximum: 1, exponent: 0.5)
        XCTAssertGreaterThan(curve.value(for: 0.5), 0.5)
    }

    func testEndpointsHoldRegardlessOfExponent() {
        for exponent in [0.25, 1.0, 3.0] {
            let curve = ResponseCurve(minimum: 0.1, maximum: 0.9, exponent: exponent)
            XCTAssertEqual(curve.value(for: 0), 0.1, accuracy: 1e-12)
            XCTAssertEqual(curve.value(for: 1), 0.9, accuracy: 1e-12)
        }
    }

    func testFlatCurveAlwaysReturnsOne() {
        for input in [0.0, 0.3, 1.0] {
            XCTAssertEqual(ResponseCurve.flat.value(for: input), 1, accuracy: 1e-12)
        }
    }

    func testCurveIsMonotonic() {
        let curve = ResponseCurve(minimum: 0.2, maximum: 1, exponent: 1.4)
        var previous = -Double.infinity
        for step in 0...20 {
            let value = curve.value(for: Double(step) / 20)
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
    }
}
