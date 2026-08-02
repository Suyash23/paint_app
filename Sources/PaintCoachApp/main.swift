import Foundation
import PaintCoachCore
import PaintCoachMetal

/// Minimal harness that renders known documents through the real Metal backend
/// and checks the resulting pixels.
///
/// The point is to turn the Metal backend's unverified assumptions into explicit
/// pass/fail results: clip-space transform, Y flip, blend state, scissor origin,
/// and instance buffer layout all either work here or visibly do not.
///
/// Deliberately drives the same public API an app would use — DocumentStore for
/// edits, FrameCoordinator for frames — so it also exercises that surface.
@main
struct Harness {

    static var failures: [String] = []
    static var checks = 0

    static func check(_ passed: Bool, _ description: String, detail: String = "") {
        checks += 1
        if passed {
            print("  PASS  \(description)")
        } else {
            let suffix = detail.isEmpty ? "" : " — \(detail)"
            print("  FAIL  \(description)\(suffix)")
            failures.append(description + suffix)
        }
    }

    static let brushes: [String: Brush] = [
        "studio-pen": Brush.studioPen,
        "soft-pencil": Brush.softPencil,
        // Hard-edged, no dynamics, so expected geometry is exactly predictable.
        "test": Brush(
            id: "test", name: "Test", maxDiameter: 40, spacing: 0.25,
            sizeDynamics: .flat, opacityDynamics: .flat, tiltDynamics: .flat
        )
    ]

    /// A document, its render target, and the coordinator wiring them together.
    final class Scene {
        var store: DocumentStore
        let coordinator: FrameCoordinator
        let renderer: OffscreenRenderer

        init(size: CanvasSize, background: RGBA = .white) throws {
            self.store = DocumentStore(document: Document(canvasSize: size, backgroundColor: background))
            self.renderer = try OffscreenRenderer(size: size)
            self.coordinator = FrameCoordinator(backend: renderer.backend, brushes: Harness.brushes)
        }

        var document: Document { store.document }
        var activeLayerID: UUID { store.document.activeLayerID }

        /// Performs a command and mirrors its cache consequences.
        func perform(_ command: DocumentCommand) throws {
            try store.perform(command)
            coordinator.apply(command)
        }

        func addLayer(_ layer: Layer) throws {
            try perform(.addLayer(layer: layer, index: store.document.topIndex))
        }

        @discardableResult
        func render(live: Stroke? = nil) throws -> Bool {
            try coordinator.render(document: store.document, liveStroke: live)
        }

        func pixel(_ x: Int, _ y: Int) -> OffscreenRenderer.Pixel {
            renderer.pixel(x: x, y: y)
        }
    }

    /// A stroke of constant pressure between two points.
    static func stroke(
        from start: Point, to end: Point, brushID: String = "test",
        color: RGBA = .black, size: Double = 1, opacity: Double = 1
    ) -> Stroke {
        let samples = 8
        let points = (0..<samples).map { i -> StrokePoint in
            let t = Double(i) / Double(samples - 1)
            return StrokePoint(position: start.lerp(to: end, t), pressure: 0.5, timestamp: t)
        }
        return Stroke(brushID: brushID, color: color, size: size, opacity: opacity, points: points)
    }

    static func main() {
        print("Metal backend verification\n")

        // Distinguish "no GPU here" from "the backend is broken" — otherwise a
        // sandbox with no Metal access looks identical to a real bug.
        guard OffscreenRenderer.isMetalAvailable else {
            print("SKIPPED: no Metal device available in this environment.")
            print("MTLCreateSystemDefaultDevice() returned nil, so nothing could be rendered.")
            print("Run this on a machine with GPU access to verify the backend.")
            exit(3)
        }

        do {
            try runBackgroundTests()
            try runStrokeTests()
            try runGeometryTests()
            try runLayerTests()
            try runCacheTests()
        } catch {
            print("\nFATAL: \(error)")
            print("The backend could not complete a frame.")
            exit(2)
        }

        print("\n\(checks - failures.count)/\(checks) checks passed")
        if failures.isEmpty {
            print("Metal backend verified.")
        } else {
            print("\nFailures:")
            for failure in failures { print("  - \(failure)") }
            exit(1)
        }
    }

    // MARK: - Background

    static func runBackgroundTests() throws {
        print("Background layer")
        let scene = try Scene(size: CanvasSize(width: 64, height: 64), background: RGBA(r: 1, g: 0, b: 0))
        try scene.render()

        let center = scene.pixel(32, 32)
        check(center.a == 255, "background is opaque", detail: "got \(center)")
        check(center.r > 200 && center.g < 40 && center.b < 40,
              "background colour is correct", detail: "got \(center)")
        check(scene.pixel(0, 0).r > 200,
              "background fills the whole canvas", detail: "corner \(scene.pixel(0, 0))")
    }

    // MARK: - Strokes

    static func runStrokeTests() throws {
        print("\nStroke rendering")
        let size = CanvasSize(width: 128, height: 128)

        let scene = try Scene(size: size)
        let mark = stroke(from: Point(20, 64), to: Point(108, 64))
        try scene.perform(.addStroke(layerID: scene.activeLayerID, stroke: mark))
        try scene.render()

        let onStroke = scene.pixel(64, 64)
        check(onStroke.r < 100 && onStroke.g < 100 && onStroke.b < 100,
              "black stroke darkens pixels on its path", detail: "got \(onStroke)")
        check(scene.pixel(64, 10).r > 200,
              "pixels away from the stroke stay background", detail: "got \(scene.pixel(64, 10))")

        // A stroke drawn high must appear high — catches a Y flip.
        let flipScene = try Scene(size: size)
        let high = stroke(from: Point(20, 20), to: Point(108, 20))
        try flipScene.perform(.addStroke(layerID: flipScene.activeLayerID, stroke: high))
        try flipScene.render()

        check(flipScene.pixel(64, 20).r < 100,
              "stroke drawn at y=20 appears at y=20", detail: "got \(flipScene.pixel(64, 20))")
        check(flipScene.pixel(64, 108).r > 200,
              "stroke at y=20 does NOT appear at y=108 (no Y flip bug)",
              detail: "got \(flipScene.pixel(64, 108))")
    }

    // MARK: - Geometry

    static func runGeometryTests() throws {
        print("\nStroke geometry")
        let size = CanvasSize(width: 128, height: 128)

        let scene = try Scene(size: size, background: .clear)
        let mark = stroke(from: Point(40, 60), to: Point(88, 60))
        try scene.perform(.addStroke(layerID: scene.activeLayerID, stroke: mark))
        try scene.render()

        guard let bounds = scene.renderer.coverageBounds() else {
            check(false, "stroke produced visible coverage", detail: "nothing was drawn")
            return
        }
        check(true, "stroke produced visible coverage")

        let expected = StampGeometry.bounds(of: mark, brush: brushes["test"]!)!
        check(abs(bounds.minX - expected.minX) < 6,
              "coverage starts near the expected x",
              detail: "drew from \(Int(bounds.minX)), expected ~\(Int(expected.minX))")
        check(abs(bounds.maxX - expected.maxX) < 6,
              "coverage ends near the expected x",
              detail: "drew to \(Int(bounds.maxX)), expected ~\(Int(expected.maxX))")
        check(abs(bounds.center.y - 60) < 6,
              "coverage is vertically centred on the stroke",
              detail: "centre y \(Int(bounds.center.y)), expected ~60")

        let thin = try Scene(size: size, background: .clear)
        try thin.perform(.addStroke(
            layerID: thin.activeLayerID,
            stroke: stroke(from: Point(30, 64), to: Point(98, 64), size: 0.25)
        ))
        try thin.render()

        let thick = try Scene(size: size, background: .clear)
        try thick.perform(.addStroke(
            layerID: thick.activeLayerID,
            stroke: stroke(from: Point(30, 64), to: Point(98, 64), size: 1.0)
        ))
        try thick.render()

        let thinCount = thin.renderer.coveredPixelCount()
        let thickCount = thick.renderer.coveredPixelCount()
        check(thickCount > thinCount,
              "a larger brush covers more pixels",
              detail: "thick \(thickCount) vs thin \(thinCount)")
    }

    // MARK: - Layers

    static func runLayerTests() throws {
        print("\nLayer compositing")
        let size = CanvasSize(width: 64, height: 64)

        let scene = try Scene(size: size)
        let lowerID = scene.activeLayerID
        let upper = Layer(name: "Upper")
        try scene.addLayer(upper)

        let path = (Point(10, 32), Point(54, 32))
        try scene.perform(.addStroke(
            layerID: lowerID,
            stroke: stroke(from: path.0, to: path.1, color: RGBA(r: 1, g: 0, b: 0))
        ))
        try scene.perform(.addStroke(
            layerID: upper.id,
            stroke: stroke(from: path.0, to: path.1, color: RGBA(r: 0, g: 0, b: 1))
        ))
        try scene.render()

        let center = scene.pixel(32, 32)
        check(center.b > center.r, "upper layer composites above lower", detail: "got \(center)")

        // Hidden layer must not appear.
        let hidden = try Scene(size: size)
        let hiddenID = hidden.activeLayerID
        try hidden.perform(.addStroke(layerID: hiddenID, stroke: stroke(from: path.0, to: path.1)))
        try hidden.perform(.setLayerVisibility(layerID: hiddenID, isVisible: false))
        try hidden.render()
        check(hidden.pixel(32, 32).r > 200,
              "hidden layer is not drawn", detail: "got \(hidden.pixel(32, 32))")

        // Layer opacity must blend.
        let faded = try Scene(size: size)
        let fadedID = faded.activeLayerID
        try faded.perform(.addStroke(layerID: fadedID, stroke: stroke(from: path.0, to: path.1)))
        try faded.perform(.setLayerOpacity(layerID: fadedID, opacity: 0.5))
        try faded.render()
        let fadedPixel = faded.pixel(32, 32)
        check(fadedPixel.r > 80 && fadedPixel.r < 200,
              "layer opacity blends the stroke", detail: "got \(fadedPixel)")
    }

    // MARK: - Caching

    static func runCacheTests() throws {
        print("\nCache behaviour")
        let scene = try Scene(size: CanvasSize(width: 128, height: 128))
        let layerID = scene.activeLayerID

        try scene.perform(.addStroke(
            layerID: layerID, stroke: stroke(from: Point(20, 30), to: Point(60, 30))
        ))
        try scene.render()
        check(scene.pixel(40, 30).r < 100, "first stroke is drawn")

        // A distant second stroke triggers incremental repair; the first must survive.
        try scene.perform(.addStroke(
            layerID: layerID, stroke: stroke(from: Point(20, 100), to: Point(60, 100))
        ))
        try scene.render()

        check(scene.pixel(40, 100).r < 100, "second stroke is drawn")
        check(scene.pixel(40, 30).r < 100,
              "first stroke survives incremental repair of a distant region",
              detail: "got \(scene.pixel(40, 30)) — scissor origin may be wrong")

        // A live stroke must appear without being baked into the cache.
        scene.coordinator.beginStroke(on: layerID)
        let live = stroke(from: Point(20, 64), to: Point(100, 64), color: RGBA(r: 0, g: 0.6, b: 0))
        try scene.render(live: live)
        let livePixel = scene.pixel(60, 64)
        check(livePixel.g > livePixel.r && livePixel.g > livePixel.b,
              "live stroke is composited onto the frame", detail: "got \(livePixel)")

        // Cancelling must leave no trace.
        scene.coordinator.cancelStroke()
        scene.coordinator.invalidateAll()
        try scene.render()
        let afterCancel = scene.pixel(60, 64)
        check(afterCancel.r > 200 && afterCancel.g > 200,
              "cancelled live stroke leaves no trace",
              detail: "got \(afterCancel) — live stroke may have leaked into the cache")
    }
}
