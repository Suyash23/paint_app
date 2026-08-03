import XCTest
@testable import PaintCoachCore

/// Covers UI_GAPS finding #1 — selection / mask model.
final class SelectionTests: XCTestCase {

    private let unitRect = Rect(x: 0, y: 0, width: 100, height: 100)

    // MARK: - Region containment

    func testRectangleRegionContainment() {
        let r = SelectionRegion.rectangle(unitRect)
        XCTAssertTrue(r.contains(Point(50, 50)))
        XCTAssertTrue(r.contains(Point(0, 0)), "edges count as inside")
        XCTAssertFalse(r.contains(Point(150, 50)))
        XCTAssertFalse(r.contains(Point(-1, 50)))
    }

    func testEllipseRegionContainment() {
        let e = SelectionRegion.ellipse(unitRect)
        XCTAssertTrue(e.contains(Point(50, 50)), "centre is inside")
        XCTAssertTrue(e.contains(Point(50, 0)), "top of the arc is on the curve")
        // The rect's corner is outside an inscribed ellipse — the key difference.
        XCTAssertFalse(e.contains(Point(0, 0)), "corner is outside the inscribed ellipse")
    }

    func testStretchedEllipseRespectsBothRadii() {
        let e = SelectionRegion.ellipse(Rect(x: 0, y: 0, width: 200, height: 50))
        XCTAssertTrue(e.contains(Point(190, 25)))
        XCTAssertFalse(e.contains(Point(190, 5)))
    }

    func testDegenerateEllipseContainsNothing() {
        let e = SelectionRegion.ellipse(Rect(x: 0, y: 0, width: 0, height: 50))
        XCTAssertFalse(e.contains(Point(0, 25)))
    }

    func testPolygonRegionContainment() {
        // A triangle covering the lower-left half of the unit rect.
        let tri = SelectionRegion.polygon([Point(0, 0), Point(100, 0), Point(0, 100)])
        XCTAssertTrue(tri.contains(Point(10, 10)))
        XCTAssertFalse(tri.contains(Point(90, 90)), "beyond the hypotenuse")
    }

    func testConcavePolygonContainment() {
        // An L shape — the notch must not be considered inside.
        let l = SelectionRegion.polygon([
            Point(0, 0), Point(100, 0), Point(100, 40),
            Point(40, 40), Point(40, 100), Point(0, 100)
        ])
        XCTAssertTrue(l.contains(Point(20, 80)))
        XCTAssertTrue(l.contains(Point(80, 20)))
        XCTAssertFalse(l.contains(Point(80, 80)), "the notch is outside")
    }

    func testDegeneratePolygonContainsNothing() {
        XCTAssertFalse(SelectionRegion.polygon([]).contains(.zero))
        XCTAssertFalse(SelectionRegion.polygon([Point(0, 0), Point(1, 1)]).contains(Point(0.5, 0.5)))
    }

    func testRegionBounds() {
        XCTAssertEqual(SelectionRegion.rectangle(unitRect).bounds, unitRect)
        XCTAssertEqual(SelectionRegion.ellipse(unitRect).bounds, unitRect)
        XCTAssertEqual(
            SelectionRegion.polygon([Point(10, 20), Point(30, 5)]).bounds,
            Rect(x: 10, y: 5, width: 20, height: 15)
        )
        XCTAssertNil(SelectionRegion.polygon([]).bounds)
    }

    // MARK: - Empty selection

    func testEmptySelectionAllowsPaintingEverywhere() {
        let s = Selection.none
        XCTAssertTrue(s.isEmpty)
        XCTAssertFalse(s.isActive)
        XCTAssertTrue(s.contains(Point(9999, -9999)), "no selection means paint anywhere")
        XCTAssertEqual(s.coverage(at: Point(5, 5)), 1)
    }

    // MARK: - Combining modes

    func testReplaceDiscardsPreviousRegions() {
        var s = Selection()
        s.add(.rectangle(unitRect))
        s.add(.rectangle(Rect(x: 500, y: 500, width: 10, height: 10)), mode: .replace)
        XCTAssertEqual(s.steps.count, 1)
        XCTAssertFalse(s.contains(Point(50, 50)))
        XCTAssertTrue(s.contains(Point(505, 505)))
    }

    func testAddUnionsRegions() {
        var s = Selection()
        s.add(.rectangle(unitRect))
        s.add(.rectangle(Rect(x: 200, y: 0, width: 100, height: 100)), mode: .add)
        XCTAssertTrue(s.contains(Point(50, 50)))
        XCTAssertTrue(s.contains(Point(250, 50)))
        XCTAssertFalse(s.contains(Point(150, 50)), "the gap stays unselected")
    }

    func testSubtractRemovesFromSelection() {
        var s = Selection()
        s.add(.rectangle(unitRect))
        s.add(.rectangle(Rect(x: 0, y: 0, width: 50, height: 100)), mode: .subtract)
        XCTAssertFalse(s.contains(Point(25, 50)), "subtracted half")
        XCTAssertTrue(s.contains(Point(75, 50)), "remaining half")
    }

    func testIntersectKeepsOnlyTheOverlap() {
        var s = Selection()
        s.add(.rectangle(unitRect))
        s.add(.rectangle(Rect(x: 50, y: 0, width: 100, height: 100)), mode: .intersect)
        XCTAssertTrue(s.contains(Point(75, 50)), "in both")
        XCTAssertFalse(s.contains(Point(25, 50)), "only in the first")
        XCTAssertFalse(s.contains(Point(125, 50)), "only in the second")
    }

    func testModesApplyInOrder() {
        var s = Selection()
        s.add(.rectangle(unitRect))
        s.add(.rectangle(unitRect), mode: .subtract)
        s.add(.rectangle(Rect(x: 0, y: 0, width: 20, height: 20)), mode: .add)
        // Subtracted everything, then added a corner back.
        XCTAssertTrue(s.contains(Point(10, 10)))
        XCTAssertFalse(s.contains(Point(60, 60)))
    }

    // MARK: - Inversion

    func testInversionFlipsCoverage() {
        var s = Selection()
        s.add(.rectangle(unitRect))
        s.isInverted = true
        XCTAssertFalse(s.contains(Point(50, 50)), "inside the region is now excluded")
        XCTAssertTrue(s.contains(Point(500, 500)), "outside is now selected")
    }

    func testInvertingAnEmptySelectionSelectsNothing() {
        var s = Selection()
        s.isInverted = true
        XCTAssertTrue(s.isActive, "an inverted empty selection does restrict painting")
        XCTAssertFalse(s.contains(Point(50, 50)))
    }

    func testDoubleInversionRestoresOriginalCoverage() {
        var s = Selection()
        s.add(.rectangle(unitRect))
        let original = s.contains(Point(50, 50))
        s.isInverted = true
        s.isInverted = false
        XCTAssertEqual(s.contains(Point(50, 50)), original)
    }

    // MARK: - Feathering

    func testZeroFeatherGivesHardEdges() {
        var s = Selection()
        s.add(.rectangle(unitRect))
        XCTAssertEqual(s.coverage(at: Point(50, 50)), 1)
        XCTAssertEqual(s.coverage(at: Point(200, 50)), 0)
    }

    func testFeatherRampsCoverageNearTheEdge() {
        var s = Selection(featherRadius: 10)
        s.add(.rectangle(unitRect))
        // Well inside is full, on the edge is half, well outside is zero.
        XCTAssertEqual(s.coverage(at: Point(50, 50)), 1, accuracy: 1e-9)
        XCTAssertEqual(s.coverage(at: Point(0, 50)), 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.coverage(at: Point(-50, 50)), 0, accuracy: 1e-9)
    }

    func testFeatherIsMonotonicAcrossTheEdge() {
        var s = Selection(featherRadius: 20)
        s.add(.rectangle(unitRect))
        // Sample inward from outside the left edge; coverage must never decrease.
        let samples = stride(from: -25.0, through: 25.0, by: 5).map {
            s.coverage(at: Point($0, 50))
        }
        for (a, b) in zip(samples, samples.dropFirst()) {
            XCTAssertLessThanOrEqual(a, b, "feather ramp must be monotonic")
        }
    }

    func testCoverageStaysWithinUnitRange() {
        var s = Selection(featherRadius: 15)
        s.add(.ellipse(unitRect))
        for x in stride(from: -50.0, through: 150.0, by: 7) {
            let c = s.coverage(at: Point(x, 50))
            XCTAssertGreaterThanOrEqual(c, 0)
            XCTAssertLessThanOrEqual(c, 1)
        }
    }

    func testNegativeFeatherIsClampedToZero() {
        let s = Selection(featherRadius: -5)
        XCTAssertEqual(s.featherRadius, 0)
    }

    // MARK: - Bounds

    func testSelectionBoundsSpanAllAdditiveRegions() {
        var s = Selection()
        s.add(.rectangle(unitRect))
        s.add(.rectangle(Rect(x: 200, y: 50, width: 100, height: 100)), mode: .add)
        XCTAssertEqual(s.bounds, Rect(x: 0, y: 0, width: 300, height: 150))
    }

    func testSubtractedRegionsDoNotExtendBounds() {
        var s = Selection()
        s.add(.rectangle(unitRect))
        s.add(.rectangle(Rect(x: 900, y: 900, width: 50, height: 50)), mode: .subtract)
        XCTAssertEqual(s.bounds, unitRect)
    }

    func testInvertedSelectionHasNoFiniteBounds() {
        var s = Selection()
        s.add(.rectangle(unitRect))
        s.isInverted = true
        XCTAssertNil(s.bounds, "an inverted selection is unbounded")
    }

    func testEmptySelectionHasNoBounds() {
        XCTAssertNil(Selection.none.bounds)
    }

    // MARK: - Clearing

    func testClearResetsRegionsAndInversion() {
        var s = Selection()
        s.add(.rectangle(unitRect))
        s.isInverted = true
        s.clear()
        XCTAssertTrue(s.isEmpty)
        XCTAssertFalse(s.isActive)
        XCTAssertTrue(s.contains(Point(500, 500)), "cleared means paint anywhere")
    }

    // MARK: - Rect edge distance helper

    func testDistanceToRectEdgeInsideAndOutside() {
        let r = Rect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(Selection.distanceToRectEdge(from: Point(50, 50), rect: r), 50, accuracy: 1e-9)
        XCTAssertEqual(Selection.distanceToRectEdge(from: Point(10, 50), rect: r), 10, accuracy: 1e-9)
        XCTAssertEqual(Selection.distanceToRectEdge(from: Point(-10, 50), rect: r), 10, accuracy: 1e-9)
        // Diagonally off a corner.
        XCTAssertEqual(
            Selection.distanceToRectEdge(from: Point(-3, -4), rect: r), 5, accuracy: 1e-9
        )
        XCTAssertEqual(Selection.distanceToRectEdge(from: Point(0, 50), rect: r), 0, accuracy: 1e-9)
    }

    // MARK: - Document integration

    func testDocumentStartsWithNoSelection() {
        XCTAssertFalse(DocumentStore().document.selection.isActive)
    }

    func testSetSelectionCommandAppliesAndUndoes() throws {
        var store = DocumentStore()
        let before = store.document
        var selection = Selection()
        selection.add(.rectangle(unitRect))

        try store.perform(.setSelection(selection))
        XCTAssertTrue(store.document.selection.isActive)
        XCTAssertNotEqual(store.document, before)

        try store.undo()
        XCTAssertEqual(store.document, before)
    }

    func testRedoReappliesTheSelection() throws {
        var store = DocumentStore()
        var selection = Selection()
        selection.add(.ellipse(unitRect))

        try store.perform(.setSelection(selection))
        let afterSet = store.document
        try store.undo()
        try store.redo()
        XCTAssertEqual(store.document, afterSet)
    }

    func testSelectionPersistsAcrossLayerChanges() throws {
        var store = DocumentStore()
        var selection = Selection()
        selection.add(.rectangle(unitRect))
        try store.perform(.setSelection(selection))

        let layer = Layer(name: "Another")
        try store.perform(.addLayer(layer: layer, index: store.document.topIndex))
        try store.perform(.setActiveLayer(layerID: layer.id))

        XCTAssertTrue(store.document.selection.isActive, "selections are document-level")
    }

    func testInvertIsUndoableAsASelectionChange() throws {
        var store = DocumentStore()
        var selection = Selection()
        selection.add(.rectangle(unitRect))
        try store.perform(.setSelection(selection))

        var inverted = selection
        inverted.isInverted = true
        try store.perform(.setSelection(inverted))
        XCTAssertTrue(store.document.selection.isInverted)

        try store.undo()
        XCTAssertFalse(store.document.selection.isInverted)
    }

    // MARK: - Coding

    func testSelectionSurvivesCodingRoundTrip() throws {
        var store = DocumentStore()
        var selection = Selection(featherRadius: 8)
        selection.add(.rectangle(unitRect))
        selection.add(.ellipse(Rect(x: 20, y: 20, width: 40, height: 40)), mode: .subtract)
        selection.add(.polygon([Point(0, 0), Point(5, 0), Point(0, 5)]), mode: .add)
        selection.isInverted = true
        try store.perform(.setSelection(selection))

        let data = try JSONEncoder().encode(store.document)
        let decoded = try JSONDecoder().decode(Document.self, from: data)

        XCTAssertEqual(decoded, store.document)
        XCTAssertEqual(decoded.selection.steps.count, 3)
        XCTAssertEqual(decoded.selection.featherRadius, 8)
        XCTAssertTrue(decoded.selection.isInverted)
    }

    /// Documents saved before selections existed must still decode.
    func testDocumentDecodesWhenSelectionKeyIsAbsent() throws {
        let doc = Document()
        var json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(doc)
        ) as! [String: Any]
        json.removeValue(forKey: "selection")

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(Document.self, from: data)
        XCTAssertFalse(decoded.selection.isActive, "missing selection defaults to none")
    }
}
