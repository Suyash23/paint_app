import XCTest
@testable import PaintCoachCore

final class DocumentCommandTests: XCTestCase {

    // MARK: - Stroke commands

    func testAddStrokeAppendsToActiveLayer() throws {
        var store = DocumentStore()
        let target = store.document.activeLayerID
        try store.perform(.addStroke(layerID: target, stroke: .fixture()))
        XCTAssertEqual(store.document.activeLayer.strokes.count, 1)
    }

    func testAddStrokeThenUndoRestoresExactPriorDocument() throws {
        var store = DocumentStore()
        let before = store.document
        try store.perform(.addStroke(layerID: store.document.activeLayerID, stroke: .fixture()))
        XCTAssertNotEqual(store.document, before)
        try store.undo()
        XCTAssertEqual(store.document, before)
    }

    func testRedoReappliesTheStroke() throws {
        var store = DocumentStore()
        let stroke = Stroke.fixture()
        try store.perform(.addStroke(layerID: store.document.activeLayerID, stroke: stroke))
        let afterAdd = store.document
        try store.undo()
        try store.redo()
        XCTAssertEqual(store.document, afterAdd)
        XCTAssertEqual(store.document.activeLayer.strokes.first?.id, stroke.id)
    }

    func testStrokesPaintOntoBackgroundLayerAreRejected() {
        var store = DocumentStore()
        let backgroundID = store.document.backgroundLayer.id
        XCTAssertThrowsError(
            try store.perform(.addStroke(layerID: backgroundID, stroke: .fixture()))
        ) { error in
            XCTAssertEqual(error as? DocumentError, .layerNotPaintable(backgroundID))
        }
    }

    func testStrokesOnLockedLayerAreRejected() throws {
        var store = DocumentStore()
        let id = store.document.activeLayerID
        try store.perform(.setLayerLocked(layerID: id, isLocked: true))
        XCTAssertThrowsError(try store.perform(.addStroke(layerID: id, stroke: .fixture())))
    }

    // MARK: - Failure atomicity

    func testFailedCommandLeavesDocumentAndUndoStackUntouched() {
        var store = DocumentStore()
        let before = store.document
        let bogus = UUID()
        XCTAssertThrowsError(try store.perform(.addStroke(layerID: bogus, stroke: .fixture())))
        XCTAssertEqual(store.document, before, "a throwing command must not mutate the document")
        XCTAssertFalse(store.canUndo, "a throwing command must not push onto the undo stack")
    }

    // MARK: - Multi-step undo ordering

    func testUndoUnwindsInReverseOrder() throws {
        var store = DocumentStore()
        let layerID = store.document.activeLayerID
        let a = Stroke.fixture(), b = Stroke.fixture(), c = Stroke.fixture()

        try store.perform(.addStroke(layerID: layerID, stroke: a))
        try store.perform(.addStroke(layerID: layerID, stroke: b))
        try store.perform(.addStroke(layerID: layerID, stroke: c))
        XCTAssertEqual(store.document.activeLayer.strokes.map(\.id), [a.id, b.id, c.id])

        try store.undo()
        XCTAssertEqual(store.document.activeLayer.strokes.map(\.id), [a.id, b.id])
        try store.undo()
        XCTAssertEqual(store.document.activeLayer.strokes.map(\.id), [a.id])
        try store.undo()
        XCTAssertTrue(store.document.activeLayer.strokes.isEmpty)
        XCTAssertFalse(store.canUndo)
    }

    func testNewCommandClearsRedoStack() throws {
        var store = DocumentStore()
        let layerID = store.document.activeLayerID
        try store.perform(.addStroke(layerID: layerID, stroke: .fixture()))
        try store.undo()
        XCTAssertTrue(store.canRedo)
        try store.perform(.addStroke(layerID: layerID, stroke: .fixture()))
        XCTAssertFalse(store.canRedo, "a fresh command must invalidate the redo branch")
    }

    func testUndoAndRedoOnEmptyStacksAreNoOps() throws {
        var store = DocumentStore()
        let before = store.document
        try store.undo()
        try store.redo()
        XCTAssertEqual(store.document, before)
    }

    // MARK: - Layer commands

    func testAddLayerInsertsAboveBackgroundAndUndoRemovesIt() throws {
        var store = DocumentStore()
        let new = Layer(name: "Layer 2")
        try store.perform(.addLayer(layer: new, index: store.document.topIndex))
        XCTAssertEqual(store.document.layers.count, 3)
        XCTAssertEqual(store.document.layers.last?.name, "Layer 2")
        try store.undo()
        XCTAssertEqual(store.document.layers.count, 2)
    }

    func testLayerCannotBeInsertedBelowBackground() {
        var store = DocumentStore()
        XCTAssertThrowsError(try store.perform(.addLayer(layer: Layer(name: "X"), index: 0))) {
            XCTAssertEqual($0 as? DocumentError, .indexOutOfRange(0))
        }
    }

    func testBackgroundLayerCannotBeDeleted() {
        var store = DocumentStore()
        let id = store.document.backgroundLayer.id
        XCTAssertThrowsError(try store.perform(.deleteLayer(layerID: id))) {
            XCTAssertEqual($0 as? DocumentError, .backgroundLayerImmovable)
        }
    }

    func testBackgroundLayerCannotBeMoved() {
        var store = DocumentStore()
        let id = store.document.backgroundLayer.id
        XCTAssertThrowsError(try store.perform(.moveLayer(layerID: id, to: 1))) {
            XCTAssertEqual($0 as? DocumentError, .backgroundLayerImmovable)
        }
    }

    func testLastPaintLayerCannotBeDeleted() {
        var store = DocumentStore()
        let id = store.document.activeLayerID
        XCTAssertThrowsError(try store.perform(.deleteLayer(layerID: id))) {
            XCTAssertEqual($0 as? DocumentError, .lastPaintLayer)
        }
    }

    func testDeleteLayerRestoresAtOriginalIndexOnUndo() throws {
        var store = DocumentStore()
        let middle = Layer(name: "Middle")
        try store.perform(.addLayer(layer: middle, index: 1))
        try store.perform(.addLayer(layer: Layer(name: "Top"), index: store.document.topIndex))
        let before = store.document

        try store.perform(.deleteLayer(layerID: middle.id))
        XCTAssertNil(store.document.layer(id: middle.id))

        try store.undo()
        XCTAssertEqual(store.document, before)
        XCTAssertEqual(store.document.index(of: middle.id), 1)
    }

    func testDeletingActiveLayerReassignsActiveLayer() throws {
        var store = DocumentStore()
        let top = Layer(name: "Top")
        try store.perform(.addLayer(layer: top, index: store.document.topIndex))
        try store.perform(.setActiveLayer(layerID: top.id))
        try store.perform(.deleteLayer(layerID: top.id))

        XCTAssertNotEqual(store.document.activeLayerID, top.id)
        XCTAssertNotNil(store.document.layer(id: store.document.activeLayerID))
    }

    func testMoveLayerUndoReturnsToOriginalIndex() throws {
        var store = DocumentStore()
        let a = Layer(name: "A"), b = Layer(name: "B")
        try store.perform(.addLayer(layer: a, index: store.document.topIndex))
        try store.perform(.addLayer(layer: b, index: store.document.topIndex))
        let before = store.document

        try store.perform(.moveLayer(layerID: a.id, to: 3))
        XCTAssertEqual(store.document.index(of: a.id), 3)
        try store.undo()
        XCTAssertEqual(store.document, before)
    }

    func testOpacityIsClampedAndUndoRestoresPrevious() throws {
        var store = DocumentStore()
        let id = store.document.activeLayerID
        try store.perform(.setLayerOpacity(layerID: id, opacity: 5))
        XCTAssertEqual(store.document.activeLayer.opacity, 1)
        try store.perform(.setLayerOpacity(layerID: id, opacity: -2))
        XCTAssertEqual(store.document.activeLayer.opacity, 0)
        try store.undo()
        XCTAssertEqual(store.document.activeLayer.opacity, 1)
    }

    func testVisibilityAndRenameToggleAndUndoCleanly() throws {
        var store = DocumentStore()
        let id = store.document.activeLayerID
        try store.perform(.setLayerVisibility(layerID: id, isVisible: false))
        XCTAssertFalse(store.document.activeLayer.isVisible)
        try store.perform(.renameLayer(layerID: id, name: "Sketch"))
        XCTAssertEqual(store.document.activeLayer.name, "Sketch")
        try store.undo()
        XCTAssertEqual(store.document.activeLayer.name, "Layer 1")
        try store.undo()
        XCTAssertTrue(store.document.activeLayer.isVisible)
    }

    // MARK: - Clear layer (3-finger scrub)

    func testClearLayerRemovesAllStrokesAndUndoRestoresThemInOrder() throws {
        var store = DocumentStore()
        let layerID = store.document.activeLayerID
        let a = Stroke.fixture(), b = Stroke.fixture()
        try store.perform(.addStroke(layerID: layerID, stroke: a))
        try store.perform(.addStroke(layerID: layerID, stroke: b))
        let before = store.document

        try store.perform(.clearLayer(layerID: layerID))
        XCTAssertTrue(store.document.activeLayer.strokes.isEmpty)

        try store.undo()
        XCTAssertEqual(store.document, before)
        XCTAssertEqual(store.document.activeLayer.strokes.map(\.id), [a.id, b.id])
    }

    func testClearLayerRedoClearsAgain() throws {
        var store = DocumentStore()
        let layerID = store.document.activeLayerID
        try store.perform(.addStroke(layerID: layerID, stroke: .fixture()))
        try store.perform(.clearLayer(layerID: layerID))
        try store.undo()
        try store.redo()
        XCTAssertTrue(store.document.activeLayer.strokes.isEmpty)
    }

    // MARK: - Long-run invariant

    func testFullUndoOfLongSessionReturnsToPristineDocument() throws {
        var store = DocumentStore()
        let pristine = store.document
        let layerID = store.document.activeLayerID
        let extra = Layer(name: "Extra")

        try store.perform(.addStroke(layerID: layerID, stroke: .fixture()))
        try store.perform(.addLayer(layer: extra, index: store.document.topIndex))
        try store.perform(.setActiveLayer(layerID: extra.id))
        try store.perform(.addStroke(layerID: extra.id, stroke: .fixture()))
        try store.perform(.setLayerOpacity(layerID: extra.id, opacity: 0.3))
        try store.perform(.renameLayer(layerID: extra.id, name: "Ink"))
        try store.perform(.clearLayer(layerID: extra.id))

        while store.canUndo { try store.undo() }
        XCTAssertEqual(store.document, pristine)

        while store.canRedo { try store.redo() }
        XCTAssertEqual(store.document.layer(id: extra.id)?.name, "Ink")
        XCTAssertEqual(store.document.layer(id: extra.id)?.opacity, 0.3)
    }
}
