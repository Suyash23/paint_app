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
            CanvasRepresentable(model: model).ignoresSafeArea()
            toolbar
        }
        .overlay(alignment: .trailing) {
            if showLayers { layerPanel }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            Picker("Brush", selection: $model.brushID) {
                Text("Pen").tag(Brush.studioPen.id)
                Text("Pencil").tag(Brush.softPencil.id)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)

            ForEach(Self.palette, id: \.0) { name, swatch in
                Button {
                    model.color = swatch
                } label: {
                    Circle()
                        .fill(Color(red: swatch.r, green: swatch.g, blue: swatch.b))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle().stroke(.white.opacity(model.color == swatch ? 1 : 0.3),
                                            lineWidth: model.color == swatch ? 2 : 1)
                        )
                }
                .accessibilityLabel(name)
            }

            VStack(spacing: 2) {
                Text("Size").font(.caption2)
                Slider(value: $model.brushSize, in: 0.02...1).frame(width: 110)
            }

            VStack(spacing: 2) {
                Text("Opacity").font(.caption2)
                Slider(value: $model.brushOpacity, in: 0.05...1).frame(width: 110)
            }

            Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                .disabled(!model.canUndo)
            Button("Redo", systemImage: "arrow.uturn.forward") { model.redo() }
                .disabled(!model.canRedo)
            Button("Layers", systemImage: "square.3.layers.3d") {
                showLayers.toggle()
            }
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .padding(.top, 8)
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
