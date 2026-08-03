import Foundation

/// What a renderer must do for one layer on the next frame.
public enum LayerRenderPlan: Hashable, Sendable {
    /// The cached texture is valid — composite it as-is.
    case reuseCache
    /// Repaint the whole layer from its strokes, then cache the result.
    case fullRedraw
    /// The cache is valid but stale in one region: draw only the strokes that
    /// intersect `region` into it.
    case incremental(region: Rect)
    /// Nothing to draw — layer is hidden or fully transparent.
    case skip
}

/// One layer's contribution to a frame.
public struct LayerRenderPass: Hashable, Sendable {
    public let layerID: UUID
    public let plan: LayerRenderPlan
    /// Layer opacity to composite the result at.
    public let opacity: Double

    public init(layerID: UUID, plan: LayerRenderPlan, opacity: Double) {
        self.layerID = layerID
        self.plan = plan
        self.opacity = opacity
    }
}

/// Everything a renderer needs for one frame, bottom layer first.
public struct FramePlan: Hashable, Sendable {
    public let passes: [LayerRenderPass]
    /// The in-progress stroke, drawn live above its layer's cache and never
    /// baked into it until the stroke ends.
    public let liveStrokeLayerID: UUID?

    public init(passes: [LayerRenderPass], liveStrokeLayerID: UUID? = nil) {
        self.passes = passes
        self.liveStrokeLayerID = liveStrokeLayerID
    }

    /// True when no layer needs any GPU work.
    public var isNoOp: Bool {
        liveStrokeLayerID == nil && passes.allSatisfy {
            $0.plan == .skip || $0.plan == .reuseCache
        }
    }
}

/// Tracks which layer caches are valid and decides the work for each frame.
///
/// Pure bookkeeping: holds no textures and performs no drawing, so the whole
/// caching policy is unit-testable without a GPU. The renderer owns the actual
/// textures and simply follows the plan.
public struct RenderCachePolicy {

    private enum CacheState: Hashable {
        case invalid
        case valid
        case validButDirty(Rect)
    }

    private var states: [UUID: CacheState] = [:]
    /// Layer currently receiving a live stroke, if any.
    public private(set) var liveStrokeLayerID: UUID?

    public init() {}

    // MARK: - Queries

    public func hasValidCache(for layerID: UUID) -> Bool {
        switch states[layerID] {
        case .valid, .validButDirty: return true
        case .invalid, nil: return false
        }
    }

    public func dirtyRegion(for layerID: UUID) -> Rect? {
        if case let .validButDirty(region) = states[layerID] { return region }
        return nil
    }

    // MARK: - Invalidation

    /// Marks a layer's cache as needing a complete repaint.
    public mutating func invalidate(layerID: UUID) {
        states[layerID] = .invalid
    }

    /// Marks a sub-region of a layer's cache as stale. If the cache is already
    /// fully invalid it stays that way; a full redraw subsumes any region.
    public mutating func invalidate(layerID: UUID, region: Rect) {
        guard !region.isEmpty else { return }
        switch states[layerID] {
        case .invalid, nil:
            states[layerID] = .invalid
        case .valid:
            states[layerID] = .validButDirty(region)
        case let .validButDirty(existing):
            states[layerID] = .validButDirty(existing.union(region))
        }
    }

    /// Records that the renderer has brought a layer's cache up to date.
    public mutating func markClean(layerID: UUID) {
        states[layerID] = .valid
    }

    /// Drops bookkeeping for a deleted layer.
    public mutating func forget(layerID: UUID) {
        states.removeValue(forKey: layerID)
    }

    public mutating func invalidateAll() {
        for key in states.keys { states[key] = .invalid }
    }

    // MARK: - Live stroke

    /// Begins a live stroke. The layer's cache stays valid — the in-progress
    /// stroke is composited above it rather than drawn into it, so a growing
    /// stroke never forces the layer to be repainted.
    public mutating func beginLiveStroke(layerID: UUID) {
        liveStrokeLayerID = layerID
    }

    /// Ends the live stroke, dirtying only the region it painted so the now-
    /// committed stroke gets baked into the cache incrementally.
    public mutating func endLiveStroke(dirtyRegion: Rect?) {
        defer { liveStrokeLayerID = nil }
        guard let layerID = liveStrokeLayerID else { return }
        if let region = dirtyRegion {
            invalidate(layerID: layerID, region: region)
        } else {
            invalidate(layerID: layerID)
        }
    }

    /// Abandons the live stroke without dirtying anything.
    public mutating func cancelLiveStroke() {
        liveStrokeLayerID = nil
    }

    // MARK: - Planning

    /// Builds the frame plan for a document, bottom layer first.
    public func plan(for document: Document) -> FramePlan {
        let passes = document.layers.map { layer -> LayerRenderPass in
            LayerRenderPass(
                layerID: layer.id,
                plan: plan(for: layer),
                opacity: layer.opacity
            )
        }
        return FramePlan(passes: passes, liveStrokeLayerID: liveStrokeLayerID)
    }

    private func plan(for layer: Layer) -> LayerRenderPlan {
        // A hidden or fully transparent layer needs no work, even if dirty —
        // its cache is repaired the next time it becomes visible.
        guard layer.isVisible, layer.opacity > 0 else { return .skip }

        switch states[layer.id] {
        case .valid:
            return .reuseCache
        case let .validButDirty(region):
            return .incremental(region: region)
        case .invalid, nil:
            return .fullRedraw
        }
    }

    // MARK: - Document commands

    /// Applies the cache consequences of a document command.
    ///
    /// `strokeBounds` supplies the painted region for stroke changes; passing
    /// `nil` conservatively forces a full redraw of the affected layer.
    public mutating func apply(_ command: DocumentCommand, strokeBounds: Rect? = nil) {
        switch command {
        case let .addStroke(layerID, _), let .removeStroke(layerID, _):
            if let bounds = strokeBounds {
                invalidate(layerID: layerID, region: bounds)
            } else {
                invalidate(layerID: layerID)
            }

        case let .clearLayer(layerID), let .restoreStrokes(layerID, _),
             let .restoreElements(layerID, _):
            invalidate(layerID: layerID)

        case let .addFill(layerID, _), let .removeFill(layerID, _):
            // A flood fill's extent is not known until it is rasterized, so the
            // whole layer is conservatively redrawn.
            invalidate(layerID: layerID)

        case let .addLayer(layer, _):
            invalidate(layerID: layer.id)

        case let .deleteLayer(layerID):
            forget(layerID: layerID)

        case let .setLayerOpacity(layerID, _):
            // Opacity is applied at composite time, so the cache stays valid.
            _ = layerID

        case .moveLayer, .setLayerVisibility, .setLayerLocked, .renameLayer, .setActiveLayer,
             .setLayerClippingMask, .setSelection:
            // None of these change a layer's own pixels. Clipping and selection
            // masking are resolved at composite time, so the caches stay valid.
            break
        }
    }
}
