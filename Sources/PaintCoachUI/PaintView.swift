#if canImport(UIKit)
import SwiftUI
import PaintCoachCore

/// Bridges `MetalCanvasView` into SwiftUI.
///
/// UNVERIFIED: never run on a device.
public struct CanvasRepresentable: UIViewRepresentable {
    @ObservedObject var model: CanvasModel

    public init(model: CanvasModel) {
        self.model = model
    }

    public func makeUIView(context: Context) -> UIView {
        // A failure here means no Metal device; show a plain view rather than
        // crashing, so the failure is visible instead of fatal.
        guard let canvas = try? MetalCanvasView(document: model.initialDocument) else {
            let fallback = UIView()
            fallback.backgroundColor = .systemPink
            return fallback
        }
        canvas.onDocumentChange = { [weak model] document in
            model?.documentDidChange(document)
        }
        model.attach(canvas)
        return canvas
    }

    public func updateUIView(_ view: UIView, context: Context) {
        guard let canvas = view as? MetalCanvasView else { return }
        canvas.brushID = model.brushID
        canvas.color = model.color
        canvas.brushSize = model.brushSize
        canvas.brushOpacity = model.brushOpacity
    }
}

/// Observable state shared between the SwiftUI controls and the canvas view.
@MainActor
public final class CanvasModel: ObservableObject {

    @Published public var brushID: String = Brush.studioPen.id
    @Published public var color: RGBA = .black
    @Published public var brushSize: Double = 0.35
    @Published public var brushOpacity: Double = 1.0

    /// Mirrors the document so the layer list and undo buttons stay in step.
    @Published public private(set) var layers: [Layer] = []
    @Published public private(set) var activeLayerID: UUID?
    @Published public private(set) var canUndo = false
    @Published public private(set) var canRedo = false

    public let initialDocument: Document
    private weak var canvas: MetalCanvasView?

    public init(document: Document = Document()) {
        self.initialDocument = document
        self.layers = document.layers
        self.activeLayerID = document.activeLayerID
    }

    func attach(_ canvas: MetalCanvasView) {
        self.canvas = canvas
        documentDidChange(canvas.document)
    }

    func documentDidChange(_ document: Document) {
        layers = document.layers
        activeLayerID = document.activeLayerID
        canUndo = canvas?.canUndo ?? false
        canRedo = canvas?.canRedo ?? false
    }

    // MARK: - Actions

    public func undo() { canvas?.undo() }
    public func redo() { canvas?.redo() }

    public func addLayer() {
        guard let canvas else { return }
        let name = "Layer \(canvas.document.layers.count)"
        canvas.perform(.addLayer(layer: Layer(name: name), index: canvas.document.topIndex))
    }

    public func select(layerID: UUID) {
        canvas?.perform(.setActiveLayer(layerID: layerID))
    }

    public func toggleVisibility(layerID: UUID) {
        guard let layer = canvas?.document.layer(id: layerID) else { return }
        canvas?.perform(.setLayerVisibility(layerID: layerID, isVisible: !layer.isVisible))
    }

    public func deleteLayer(layerID: UUID) {
        canvas?.perform(.deleteLayer(layerID: layerID))
    }

    public func clearActiveLayer() {
        guard let id = activeLayerID else { return }
        canvas?.perform(.clearLayer(layerID: id))
    }
}

/// Minimal painting UI: canvas plus brush, colour, and layer controls.
///
/// UNVERIFIED: never run on a device.
public struct PaintView: View {
    @StateObject private var model: CanvasModel
    @State private var showLayers = false

    public init(document: Document = Document()) {
        _model = StateObject(wrappedValue: CanvasModel(document: document))
    }

    private static let palette: [(String, RGBA)] = [
        ("Black", .black),
        ("White", .white),
        ("Red", RGBA(r: 0.85, g: 0.15, b: 0.15)),
        ("Blue", RGBA(r: 0.15, g: 0.35, b: 0.85)),
        ("Green", RGBA(r: 0.15, g: 0.6, b: 0.3))
    ]

    public var body: some View {
        ZStack(alignment: .top) {
            Color(white: 0.12).ignoresSafeArea()
            // Constrain the view to the canvas aspect ratio. The compositing
            // shader draws a fullscreen quad, so the drawable must match the
            // canvas aspect or the image stretches — and touch mapping would
            // then disagree with what is drawn.
            CanvasRepresentable(model: model)
                .aspectRatio(
                    CGFloat(model.initialDocument.canvasSize.width)
                        / CGFloat(model.initialDocument.canvasSize.height),
                    contentMode: .fit
                )
                .padding(.horizontal, 8)
            
            VStack(spacing: 0) {
                topBar
                Spacer()
            }
            
            VStack {
                Spacer()
                HStack {
                    leftSidebar
                    Spacer()
                }
                Spacer()
            }
        }
        .overlay(alignment: .trailing) {
            if showLayers { layerPanel }
        }
    }

    private var topBar: some View {
        HStack {
            // Top Left Tool Group
            HStack(spacing: 24) {
                Button(action: {}) { Image(systemName: "wrench.fill") }
                Button(action: {}) { Image(systemName: "wand.and.stars") }
                Button(action: {}) { Image(systemName: "lasso") }
                Button(action: {}) { Image(systemName: "cursorarrow") }
            }
            .font(.title2)
            .foregroundColor(.white)
            
            Spacer()
            
            // Top Right Tool Group
            HStack(spacing: 24) {
                Button(action: {}) { Image(systemName: "paintbrush.fill").foregroundColor(.accentColor) }
                Button(action: {}) { Image(systemName: "hand.draw.fill") }
                Button(action: {}) { Image(systemName: "eraser.fill") }
                Button(action: { showLayers.toggle() }) { Image(systemName: "square.2.stack.3d") }
                Button(action: { /* Active Color Tap */ }) {
                    Circle()
                        .fill(Color(red: model.color.r, green: model.color.g, blue: model.color.b))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
            }
            .font(.title2)
            .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(white: 0.15).ignoresSafeArea(.all, edges: .top))
    }

    private var leftSidebar: some View {
        VStack(spacing: 24) {
            Slider(value: $model.brushSize, in: 0.02...1)
                .frame(width: 150)
                .rotationEffect(.degrees(-90))
                .frame(width: 30, height: 150)
                .tint(.gray)
            
            VStack(spacing: 24) {
                Button(action: { model.undo() }) { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.canUndo)
                Button(action: { model.redo() }) { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.canRedo)
            }
            .font(.title2)
            .foregroundColor(.white)
            
            Slider(value: $model.brushOpacity, in: 0.05...1)
                .frame(width: 150)
                .rotationEffect(.degrees(-90))
                .frame(width: 30, height: 150)
                .tint(.gray)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 12)
        .background(Color(white: 0.2).opacity(0.8).cornerRadius(20))
        .padding(.leading, 16)
    }

    private var layerPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Layers").font(.headline)
                Spacer()
                Button("Add", systemImage: "plus") { model.addLayer() }
                    .labelStyle(.iconOnly)
            }
            .padding(12)

            Divider()

            // Top layer first, matching what the user sees.
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.layers.reversed()) { layer in
                        layerRow(layer)
                        Divider()
                    }
                }
            }
        }
        .frame(width: 240)
        .background(.regularMaterial)
        .padding(.trailing, 8)
        .padding(.top, 70)
        .padding(.bottom, 40)
    }

    private func layerRow(_ layer: Layer) -> some View {
        HStack {
            Button {
                model.toggleVisibility(layerID: layer.id)
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(layer.name).font(.subheadline)
                if layer.kind == .backgroundColor {
                    Text("Background").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("\(layer.strokes.count) strokes")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if layer.id == model.activeLayerID {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
            }
        }
        .padding(10)
        .contentShape(Rectangle())
        .onTapGesture {
            // The background colour layer cannot be painted on, so it is not
            // selectable — mirrors the Core rule rather than duplicating it.
            if layer.kind == .paint { model.select(layerID: layer.id) }
        }
        .background(layer.id == model.activeLayerID ? Color.accentColor.opacity(0.12) : .clear)
    }
}
#endif
