import Foundation

/// Drives a `RenderBackend` from the pure cache policy.
///
/// All the ordering and cache-repair logic lives here, in plain Swift, so it can
/// be verified against a mock backend without a GPU. The Metal backend then only
/// has to implement primitive drawing correctly.
public final class FrameCoordinator {
    private let backend: RenderBackend
    public private(set) var policy: RenderCachePolicy
    /// Brushes available for rendering, by id.
    public var brushes: [String: Brush]
    /// Catmull-Rom subdivisions used when generating stamps.
    public var subdivisions: Int

    /// Layers with a cache texture currently allocated.
    private var allocated: Set<UUID> = []

    public init(
        backend: RenderBackend,
        brushes: [String: Brush],
        policy: RenderCachePolicy = RenderCachePolicy(),
        subdivisions: Int = 8
    ) {
        self.backend = backend
        self.brushes = brushes
        self.policy = policy
        self.subdivisions = subdivisions
    }

    // MARK: - Brush lookup

    /// Resolves a stroke's brush, falling back to a plain round brush so an
    /// unknown id degrades to a visible mark rather than silently vanishing.
    private func brush(for stroke: Stroke) -> Brush {
        brushes[stroke.brushID] ?? Brush(id: stroke.brushID, name: "Fallback", maxDiameter: 100)
    }

    private func batch(for stroke: Stroke) -> StampBatch {
        let engine = BrushEngine(brush: brush(for: stroke), subdivisions: subdivisions)
        return StampBatch(stamps: engine.stamps(for: stroke), color: stroke.color, brushID: stroke.brushID)
    }

    /// The region a stroke paints into.
    public func bounds(of stroke: Stroke) -> Rect? {
        StampGeometry.bounds(of: stroke, brush: brush(for: stroke), subdivisions: subdivisions)
    }

    // MARK: - Editing lifecycle

    public func beginStroke(on layerID: UUID) {
        policy.beginLiveStroke(layerID: layerID)
    }

    /// Commits a stroke, dirtying exactly the region it painted.
    public func commitStroke(_ stroke: Stroke) {
        policy.endLiveStroke(dirtyRegion: bounds(of: stroke))
    }

    public func cancelStroke() {
        policy.cancelLiveStroke()
    }

    /// Mirrors a document command's cache consequences, computing stroke bounds
    /// so stroke edits stay incremental instead of forcing a full repaint.
    public func apply(_ command: DocumentCommand) {
        switch command {
        case let .addStroke(layerID, stroke):
            policy.apply(command, strokeBounds: bounds(of: stroke))
            _ = layerID
        case let .removeStroke(layerID, strokeID):
            // The stroke is already gone from the document, so its bounds are
            // unavailable here; the caller supplies them via applyRemoval if known.
            _ = (layerID, strokeID)
            policy.apply(command, strokeBounds: nil)
        default:
            policy.apply(command)
        }
    }

    /// Applies a stroke removal whose painted region is known, keeping the
    /// repair incremental.
    public func applyRemoval(layerID: UUID, stroke: Stroke) {
        policy.apply(
            .removeStroke(layerID: layerID, strokeID: stroke.id),
            strokeBounds: bounds(of: stroke)
        )
    }

    public func invalidateAll() {
        policy.invalidateAll()
    }

    // MARK: - Frame rendering

    /// Renders one frame of `document`, with `liveStroke` drawn above its layer.
    ///
    /// Returns `false` when the frame was a no-op and nothing was submitted.
    @discardableResult
    public func render(document: Document, liveStroke: Stroke? = nil) throws -> Bool {
        let plan = policy.plan(for: document)

        // Skip entirely when nothing changed and no stroke is in flight.
        if plan.isNoOp && liveStroke == nil { return false }

        // Repair caches before compositing, so the frame reads only clean textures.
        for pass in plan.passes {
            guard let layer = document.layer(id: pass.layerID) else { continue }
            guard layer.kind == .paint else { continue }
            try repair(pass: pass, layer: layer, canvasSize: document.canvasSize)
        }

        // Composite bottom-up.
        try backend.beginFrame(size: document.canvasSize)
        for pass in plan.passes {
            guard pass.plan != .skip, let layer = document.layer(id: pass.layerID) else { continue }

            switch layer.kind {
            case .backgroundColor:
                try backend.compositeColor(layer.backgroundColor, opacity: pass.opacity)
            case .paint:
                try backend.compositeCache(layerID: layer.id, opacity: pass.opacity)
                // The live stroke rides above its own layer's cache.
                if let live = liveStroke, plan.liveStrokeLayerID == layer.id {
                    try backend.compositeLiveStroke(batch: batch(for: live), opacity: pass.opacity)
                }
            }
        }
        try backend.endFrame()

        // Every layer drawn this frame is now up to date. This includes the
        // background colour layer: it owns no texture, but it still needs a
        // clean state or the frame could never settle into a no-op.
        for pass in plan.passes where pass.plan != .skip {
            policy.markClean(layerID: pass.layerID)
        }
        return true
    }

    /// Brings one layer's cache texture up to date.
    private func repair(pass: LayerRenderPass, layer: Layer, canvasSize: CanvasSize) throws {
        switch pass.plan {
        case .skip, .reuseCache:
            return

        case .fullRedraw:
            try ensureCache(layerID: layer.id, size: canvasSize)
            try backend.clearCache(layerID: layer.id, region: nil)
            let target = RenderTarget(size: canvasSize, scissor: nil)
            for stroke in layer.strokes {
                try backend.drawIntoCache(layerID: layer.id, batch: batch(for: stroke), target: target)
            }

        case let .incremental(region):
            try ensureCache(layerID: layer.id, size: canvasSize)
            // Clip to whole pixels inside the canvas; an empty region means the
            // dirty area fell entirely outside the canvas and needs no work.
            guard let clipped = region.integral().clipped(to: canvasSize) else { return }
            try backend.clearCache(layerID: layer.id, region: clipped)
            let target = RenderTarget(size: canvasSize, scissor: clipped)
            // Redraw only strokes that actually touch the dirty region.
            for stroke in layer.strokes {
                guard let strokeBounds = bounds(of: stroke), strokeBounds.intersects(clipped) else { continue }
                try backend.drawIntoCache(layerID: layer.id, batch: batch(for: stroke), target: target)
            }
        }
    }

    private func ensureCache(layerID: UUID, size: CanvasSize) throws {
        guard !allocated.contains(layerID) else { return }
        try backend.prepareCache(layerID: layerID, size: size)
        allocated.insert(layerID)
    }

    /// Releases a deleted layer's cache texture.
    public func releaseCache(layerID: UUID) {
        guard allocated.remove(layerID) != nil else { return }
        backend.releaseCache(layerID: layerID)
        policy.forget(layerID: layerID)
    }

    /// Drops every cache, e.g. on canvas resize.
    public func releaseAllCaches() {
        for layerID in allocated { backend.releaseCache(layerID: layerID) }
        allocated.removeAll()
        policy.invalidateAll()
    }
}
