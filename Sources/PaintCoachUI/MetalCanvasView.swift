#if canImport(UIKit)
import UIKit
import MetalKit
import PaintCoachCore
import PaintCoachMetal

/// Hosts the Metal renderer and turns Pencil/touch input into strokes.
///
/// UNVERIFIED: no iPad was available, so none of this has run. The layers below
/// it are proven (199 unit tests, 26 on-device pixel checks), but everything
/// here — touch coordinate mapping, pressure capture, and the MTKView draw loop
/// — is unexercised.
public final class MetalCanvasView: MTKView {

    // MARK: - Configuration

    /// Called after every committed or undone stroke, for UI that mirrors state.
    public var onDocumentChange: ((Document) -> Void)?

    public var brushID: String = "studio-pen" {
        didSet { session.cancel() }
    }
    public var color: RGBA = .black
    /// Brush size as a fraction of the brush's max diameter, 0...1.
    public var brushSize: Double = 0.35
    public var brushOpacity: Double = 1.0

    // MARK: - State

    private var store: DocumentStore
    private var coordinator: FrameCoordinator!
    private var backend: MetalRenderBackend!
    private var session = StrokeSession()

    /// The touch currently drawing. Tracked so a second finger cannot hijack
    /// a stroke mid-gesture.
    private var activeTouch: UITouch?

    /// Set when input changes something the next frame must show.
    private var needsFrame = true

    public var document: Document { store.document }

    // MARK: - Init

    public init(document: Document = Document(), brushes: [String: Brush] = MetalCanvasView.defaultBrushes) throws {
        self.store = DocumentStore(document: document)
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RenderError.backendUnavailable
        }
        super.init(frame: .zero, device: device)

        self.backend = try MetalRenderBackend(device: device)
        self.coordinator = FrameCoordinator(backend: backend, brushes: brushes)

        // Hand the backend this view's drawable each frame.
        backend.frameTargetProvider = { [weak self] in
            guard let drawable = self?.currentDrawable else { return nil }
            return .drawable(drawable)
        }

        colorPixelFormat = MetalRenderBackend.colorPixelFormat
        framebufferOnly = false
        // Draw on demand rather than at a fixed rate: the cache policy already
        // reports when nothing changed, so a continuous loop would burn battery
        // redrawing identical frames.
        isPaused = true
        enableSetNeedsDisplay = true
        delegate = self

        isMultipleTouchEnabled = true
        // Pencil samples arrive far faster than touch; allow the higher rate.
        if #available(iOS 17.0, *) {
            preferredFramesPerSecond = 120
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public static let defaultBrushes: [String: Brush] = [
        Brush.studioPen.id: .studioPen,
        Brush.softPencil.id: .softPencil
    ]

    // MARK: - Coordinate mapping

    /// Converts a view-space location into canvas pixels.
    ///
    /// The canvas is fitted into the view preserving aspect ratio, so the same
    /// transform must be used for drawing and for input or marks land offset
    /// from the Pencil tip.
    private func canvasPoint(from viewPoint: CGPoint) -> Point {
        let canvas = store.document.canvasSize
        let scale = min(
            bounds.width / CGFloat(canvas.width),
            bounds.height / CGFloat(canvas.height)
        )
        guard scale > 0 else { return .zero }

        let drawnWidth = CGFloat(canvas.width) * scale
        let drawnHeight = CGFloat(canvas.height) * scale
        let originX = (bounds.width - drawnWidth) / 2
        let originY = (bounds.height - drawnHeight) / 2

        return Point(
            Double((viewPoint.x - originX) / scale),
            Double((viewPoint.y - originY) / scale)
        )
    }

    /// Builds a sample from a touch, capturing Pencil attitude when present.
    private func strokePoint(from touch: UITouch, in view: UIView) -> StrokePoint {
        let location = touch.preciseLocation(in: view)

        // Normalize force. Pencil reports maximumPossibleForce; direct touch
        // reports 0, so fall back to a neutral mid-pressure.
        let pressure: Double
        if touch.type == .pencil, touch.maximumPossibleForce > 0 {
            pressure = Double(touch.force / touch.maximumPossibleForce)
        } else {
            pressure = 0.5
        }

        return StrokePoint(
            position: canvasPoint(from: location),
            pressure: min(max(pressure, 0), 1),
            altitude: touch.type == .pencil ? Double(touch.altitudeAngle) : .pi / 2,
            azimuth: touch.type == .pencil ? Double(touch.azimuthAngle(in: view)) : 0,
            timestamp: touch.timestamp
        )
    }

    // MARK: - Touch handling

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }

        let started = session.begin(
            layer: store.document.activeLayer,
            brushID: brushID,
            color: color,
            size: brushSize,
            opacity: brushOpacity,
            at: touch.timestamp
        )
        // A locked or background layer refuses the stroke outright.
        guard started else { return }

        activeTouch = touch
        coordinator.beginStroke(on: store.document.activeLayerID)
        session.move(coalesced: [strokePoint(from: touch, in: self)])
        requestFrame()
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let active = activeTouch, touches.contains(active) else { return }

        // Coalesced touches recover samples the 60Hz callback rate would drop —
        // essential for smooth fast strokes.
        let coalesced = (event?.coalescedTouches(for: active) ?? [active])
            .map { strokePoint(from: $0, in: self) }
        // Predicted touches hide input latency; they are display-only and are
        // discarded when the stroke commits.
        let predicted = (event?.predictedTouches(for: active) ?? [])
            .map { strokePoint(from: $0, in: self) }

        session.move(coalesced: coalesced, predicted: predicted)
        requestFrame()
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let active = activeTouch, touches.contains(active) else { return }
        activeTouch = nil

        guard let result = session.end() else {
            coordinator.cancelStroke()
            requestFrame()
            return
        }
        do {
            try store.perform(result.command)
            coordinator.commitStroke(result.stroke)
            onDocumentChange?(store.document)
        } catch {
            // The document refused the stroke; drop it rather than leave the
            // cache thinking a mark was baked in.
            coordinator.cancelStroke()
        }
        requestFrame()
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let active = activeTouch, touches.contains(active) else { return }
        activeTouch = nil
        session.cancel()
        coordinator.cancelStroke()
        requestFrame()
    }

    // MARK: - Editing commands

    public func undo() {
        guard store.canUndo else { return }
        // Stroke geometry is unavailable after the fact, so repaint the layer.
        let layerID = store.document.activeLayerID
        try? store.undo()
        coordinator.invalidate(layerID: layerID)
        onDocumentChange?(store.document)
        requestFrame()
    }

    public func redo() {
        guard store.canRedo else { return }
        let layerID = store.document.activeLayerID
        try? store.redo()
        coordinator.invalidate(layerID: layerID)
        onDocumentChange?(store.document)
        requestFrame()
    }

    /// Applies a document command and keeps the render cache in step.
    public func perform(_ command: DocumentCommand) {
        do {
            try store.perform(command)
            coordinator.apply(command)
            onDocumentChange?(store.document)
            requestFrame()
        } catch {
            // Invalid edits (locked layer, last paint layer) are simply ignored.
        }
    }

    public var canUndo: Bool { store.canUndo }
    public var canRedo: Bool { store.canRedo }

    private func requestFrame() {
        needsFrame = true
        setNeedsDisplay()
    }
}

// MARK: - MTKViewDelegate

extension MetalCanvasView: MTKViewDelegate {

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Cache textures are canvas-sized, not view-sized, so they survive a
        // resize; only the frame needs redrawing.
        requestFrame()
    }

    public func draw(in view: MTKView) {
        guard needsFrame || session.isDrawing else { return }
        needsFrame = false
        do {
            try coordinator.render(document: store.document, liveStroke: session.liveStroke)
        } catch {
            // A dropped frame is recoverable: the cache stays dirty and the next
            // frame retries. Marking clean here would lose the stroke.
            needsFrame = true
        }
    }
}
#endif
