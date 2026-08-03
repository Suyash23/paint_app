import XCTest
@testable import PaintCoachCore

/// Covers UI_GAPS finding #2 — clipping-mask representation.
final class ClippingMaskTests: XCTestCase {

    /// Adds `count` paint layers above the default stack and returns their ids,
    /// bottom-most first.
    private func addPaintLayers(_ count: Int, to store: inout DocumentStore) throws -> [UUID] {
        try (0..<count).map { i in
            let layer = Layer(name: "Extra \(i)")
            try store.perform(.addLayer(layer: layer, index: store.document.topIndex))
            return layer.id
        }
    }

    // MARK: - Defaults

    func testLayersAreNotClippingMasksByDefault() {
        let store = DocumentStore()
        XCTAssertFalse(store.document.activeLayer.isClippingMask)
        XCTAssertFalse(store.document.backgroundLayer.isClippingMask)
    }

    // MARK: - Command behaviour

    func testSetClippingMaskEnablesTheFlag() throws {
        var store = DocumentStore()
        let id = store.document.activeLayerID
        try store.perform(.setLayerClippingMask(layerID: id, isClippingMask: true))
        XCTAssertTrue(store.document.activeLayer.isClippingMask)
    }

    func testSetClippingMaskThenUndoRestoresExactPriorDocument() throws {
        var store = DocumentStore()
        let before = store.document
        try store.perform(.setLayerClippingMask(layerID: store.document.activeLayerID, isClippingMask: true))
        XCTAssertNotEqual(store.document, before)
        try store.undo()
        XCTAssertEqual(store.document, before)
    }

    func testRedoReappliesTheClippingMask() throws {
        var store = DocumentStore()
        let id = store.document.activeLayerID
        try store.perform(.setLayerClippingMask(layerID: id, isClippingMask: true))
        let afterSet = store.document
        try store.undo()
        try store.redo()
        XCTAssertEqual(store.document, afterSet)
        XCTAssertTrue(store.document.activeLayer.isClippingMask)
    }

    func testBackgroundColorLayerCannotBecomeAClippingMask() {
        var store = DocumentStore()
        let backgroundID = store.document.backgroundLayer.id
        XCTAssertThrowsError(
            try store.perform(.setLayerClippingMask(layerID: backgroundID, isClippingMask: true))
        ) { error in
            XCTAssertEqual(error as? DocumentError, .layerNotClippable(backgroundID))
        }
    }

    func testSettingClippingMaskOnMissingLayerThrows() {
        var store = DocumentStore()
        let bogus = UUID()
        XCTAssertThrowsError(
            try store.perform(.setLayerClippingMask(layerID: bogus, isClippingMask: true))
        ) { error in
            XCTAssertEqual(error as? DocumentError, .layerNotFound(bogus))
        }
    }

    func testFailedClippingMaskCommandLeavesDocumentAndUndoStackUntouched() {
        var store = DocumentStore()
        let before = store.document
        XCTAssertThrowsError(
            try store.perform(.setLayerClippingMask(layerID: UUID(), isClippingMask: true))
        )
        XCTAssertEqual(store.document, before)
        XCTAssertFalse(store.canUndo)
    }

    // MARK: - Base resolution

    func testNonClippingLayerHasNoClippingBase() {
        let store = DocumentStore()
        XCTAssertNil(store.document.clippingBase(for: store.document.activeLayerID))
    }

    func testClippingBaseIsTheLayerDirectlyBelow() throws {
        var store = DocumentStore()
        let base = store.document.activeLayerID
        let ids = try addPaintLayers(1, to: &store)
        let masked = ids[0]

        try store.perform(.setLayerClippingMask(layerID: masked, isClippingMask: true))
        XCTAssertEqual(store.document.clippingBase(for: masked)?.id, base)
    }

    func testStackedClippingMasksShareTheSameBase() throws {
        var store = DocumentStore()
        let base = store.document.activeLayerID
        let ids = try addPaintLayers(2, to: &store)

        for id in ids {
            try store.perform(.setLayerClippingMask(layerID: id, isClippingMask: true))
        }

        // Both masks clip to the one non-mask layer beneath the run.
        XCTAssertEqual(store.document.clippingBase(for: ids[0])?.id, base)
        XCTAssertEqual(store.document.clippingBase(for: ids[1])?.id, base)
    }

    func testClippingBaseCanBeTheBackgroundColorLayer() throws {
        var store = DocumentStore()
        // The bottom-most paint layer clips to the pinned Background Color layer.
        let bottomPaint = store.document.activeLayerID
        try store.perform(.setLayerClippingMask(layerID: bottomPaint, isClippingMask: true))
        XCTAssertEqual(
            store.document.clippingBase(for: bottomPaint)?.id,
            store.document.backgroundLayer.id
        )
    }

    func testClippingBaseFollowsReordering() throws {
        var store = DocumentStore()
        let firstPaint = store.document.activeLayerID
        let ids = try addPaintLayers(2, to: &store)
        let masked = ids[1]
        try store.perform(.setLayerClippingMask(layerID: masked, isClippingMask: true))
        XCTAssertEqual(store.document.clippingBase(for: masked)?.id, ids[0])

        // Move the mask down so it now sits directly above the first paint layer.
        let newIndex = store.document.index(of: ids[0])!
        try store.perform(.moveLayer(layerID: masked, to: newIndex))
        XCTAssertEqual(store.document.clippingBase(for: masked)?.id, firstPaint)
    }

    func testClippingMaskSurvivesCodingRoundTrip() throws {
        var store = DocumentStore()
        try store.perform(.setLayerClippingMask(layerID: store.document.activeLayerID, isClippingMask: true))

        let data = try JSONEncoder().encode(store.document)
        let decoded = try JSONDecoder().decode(Document.self, from: data)

        XCTAssertEqual(decoded, store.document)
        XCTAssertTrue(decoded.activeLayer.isClippingMask)
    }
}
