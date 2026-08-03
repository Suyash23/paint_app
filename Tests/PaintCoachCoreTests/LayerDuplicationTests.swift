import XCTest
@testable import PaintCoachCore

/// Covers the Core half of UI_GAPS finding #9 — layer duplication.
final class LayerDuplicationTests: XCTestCase {

    private func populatedLayer() -> Layer {
        Layer(
            name: "Original",
            opacity: 0.6,
            isClippingMask: true,
            elements: [.stroke(.fixture()), .fill(.fixture(threshold: 0.3))]
        )
    }

    // MARK: - Identity

    func testDuplicateGetsANewLayerID() {
        let original = populatedLayer()
        XCTAssertNotEqual(original.duplicated().id, original.id)
    }

    func testDuplicateGivesEveryElementANewID() {
        let original = populatedLayer()
        let copy = original.duplicated()

        let originalIDs = Set(original.elements.map(\.id))
        let copyIDs = Set(copy.elements.map(\.id))
        XCTAssertTrue(
            originalIDs.isDisjoint(with: copyIDs),
            "element ids must not collide, or lookups and undo break"
        )
    }

    func testDuplicateKeepsElementCountAndOrder() {
        let original = populatedLayer()
        let copy = original.duplicated()

        XCTAssertEqual(copy.elements.count, original.elements.count)
        // A stroke then a fill must stay a stroke then a fill.
        XCTAssertEqual(copy.strokes.count, 1)
        XCTAssertEqual(copy.fills.count, 1)
        if case .stroke = copy.elements[0] {} else { XCTFail("first element should be the stroke") }
        if case .fill = copy.elements[1] {} else { XCTFail("second element should be the fill") }
    }

    // MARK: - Preserved state

    func testDuplicatePreservesAppearance() {
        let original = populatedLayer()
        let copy = original.duplicated()

        XCTAssertEqual(copy.opacity, original.opacity)
        XCTAssertEqual(copy.isClippingMask, original.isClippingMask)
        XCTAssertEqual(copy.isVisible, original.isVisible)
        XCTAssertEqual(copy.kind, original.kind)
    }

    func testDuplicatePreservesStrokeContent() {
        let stroke = Stroke.fixture()
        let copy = Layer(name: "L", elements: [.stroke(stroke)]).duplicated()
        let copied = copy.strokes[0]

        XCTAssertEqual(copied.brushID, stroke.brushID)
        XCTAssertEqual(copied.color, stroke.color)
        XCTAssertEqual(copied.size, stroke.size)
        XCTAssertEqual(copied.opacity, stroke.opacity)
        XCTAssertEqual(copied.points, stroke.points)
    }

    func testDuplicatePreservesFillContent() {
        let fill = Fill.fixture(origin: Point(31, 47), threshold: 0.42)
        let copy = Layer(name: "L", elements: [.fill(fill)]).duplicated()
        let copied = copy.fills[0]

        XCTAssertEqual(copied.color, fill.color)
        XCTAssertEqual(copied.origin, fill.origin)
        XCTAssertEqual(copied.threshold, fill.threshold)
    }

    func testDuplicateKeepsTheNameByDefault() {
        XCTAssertEqual(populatedLayer().duplicated().name, "Original")
    }

    func testDuplicateCanBeRenamed() {
        XCTAssertEqual(populatedLayer().duplicated(named: "Copy").name, "Copy")
    }

    func testEmptyLayerDuplicatesToAnEmptyLayer() {
        let copy = Layer(name: "Blank").duplicated()
        XCTAssertTrue(copy.isEmpty)
    }

    func testDuplicateIsIndependentOfTheOriginal() {
        var original = populatedLayer()
        let copy = original.duplicated()

        original.elements.removeAll()
        original.name = "Changed"

        XCTAssertEqual(copy.elements.count, 2, "the copy must not share storage")
        XCTAssertEqual(copy.name, "Original")
    }

    // MARK: - Document integration

    func testDuplicatedLayerCanBeAddedAboveItsOriginal() throws {
        var store = DocumentStore()
        let sourceID = store.document.activeLayerID
        try store.perform(.addStroke(layerID: sourceID, stroke: .fixture()))

        let copy = store.document.layer(id: sourceID)!.duplicated(named: "Layer copy")
        let index = store.document.index(of: sourceID)! + 1
        try store.perform(.addLayer(layer: copy, index: index))

        XCTAssertEqual(store.document.index(of: copy.id), index, "copy sits directly above")
        XCTAssertEqual(store.document.layer(id: copy.id)?.strokes.count, 1)
        // Both layers coexist, which is only possible with distinct ids.
        XCTAssertNotNil(store.document.layer(id: sourceID))
    }

    func testDuplicatingIsUndoable() throws {
        var store = DocumentStore()
        let before = store.document
        let copy = store.document.activeLayer.duplicated()
        try store.perform(.addLayer(layer: copy, index: store.document.topIndex))

        try store.undo()
        XCTAssertEqual(store.document, before)
    }
}
