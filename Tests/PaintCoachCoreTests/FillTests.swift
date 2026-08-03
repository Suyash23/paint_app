import XCTest
@testable import PaintCoachCore

/// Covers UI_GAPS finding #3 — fill / ColorDrop command.
final class FillTests: XCTestCase {

    // MARK: - Value semantics

    func testThresholdIsClampedIntoRange() {
        XCTAssertEqual(Fill.fixture(threshold: 2).threshold, 1)
        XCTAssertEqual(Fill.fixture(threshold: -1).threshold, 0)
        XCTAssertEqual(Fill.fixture(threshold: 0.35).threshold, 0.35)
    }

    // MARK: - Command behaviour

    func testAddFillAppendsToLayer() throws {
        var store = DocumentStore()
        try store.perform(.addFill(layerID: store.document.activeLayerID, fill: .fixture()))
        XCTAssertEqual(store.document.activeLayer.fills.count, 1)
    }

    func testAddFillThenUndoRestoresExactPriorDocument() throws {
        var store = DocumentStore()
        let before = store.document
        try store.perform(.addFill(layerID: store.document.activeLayerID, fill: .fixture()))
        XCTAssertNotEqual(store.document, before)
        try store.undo()
        XCTAssertEqual(store.document, before)
    }

    func testRedoReappliesTheFill() throws {
        var store = DocumentStore()
        let fill = Fill.fixture()
        try store.perform(.addFill(layerID: store.document.activeLayerID, fill: fill))
        let afterAdd = store.document
        try store.undo()
        try store.redo()
        XCTAssertEqual(store.document, afterAdd)
        XCTAssertEqual(store.document.activeLayer.fills.first?.id, fill.id)
    }

    func testFillOntoBackgroundLayerIsRejected() {
        var store = DocumentStore()
        let backgroundID = store.document.backgroundLayer.id
        XCTAssertThrowsError(
            try store.perform(.addFill(layerID: backgroundID, fill: .fixture()))
        ) { error in
            XCTAssertEqual(error as? DocumentError, .layerNotPaintable(backgroundID))
        }
    }

    func testFillOnLockedLayerIsRejected() throws {
        var store = DocumentStore()
        let id = store.document.activeLayerID
        try store.perform(.setLayerLocked(layerID: id, isLocked: true))
        XCTAssertThrowsError(try store.perform(.addFill(layerID: id, fill: .fixture())))
    }

    func testRemovingAMissingFillThrows() {
        var store = DocumentStore()
        let bogus = UUID()
        XCTAssertThrowsError(
            try store.perform(.removeFill(layerID: store.document.activeLayerID, fillID: bogus))
        ) { error in
            XCTAssertEqual(error as? DocumentError, .fillNotFound(bogus))
        }
    }

    func testFailedFillCommandLeavesDocumentAndUndoStackUntouched() {
        var store = DocumentStore()
        let before = store.document
        XCTAssertThrowsError(try store.perform(.addFill(layerID: UUID(), fill: .fixture())))
        XCTAssertEqual(store.document, before)
        XCTAssertFalse(store.canUndo)
    }

    // MARK: - Ordering against strokes

    /// The reason strokes and fills share one list: draw order is part of the picture.
    func testFillsAndStrokesKeepTheirRelativeDrawOrder() throws {
        var store = DocumentStore()
        let id = store.document.activeLayerID
        let firstStroke = Stroke.fixture()
        let fill = Fill.fixture()
        let lastStroke = Stroke.fixture()

        try store.perform(.addStroke(layerID: id, stroke: firstStroke))
        try store.perform(.addFill(layerID: id, fill: fill))
        try store.perform(.addStroke(layerID: id, stroke: lastStroke))

        XCTAssertEqual(
            store.document.activeLayer.elements.map(\.id),
            [firstStroke.id, fill.id, lastStroke.id]
        )
    }

    func testRemovingAFillLeavesSurroundingStrokesInOrder() throws {
        var store = DocumentStore()
        let id = store.document.activeLayerID
        let a = Stroke.fixture()
        let fill = Fill.fixture()
        let b = Stroke.fixture()

        try store.perform(.addStroke(layerID: id, stroke: a))
        try store.perform(.addFill(layerID: id, fill: fill))
        try store.perform(.addStroke(layerID: id, stroke: b))
        try store.perform(.removeFill(layerID: id, fillID: fill.id))

        XCTAssertEqual(store.document.activeLayer.elements.map(\.id), [a.id, b.id])
    }

    func testRemoveStrokeRejectsAFillID() throws {
        var store = DocumentStore()
        let id = store.document.activeLayerID
        let fill = Fill.fixture()
        try store.perform(.addFill(layerID: id, fill: fill))

        // A fill is not a stroke — the typed accessors must not alias.
        XCTAssertThrowsError(try store.perform(.removeStroke(layerID: id, strokeID: fill.id)))
    }

    // MARK: - Clearing

    func testClearLayerRemovesFillsAsWellAsStrokes() throws {
        var store = DocumentStore()
        let id = store.document.activeLayerID
        try store.perform(.addStroke(layerID: id, stroke: .fixture()))
        try store.perform(.addFill(layerID: id, fill: .fixture()))

        try store.perform(.clearLayer(layerID: id))
        XCTAssertTrue(store.document.activeLayer.isEmpty)
    }

    func testUndoingClearLayerRestoresFillsAndOrder() throws {
        var store = DocumentStore()
        let id = store.document.activeLayerID
        let a = Stroke.fixture()
        let fill = Fill.fixture()
        try store.perform(.addStroke(layerID: id, stroke: a))
        try store.perform(.addFill(layerID: id, fill: fill))
        let before = store.document

        try store.perform(.clearLayer(layerID: id))
        try store.undo()

        XCTAssertEqual(store.document, before)
        XCTAssertEqual(store.document.activeLayer.elements.map(\.id), [a.id, fill.id])
    }

    // MARK: - Coding

    func testFillSurvivesCodingRoundTrip() throws {
        var store = DocumentStore()
        let id = store.document.activeLayerID
        try store.perform(.addStroke(layerID: id, stroke: .fixture()))
        try store.perform(.addFill(layerID: id, fill: .fixture(threshold: 0.7)))

        let data = try JSONEncoder().encode(store.document)
        let decoded = try JSONDecoder().decode(Document.self, from: data)

        XCTAssertEqual(decoded, store.document)
        XCTAssertEqual(decoded.activeLayer.fills.first?.threshold, 0.7)
        XCTAssertEqual(decoded.activeLayer.elements.count, 2)
    }
}

// MARK: - Fixtures

extension Fill {
    static func fixture(
        id: UUID = UUID(),
        origin: Point = Point(120, 80),
        threshold: Double = 0.5
    ) -> Fill {
        Fill(id: id, color: .black, origin: origin, threshold: threshold)
    }
}
