import XCTest
@testable import PaintCoachCore

final class SeededGeneratorTests: XCTestCase {

    func testSameSeedProducesSameSequence() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        for _ in 0..<100 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testDifferentSeedsDiverge() {
        var a = SeededGenerator(seed: 1)
        var b = SeededGenerator(seed: 2)
        let left = (0..<32).map { _ in a.next() }
        let right = (0..<32).map { _ in b.next() }
        XCTAssertNotEqual(left, right)
    }

    func testZeroSeedDoesNotDegenerate() {
        var rng = SeededGenerator(seed: 0)
        let values = Set((0..<32).map { _ in rng.next() })
        XCTAssertGreaterThan(values.count, 1, "zero seed collapsed to a constant")
    }

    func testSameUUIDProducesSameSequence() {
        let id = UUID()
        var a = SeededGenerator(uuid: id)
        var b = SeededGenerator(uuid: id)
        for _ in 0..<50 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testDistinctUUIDsProduceDistinctSequences() {
        var a = SeededGenerator(uuid: UUID())
        var b = SeededGenerator(uuid: UUID())
        XCTAssertNotEqual((0..<16).map { _ in a.next() }, (0..<16).map { _ in b.next() })
    }

    func testUnitValuesStayInRange() {
        var rng = SeededGenerator(seed: 7)
        for _ in 0..<2000 {
            let value = rng.nextUnit()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
        }
    }

    func testSignedValuesStayInRange() {
        var rng = SeededGenerator(seed: 9)
        for _ in 0..<2000 {
            let value = rng.nextSigned()
            XCTAssertGreaterThanOrEqual(value, -1)
            XCTAssertLessThan(value, 1)
        }
    }

    func testDistributionIsRoughlyUniform() {
        var rng = SeededGenerator(seed: 12345)
        var buckets = [Int](repeating: 0, count: 10)
        let samples = 20_000
        for _ in 0..<samples {
            buckets[min(Int(rng.nextUnit() * 10), 9)] += 1
        }
        let expected = Double(samples) / 10
        for count in buckets {
            // Generous tolerance: catching a badly broken generator, not testing statistics.
            XCTAssertEqual(Double(count), expected, accuracy: expected * 0.2)
        }
    }
}
