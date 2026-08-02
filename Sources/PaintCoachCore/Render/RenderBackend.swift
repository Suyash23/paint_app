import Foundation

/// A texture-space region a renderer draws into, in whole pixels.
public struct RenderTarget: Hashable, Sendable {
    public var size: CanvasSize
    /// Region to restrict drawing to, or `nil` for the whole target.
    public var scissor: Rect?

    public init(size: CanvasSize, scissor: Rect? = nil) {
        self.size = size
        self.scissor = scissor
    }
}

/// One unit of drawing work: a run of stamps in a single colour.
///
/// Colour lives here rather than on `BrushStamp` because every stamp in a stroke
/// shares it — keeping it out of the per-stamp struct avoids duplicating it
/// thousands of times per stroke.
public struct StampBatch: Hashable, Sendable {
    public var stamps: [BrushStamp]
    public var color: RGBA
    public var brushID: String

    public init(stamps: [BrushStamp], color: RGBA, brushID: String) {
        self.stamps = stamps
        self.color = color
        self.brushID = brushID
    }

    /// The region these stamps paint into, or `nil` when empty.
    public var bounds: Rect? { StampGeometry.bounds(of: stamps) }
}

/// The drawing operations a backend must provide.
///
/// Deliberately narrow and imperative: `FrameCoordinator` decides *what* to draw
/// from the pure cache policy, and the backend only has to know *how*. That keeps
/// all scheduling logic testable against a mock.
public protocol RenderBackend: AnyObject {
    /// Allocates or resizes a layer's cache texture.
    func prepareCache(layerID: UUID, size: CanvasSize) throws

    /// Releases a layer's cache texture.
    func releaseCache(layerID: UUID)

    /// Clears a region of a layer's cache to transparent.
    func clearCache(layerID: UUID, region: Rect?) throws

    /// Draws stamps into a layer's cache texture.
    func drawIntoCache(layerID: UUID, batch: StampBatch, target: RenderTarget) throws

    /// Begins compositing a frame onto the drawable.
    func beginFrame(size: CanvasSize) throws

    /// Composites a flat colour over the whole frame — the Background Color layer.
    func compositeColor(_ color: RGBA, opacity: Double) throws

    /// Composites a layer's cache texture onto the frame.
    func compositeCache(layerID: UUID, opacity: Double) throws

    /// Draws the in-progress stroke directly onto the frame, above its layer's
    /// cache and never into it.
    func compositeLiveStroke(batch: StampBatch, opacity: Double) throws

    /// Presents the finished frame.
    func endFrame() throws
}

public enum RenderError: Error, Equatable, Sendable {
    case backendUnavailable
    case cacheAllocationFailed(UUID)
    case noCacheForLayer(UUID)
    case frameAlreadyInProgress
    case noFrameInProgress
}
