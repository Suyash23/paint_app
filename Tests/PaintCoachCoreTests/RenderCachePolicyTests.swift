import XCTest
@testable import PaintCoachCore

final class RenderCachePolicyTests: XCTestCase {

    private let region = Rect(x: 10, y: 10, width: 50, height: 50)

    private func plan(_ policy: RenderCachePolicy, _ document: Document, layerID: UUID) -> LayerRenderPlan? {
        policy.plan(for: document).passes.first { $0.layerID == layerID }?.plan
    }

    // MARK: - Initial state

    func testUnknownLayerHasNoCacheAndNeedsFullRedraw() {
        let document = Document()
        let policy = RenderCachePolicy()
        XCTAssertFalse(policy.hasValidCache(for: document.activeLayerID))
        XCTAssertEqual(plan(policy, document, layerID: document.activeLayerID), .fullRedraw)
    }

    func testPlanCoversEveryLayerBottomFirst() {
        let document = Document()
        let passes = RenderCachePolicy().plan(for: document).passes
        XCTAssertEqual(passes.map(\.layerID), document.layers.map(\.id))
    }

    // MARK: - Clean / invalid transitions

    func testMarkCleanEnablesCacheReuse() {
        let document = Document()
        var policy = RenderCachePolicy()
        policy.markClean(layerID: document.activeLayerID)
        XCTAssertTrue(policy.hasValidCache(for: document.activeLayerID))
        XCTAssertEqual(plan(policy, document, layerID: document.activeLayerID), .reuseCache)
    }

    func testFullInvalidationForcesRedraw() {
        let document = Document()
        var policy = RenderCachePolicy()
        policy.markClean(layerID: document.activeLayerID)
        policy.invalidate(layerID: document.activeLayerID)
        XCTAssertFalse(policy.hasValidCache(for: document.activeLayerID))
        XCTAssertEqual(plan(policy, document, layerID: document.activeLayerID), .fullRedraw)
    }

    func testRegionInvalidationOnCleanCacheGivesIncrementalPlan() {
        let document = Document()
        var policy = RenderCachePolicy()
        policy.markClean(layerID: document.activeLayerID)
        policy.invalidate(layerID: document.activeLayerID, region: region)
        XCTAssertEqual(plan(policy, document, layerID: document.activeLayerID), .incremental(region: region))
    }

    func testDirtyRegionsAccumulateByUnion() {
        let document = Document()
        var policy = RenderCachePolicy()
        let layerID = document.activeLayerID
        policy.markClean(layerID: layerID)
        policy.invalidate(layerID: layerID, region: Rect(x: 0, y: 0, width: 10, height: 10))
        policy.invalidate(layerID: layerID, region: Rect(x: 90, y: 90, width: 10, height: 10))
        XCTAssertEqual(policy.dirtyRegion(for: layerID), Rect(x: 0, y: 0, width: 100, height: 100))
    }

    func testFullInvalidationSubsumesRegionInvalidation() {
        let document = Document()
        var policy = RenderCachePolicy()
        let layerID = document.activeLayerID
        // Region dirtying must never downgrade an already-full invalidation.
        policy.invalidate(layerID: layerID)
        policy.invalidate(layerID: layerID, region: region)
        XCTAssertEqual(plan(policy, document, layerID: layerID), .fullRedraw)
        XCTAssertNil(policy.dirtyRegion(for: layerID))
    }

    func testEmptyRegionIsIgnored() {
        let document = Document()
        var policy = RenderCachePolicy()
        let layerID = document.activeLayerID
        policy.markClean(layerID: layerID)
        policy.invalidate(layerID: layerID, region: .zero)
        XCTAssertEqual(plan(policy, document, layerID: layerID), .reuseCache)
    }

    func testMarkCleanClearsDirtyRegion() {
        let document = Document()
        var policy = RenderCachePolicy()
        let layerID = document.activeLayerID
        policy.markClean(layerID: layerID)
        policy.invalidate(layerID: layerID, region: region)
        policy.markClean(layerID: layerID)
        XCTAssertNil(policy.dirtyRegion(for: layerID))
        XCTAssertEqual(plan(policy, document, layerID: layerID), .reuseCache)
    }

    func testInvalidateAllForcesEveryKnownLayerToRedraw() {
        var document = Document()
        let second = Layer(name: "Second")
        try? DocumentCommand.addLayer(layer: second, index: document.topIndex).apply(to: &document)

        var policy = RenderCachePolicy()
        for layer in document.layers { policy.markClean(layerID: layer.id) }
        policy.invalidateAll()

        for pass in policy.plan(for: document).passes {
            XCTAssertEqual(pass.plan, .fullRedraw)
        }
    }

    // MARK: - Visibility and opacity

    func testHiddenLayerIsSkipped() throws {
        var document = Document()
        let layerID = document.activeLayerID
        try DocumentCommand.setLayerVisibility(layerID: layerID, isVisible: false).apply(to: &document)

        var policy = RenderCachePolicy()
        policy.markClean(layerID: layerID)
        XCTAssertEqual(plan(policy, document, layerID: layerID), .skip)
    }

    func testFullyTransparentLayerIsSkipped() throws {
        var document = Document()
        let layerID = document.activeLayerID
        try DocumentCommand.setLayerOpacity(layerID: layerID, opacity: 0).apply(to: &document)

        var policy = RenderCachePolicy()
        policy.markClean(layerID: layerID)
        XCTAssertEqual(plan(policy, document, layerID: layerID), .skip)
    }

    func testHiddenDirtyLayerIsStillSkippedButStaysDirty() throws {
        var document = Document()
        let layerID = document.activeLayerID
        var policy = RenderCachePolicy()
        policy.invalidate(layerID: layerID)

        try DocumentCommand.setLayerVisibility(layerID: layerID, isVisible: false).apply(to: &document)
        XCTAssertEqual(plan(policy, document, layerID: layerID), .skip)

        // Becoming visible again must still trigger the deferred repaint.
        try DocumentCommand.setLayerVisibility(layerID: layerID, isVisible: true).apply(to: &document)
        XCTAssertEqual(plan(policy, document, layerID: layerID), .fullRedraw)
    }

    func testOpacityIsCarriedOnThePass() throws {
        var document = Document()
        let layerID = document.activeLayerID
        try DocumentCommand.setLayerOpacity(layerID: layerID, opacity: 0.42).apply(to: &document)
        let pass = RenderCachePolicy().plan(for: document).passes.first { $0.layerID == layerID }
        XCTAssertEqual(pass?.opacity, 0.42)
    }

    // MARK: - Live stroke

    func testLiveStrokeDoesNotInvalidateTheLayerCache() {
        let document = Document()
        var policy = RenderCachePolicy()
        let layerID = document.activeLayerID
        policy.markClean(layerID: layerID)

        policy.beginLiveStroke(layerID: layerID)
        // The whole point of Option A: a growing stroke must not repaint the layer.
        XCTAssertEqual(plan(policy, document, layerID: layerID), .reuseCache)
        XCTAssertEqual(policy.plan(for: document).liveStrokeLayerID, layerID)
    }

    func testEndingLiveStrokeDirtiesOnlyThePaintedRegion() {
        let document = Document()
        var policy = RenderCachePolicy()
        let layerID = document.activeLayerID
        policy.markClean(layerID: layerID)

        policy.beginLiveStroke(layerID: layerID)
        policy.endLiveStroke(dirtyRegion: region)

        XCTAssertNil(policy.liveStrokeLayerID)
        XCTAssertEqual(plan(policy, document, layerID: layerID), .incremental(region: region))
    }

    func testEndingLiveStrokeWithoutRegionFallsBackToFullRedraw() {
        let document = Document()
        var policy = RenderCachePolicy()
        let layerID = document.activeLayerID
        policy.markClean(layerID: layerID)

        policy.beginLiveStroke(layerID: layerID)
        policy.endLiveStroke(dirtyRegion: nil)
        XCTAssertEqual(plan(policy, document, layerID: layerID), .fullRedraw)
    }

    func testCancellingLiveStrokeLeavesCacheUntouched() {
        let document = Document()
        var policy = RenderCachePolicy()
        let layerID = document.activeLayerID
        policy.markClean(layerID: layerID)

        policy.beginLiveStroke(layerID: layerID)
        policy.cancelLiveStroke()

        XCTAssertNil(policy.liveStrokeLayerID)
        XCTAssertEqual(plan(policy, document, layerID: layerID), .reuseCache)
    }

    func testEndingLiveStrokeWithNoActiveStrokeIsHarmless() {
        let document = Document()
        var policy = RenderCachePolicy()
        policy.markClean(layerID: document.activeLayerID)
        policy.endLiveStroke(dirtyRegion: region)
        XCTAssertEqual(plan(policy, document, layerID: document.activeLayerID), .reuseCache)
    }

    // MARK: - No-op frames

    func testFullyCachedFrameIsANoOp() {
        let document = Document()
        var policy = RenderCachePolicy()
        for layer in document.layers { policy.markClean(layerID: layer.id) }
        XCTAssertTrue(policy.plan(for: document).isNoOp)
    }

    func testFrameWithLiveStrokeIsNotANoOp() {
        let document = Document()
        var policy = RenderCachePolicy()
        for layer in document.layers { policy.markClean(layerID: layer.id) }
        policy.beginLiveStroke(layerID: document.activeLayerID)
        XCTAssertFalse(policy.plan(for: document).isNoOp)
    }

    func testFrameWithDirtyLayerIsNotANoOp() {
        let document = Document()
        var policy = RenderCachePolicy()
        for layer in document.layers { policy.markClean(layerID: layer.id) }
        policy.invalidate(layerID: document.activeLayerID, region: region)
        XCTAssertFalse(policy.plan(for: document).isNoOp)
    }

    // MARK: - Command consequences

    func testAddStrokeWithBoundsDirtiesOnlyThatRegion() {
        let document = Document()
        var policy = RenderCachePolicy()
        let layerID = document.activeLayerID
        policy.markClean(layerID: layerID)

        policy.apply(.addStroke(layerID: layerID, stroke: .fixture()), strokeBounds: region)
        XCTAssertEqual(plan(policy, document, layerID: layerID), .incremental(region: region))
    }

    func testAddStrokeWithoutBoundsForcesFullRedraw() {
        let document = Document()
        var policy = RenderCachePolicy()
        let layerID = document.activeLayerID
        policy.markClean(layerID: layerID)

        policy.apply(.addStroke(layerID: layerID, stroke: .fixture()), strokeBounds: nil)
        XCTAssertEqual(plan(policy, document, layerID: layerID), .fullRedraw)
    }

    func testRemoveStrokeDirtiesTheVacatedRegion() {
        let document = Document()
        var policy = RenderCachePolicy()
        let layerID = document.activeLayerID
        policy.markClean(layerID: layerID)

        policy.apply(.removeStroke(layerID: layerID, strokeID: UUID()), strokeBounds: region)
        XCTAssertEqual(plan(policy, document, layerID: layerID), .incremental(region: region))
    }

    func testClearLayerForcesFullRedraw() {
        let document = Document()
        var policy = RenderCachePolicy()
        let layerID = document.activeLayerID
        policy.markClean(layerID: layerID)

        policy.apply(.clearLayer(layerID: layerID))
        XCTAssertEqual(plan(policy, document, layerID: layerID), .fullRedraw)
    }

    func testRestoreStrokesForcesFullRedraw() {
        let document = Document()
        var policy = RenderCachePolicy()
        let layerID = document.activeLayerID
        policy.markClean(layerID: layerID)

        policy.apply(.restoreStrokes(layerID: layerID, strokes: [.fixture()]))
        XCTAssertEqual(plan(policy, document, layerID: layerID), .fullRedraw)
    }

    func testOpacityChangeKeepsCacheValid() {
        let document = Document()
        var policy = RenderCachePolicy()
        let layerID = document.activeLayerID
        policy.markClean(layerID: layerID)

        // Opacity applies at composite time, so the layer's own pixels are unchanged.
        policy.apply(.setLayerOpacity(layerID: layerID, opacity: 0.5))
        XCTAssertTrue(policy.hasValidCache(for: layerID))
    }

    func testReorderRenameLockAndActiveLayerKeepCachesValid() {
        let document = Document()
        var policy = RenderCachePolicy()
        let layerID = document.activeLayerID
        policy.markClean(layerID: layerID)

        policy.apply(.moveLayer(layerID: layerID, to: 1))
        policy.apply(.renameLayer(layerID: layerID, name: "x"))
        policy.apply(.setLayerLocked(layerID: layerID, isLocked: true))
        policy.apply(.setActiveLayer(layerID: layerID))
        policy.apply(.setLayerVisibility(layerID: layerID, isVisible: false))

        XCTAssertTrue(policy.hasValidCache(for: layerID), "non-pixel commands must not invalidate")
    }

    func testAddedLayerStartsInvalid() {
        var document = Document()
        var policy = RenderCachePolicy()
        let new = Layer(name: "New")
        try? DocumentCommand.addLayer(layer: new, index: document.topIndex).apply(to: &document)
        policy.apply(.addLayer(layer: new, index: document.topIndex))
        XCTAssertEqual(plan(policy, document, layerID: new.id), .fullRedraw)
    }

    func testDeletedLayerIsForgotten() {
        let document = Document()
        var policy = RenderCachePolicy()
        let layerID = document.activeLayerID
        policy.markClean(layerID: layerID)
        policy.apply(.deleteLayer(layerID: layerID))
        XCTAssertFalse(policy.hasValidCache(for: layerID))
    }

    // MARK: - End-to-end

    func testTypicalStrokeCycleOnlyRedrawsThePaintedRegion() throws {
        var document = Document()
        var policy = RenderCachePolicy()
        let layerID = document.activeLayerID

        // Frame 1: nothing cached yet.
        XCTAssertEqual(plan(policy, document, layerID: layerID), .fullRedraw)
        policy.markClean(layerID: layerID)
        for layer in document.layers { policy.markClean(layerID: layer.id) }
        XCTAssertTrue(policy.plan(for: document).isNoOp)

        // The user drags: cache holds, live stroke drawn above it.
        policy.beginLiveStroke(layerID: layerID)
        XCTAssertEqual(plan(policy, document, layerID: layerID), .reuseCache)

        // Stroke ends and is committed with its exact painted bounds.
        let stroke = Stroke.fixture()
        let bounds = StampGeometry.bounds(of: stroke, brush: .studioPen)!
        try DocumentCommand.addStroke(layerID: layerID, stroke: stroke).apply(to: &document)
        policy.endLiveStroke(dirtyRegion: bounds)

        XCTAssertEqual(plan(policy, document, layerID: layerID), .incremental(region: bounds))

        // Renderer bakes it in; the frame settles back to fully cached.
        policy.markClean(layerID: layerID)
        XCTAssertTrue(policy.plan(for: document).isNoOp)
    }
}
