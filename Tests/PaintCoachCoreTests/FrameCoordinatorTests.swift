import XCTest
@testable import PaintCoachCore

final class FrameCoordinatorTests: XCTestCase {

    private var backend: MockRenderBackend!
    private var coordinator: FrameCoordinator!
    private let brushes = ["studio-pen": Brush.studioPen, "soft-pencil": Brush.softPencil]

    override func setUp() {
        super.setUp()
        backend = MockRenderBackend()
        coordinator = FrameCoordinator(backend: backend, brushes: brushes)
    }

    private func smallDocument() -> Document {
        Document(canvasSize: CanvasSize(width: 400, height: 400))
    }

    private func stroke(
        at x: Double = 100, y: Double = 100, length: Double = 100, id: UUID = UUID()
    ) -> Stroke {
        Stroke(
            id: id, brushID: "studio-pen", color: .black, size: 0.2, opacity: 1,
            points: (0..<5).map { i in
                let t = Double(i) / 4
                return StrokePoint(position: Point(x + t * length, y), pressure: 0.6, timestamp: t)
            }
        )
    }

    // MARK: - First frame

    func testFirstFrameAllocatesAndCompositesEveryLayer() throws {
        let document = smallDocument()
        XCTAssertTrue(try coordinator.render(document: document))

        // Background is a colour composite; the paint layer gets a cache.
        XCTAssertTrue(backend.calls.contains(.prepareCache(layerID: document.activeLayerID, size: document.canvasSize)))
        XCTAssertTrue(backend.calls.contains(.compositeColor(.white, opacity: 1)))
        XCTAssertTrue(backend.calls.contains(.compositeCache(layerID: document.activeLayerID, opacity: 1)))
        XCTAssertEqual(backend.calls.last, .endFrame)
    }

    func testBackgroundLayerNeverGetsACacheTexture() throws {
        let document = smallDocument()
        try coordinator.render(document: document)
        let backgroundID = document.backgroundLayer.id
        XCTAssertFalse(backend.calls.contains(.prepareCache(layerID: backgroundID, size: document.canvasSize)))
        XCTAssertFalse(backend.calls.contains { if case .compositeCache(backgroundID, _) = $0 { return true }; return false })
    }

    func testSecondFrameWithNoChangesIsANoOp() throws {
        let document = smallDocument()
        try coordinator.render(document: document)
        backend.reset()

        XCTAssertFalse(try coordinator.render(document: document))
        XCTAssertTrue(backend.calls.isEmpty, "a clean frame must submit nothing")
    }

    func testCompositesBottomUp() throws {
        var document = smallDocument()
        let second = Layer(name: "Second")
        try DocumentCommand.addLayer(layer: second, index: document.topIndex).apply(to: &document)

        try coordinator.render(document: document)
        // Bottom paint layer first, then the one above it.
        XCTAssertEqual(backend.compositeOrder, [document.layers[1].id, second.id])
    }

    // MARK: - Cache reuse

    func testCachedLayerIsNotRedrawn() throws {
        var document = smallDocument()
        try DocumentCommand.addStroke(layerID: document.activeLayerID, stroke: stroke()).apply(to: &document)
        coordinator.apply(.addStroke(layerID: document.activeLayerID, stroke: stroke()))

        try coordinator.render(document: document)
        XCTAssertGreaterThan(backend.drawCallCount, 0)

        backend.reset()
        try coordinator.render(document: document)
        XCTAssertEqual(backend.drawCallCount, 0, "an unchanged layer must not be redrawn")
    }

    func testCacheIsAllocatedOnlyOnce() throws {
        var document = smallDocument()
        try coordinator.render(document: document)
        let layerID = document.activeLayerID

        try DocumentCommand.addStroke(layerID: layerID, stroke: stroke()).apply(to: &document)
        coordinator.apply(.addStroke(layerID: layerID, stroke: stroke()))
        backend.reset()
        try coordinator.render(document: document)

        XCTAssertFalse(
            backend.calls.contains(.prepareCache(layerID: layerID, size: document.canvasSize)),
            "cache should already be allocated"
        )
    }

    // MARK: - Live stroke

    func testLiveStrokeDoesNotRedrawTheLayerCache() throws {
        var document = smallDocument()
        try DocumentCommand.addStroke(layerID: document.activeLayerID, stroke: stroke()).apply(to: &document)
        coordinator.apply(.addStroke(layerID: document.activeLayerID, stroke: stroke()))
        try coordinator.render(document: document)

        // Start dragging a new stroke.
        coordinator.beginStroke(on: document.activeLayerID)
        backend.reset()
        let live = stroke(at: 200, y: 200)
        XCTAssertTrue(try coordinator.render(document: document, liveStroke: live))

        // This is the core Option A guarantee.
        XCTAssertEqual(backend.drawCallCount, 0, "dragging must not repaint the layer")
        XCTAssertTrue(backend.calls.contains { if case .compositeLiveStroke = $0 { return true }; return false })
    }

    func testLiveStrokeIsCompositedAboveItsOwnLayerOnly() throws {
        var document = smallDocument()
        let upper = Layer(name: "Upper")
        try DocumentCommand.addLayer(layer: upper, index: document.topIndex).apply(to: &document)
        let lowerID = document.layers[1].id

        coordinator.beginStroke(on: lowerID)
        try coordinator.render(document: document, liveStroke: stroke())

        // The live stroke must appear between the lower and upper composites.
        let liveIndex = backend.index { if case .compositeLiveStroke = $0 { return true }; return false }
        let lowerIndex = backend.index { if case .compositeCache(lowerID, _) = $0 { return true }; return false }
        let upperIndex = backend.index { if case .compositeCache(upper.id, _) = $0 { return true }; return false }

        XCTAssertNotNil(liveIndex)
        XCTAssertLessThan(lowerIndex!, liveIndex!)
        XCTAssertLessThan(liveIndex!, upperIndex!)
    }

    func testFrameWithLiveStrokeIsNeverANoOp() throws {
        let document = smallDocument()
        try coordinator.render(document: document)
        coordinator.beginStroke(on: document.activeLayerID)
        backend.reset()
        XCTAssertTrue(try coordinator.render(document: document, liveStroke: stroke()))
    }

    func testCommittingStrokeDirtiesOnlyItsRegion() throws {
        var document = smallDocument()
        try coordinator.render(document: document)
        let layerID = document.activeLayerID

        coordinator.beginStroke(on: layerID)
        let mark = stroke(at: 100, y: 100)
        try DocumentCommand.addStroke(layerID: layerID, stroke: mark).apply(to: &document)
        coordinator.commitStroke(mark)

        backend.reset()
        try coordinator.render(document: document)

        // Repair must be scissored to the painted region, not the whole canvas.
        let scissors = backend.drawScissors(layerID: layerID)
        XCTAssertFalse(scissors.isEmpty)
        for scissor in scissors {
            XCTAssertNotNil(scissor, "incremental repair must be scissored")
            XCTAssertLessThan(scissor!.width, Double(document.canvasSize.width))
        }
    }

    func testCancellingStrokeLeavesCacheClean() throws {
        var document = smallDocument()
        try DocumentCommand.addStroke(layerID: document.activeLayerID, stroke: stroke()).apply(to: &document)
        coordinator.apply(.addStroke(layerID: document.activeLayerID, stroke: stroke()))
        try coordinator.render(document: document)

        coordinator.beginStroke(on: document.activeLayerID)
        coordinator.cancelStroke()
        backend.reset()

        XCTAssertFalse(try coordinator.render(document: document))
    }

    // MARK: - Incremental repair

    func testIncrementalRepairSkipsStrokesOutsideTheDirtyRegion() throws {
        var document = smallDocument()
        let layerID = document.activeLayerID

        // Two well-separated strokes.
        let far = stroke(at: 10, y: 10, length: 20)
        let near = stroke(at: 300, y: 300, length: 20)
        try DocumentCommand.addStroke(layerID: layerID, stroke: far).apply(to: &document)
        coordinator.apply(.addStroke(layerID: layerID, stroke: far))
        try coordinator.render(document: document)

        try DocumentCommand.addStroke(layerID: layerID, stroke: near).apply(to: &document)
        coordinator.apply(.addStroke(layerID: layerID, stroke: near))
        backend.reset()
        try coordinator.render(document: document)

        // Only the stroke touching the dirty region should be redrawn.
        XCTAssertEqual(backend.drawCallCount, 1, "distant strokes must be skipped")
    }

    func testOverlappingStrokesAreBothRedrawn() throws {
        var document = smallDocument()
        let layerID = document.activeLayerID
        let first = stroke(at: 100, y: 100, length: 50)
        try DocumentCommand.addStroke(layerID: layerID, stroke: first).apply(to: &document)
        coordinator.apply(.addStroke(layerID: layerID, stroke: first))
        try coordinator.render(document: document)

        // Second stroke crosses the first, so both must be repainted in order.
        let second = stroke(at: 110, y: 100, length: 50)
        try DocumentCommand.addStroke(layerID: layerID, stroke: second).apply(to: &document)
        coordinator.apply(.addStroke(layerID: layerID, stroke: second))
        backend.reset()
        try coordinator.render(document: document)

        XCTAssertEqual(backend.drawCallCount, 2, "overlapping strokes must both be redrawn")
    }

    func testIncrementalRepairClearsBeforeDrawing() throws {
        var document = smallDocument()
        let layerID = document.activeLayerID
        let mark = stroke()
        try DocumentCommand.addStroke(layerID: layerID, stroke: mark).apply(to: &document)
        coordinator.apply(.addStroke(layerID: layerID, stroke: mark))
        backend.reset()
        try coordinator.render(document: document)

        let clearIndex = backend.index { if case .clearCache = $0 { return true }; return false }
        let drawIndex = backend.index { if case .drawIntoCache = $0 { return true }; return false }
        XCTAssertNotNil(clearIndex)
        XCTAssertNotNil(drawIndex)
        XCTAssertLessThan(clearIndex!, drawIndex!, "stale pixels must be cleared before redrawing")
    }

    func testDirtyRegionIsClippedToCanvas() throws {
        var document = smallDocument()
        let layerID = document.activeLayerID
        // A stroke straddling the canvas edge.
        let edge = stroke(at: -50, y: 10, length: 100)
        try DocumentCommand.addStroke(layerID: layerID, stroke: edge).apply(to: &document)
        coordinator.apply(.addStroke(layerID: layerID, stroke: edge))
        backend.reset()
        try coordinator.render(document: document)

        for scissor in backend.drawScissors(layerID: layerID) {
            guard let scissor else { continue }
            XCTAssertGreaterThanOrEqual(scissor.minX, 0)
            XCTAssertGreaterThanOrEqual(scissor.minY, 0)
            XCTAssertLessThanOrEqual(scissor.maxX, Double(document.canvasSize.width))
            XCTAssertLessThanOrEqual(scissor.maxY, Double(document.canvasSize.height))
        }
    }

    func testStrokeEntirelyOffCanvasSubmitsNoDrawCalls() throws {
        var document = smallDocument()
        let layerID = document.activeLayerID
        try coordinator.render(document: document)

        let offscreen = stroke(at: 5000, y: 5000, length: 50)
        try DocumentCommand.addStroke(layerID: layerID, stroke: offscreen).apply(to: &document)
        coordinator.apply(.addStroke(layerID: layerID, stroke: offscreen))
        backend.reset()
        try coordinator.render(document: document)

        XCTAssertEqual(backend.drawCallCount, 0, "offscreen work should be culled")
    }

    // MARK: - Full redraw

    func testClearLayerForcesFullRedrawWithoutScissor() throws {
        var document = smallDocument()
        let layerID = document.activeLayerID
        let a = stroke(at: 50, y: 50), b = stroke(at: 200, y: 200)
        for mark in [a, b] {
            try DocumentCommand.addStroke(layerID: layerID, stroke: mark).apply(to: &document)
            coordinator.apply(.addStroke(layerID: layerID, stroke: mark))
        }
        try coordinator.render(document: document)

        // Undoing a clear restores strokes and forces a full repaint.
        coordinator.apply(.restoreStrokes(layerID: layerID, strokes: [a, b]))
        backend.reset()
        try coordinator.render(document: document)

        XCTAssertTrue(backend.calls.contains(.clearCache(layerID: layerID, region: nil)))
        for scissor in backend.drawScissors(layerID: layerID) {
            XCTAssertNil(scissor, "full redraw must not be scissored")
        }
    }

    func testFullRedrawDrawsEveryStrokeInOrder() throws {
        var document = smallDocument()
        let layerID = document.activeLayerID
        for i in 0..<4 {
            let mark = stroke(at: Double(i) * 60 + 20, y: 100, length: 30)
            try DocumentCommand.addStroke(layerID: layerID, stroke: mark).apply(to: &document)
        }
        coordinator.invalidateAll()
        try coordinator.render(document: document)
        XCTAssertEqual(backend.drawCallCount, 4)
    }

    // MARK: - Visibility

    func testHiddenLayerIsNeitherRepairedNorComposited() throws {
        var document = smallDocument()
        let layerID = document.activeLayerID
        try DocumentCommand.addStroke(layerID: layerID, stroke: stroke()).apply(to: &document)
        try DocumentCommand.setLayerVisibility(layerID: layerID, isVisible: false).apply(to: &document)
        coordinator.apply(.addStroke(layerID: layerID, stroke: stroke()))

        try coordinator.render(document: document)
        XCTAssertEqual(backend.drawCallCount, 0)
        XCTAssertFalse(backend.compositeOrder.contains(layerID))
    }

    func testLayerOpacityIsPassedToComposite() throws {
        var document = smallDocument()
        let layerID = document.activeLayerID
        try DocumentCommand.setLayerOpacity(layerID: layerID, opacity: 0.35).apply(to: &document)
        try coordinator.render(document: document)
        XCTAssertTrue(backend.calls.contains(.compositeCache(layerID: layerID, opacity: 0.35)))
    }

    func testOpacityChangeAloneDoesNotRedrawTheCache() throws {
        var document = smallDocument()
        let layerID = document.activeLayerID
        try DocumentCommand.addStroke(layerID: layerID, stroke: stroke()).apply(to: &document)
        coordinator.apply(.addStroke(layerID: layerID, stroke: stroke()))
        try coordinator.render(document: document)

        try DocumentCommand.setLayerOpacity(layerID: layerID, opacity: 0.5).apply(to: &document)
        coordinator.apply(.setLayerOpacity(layerID: layerID, opacity: 0.5))
        backend.reset()
        try coordinator.render(document: document)

        XCTAssertEqual(backend.drawCallCount, 0, "opacity applies at composite time")
    }

    // MARK: - Cache lifetime

    func testReleasingCacheFreesTheTexture() throws {
        var document = smallDocument()
        let extra = Layer(name: "Extra")
        try DocumentCommand.addLayer(layer: extra, index: document.topIndex).apply(to: &document)
        try coordinator.render(document: document)

        coordinator.releaseCache(layerID: extra.id)
        XCTAssertTrue(backend.calls.contains(.releaseCache(layerID: extra.id)))
    }

    func testReleasingUnknownCacheIsHarmless() {
        coordinator.releaseCache(layerID: UUID())
        XCTAssertTrue(backend.calls.isEmpty)
    }

    func testReleaseAllCachesForcesReallocationOnNextFrame() throws {
        let document = smallDocument()
        try coordinator.render(document: document)
        coordinator.releaseAllCaches()
        backend.reset()

        try coordinator.render(document: document)
        XCTAssertTrue(backend.calls.contains(.prepareCache(layerID: document.activeLayerID, size: document.canvasSize)))
    }

    // MARK: - Brushes

    func testUnknownBrushFallsBackInsteadOfVanishing() throws {
        var document = smallDocument()
        let layerID = document.activeLayerID
        let odd = Stroke(
            brushID: "does-not-exist", color: .black, size: 0.3, opacity: 1,
            points: (0..<4).map { StrokePoint(position: Point(Double($0) * 20 + 50, 50), pressure: 0.5) }
        )
        try DocumentCommand.addStroke(layerID: layerID, stroke: odd).apply(to: &document)
        coordinator.apply(.addStroke(layerID: layerID, stroke: odd))
        try coordinator.render(document: document)

        // Must still produce a mark rather than silently dropping the stroke.
        XCTAssertGreaterThan(backend.drawCallCount, 0)
        XCTAssertNotNil(coordinator.bounds(of: odd))
    }

    // MARK: - Error propagation

    func testBackendFailureDuringRepairPropagates() throws {
        var document = smallDocument()
        let layerID = document.activeLayerID
        try DocumentCommand.addStroke(layerID: layerID, stroke: stroke()).apply(to: &document)
        coordinator.apply(.addStroke(layerID: layerID, stroke: stroke()))
        backend.failOn = "drawIntoCache"

        XCTAssertThrowsError(try coordinator.render(document: document))
    }

    func testFailedFrameLeavesCacheDirtyForRetry() throws {
        var document = smallDocument()
        let layerID = document.activeLayerID
        try DocumentCommand.addStroke(layerID: layerID, stroke: stroke()).apply(to: &document)
        coordinator.apply(.addStroke(layerID: layerID, stroke: stroke()))

        backend.failOn = "drawIntoCache"
        XCTAssertThrowsError(try coordinator.render(document: document))

        // The layer must not have been marked clean, or the mark would be lost.
        backend.failOn = nil
        backend.reset()
        XCTAssertTrue(try coordinator.render(document: document))
        XCTAssertGreaterThan(backend.drawCallCount, 0, "failed work must be retried")
    }
}
