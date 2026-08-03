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
    @Published public var color: RGBA = RGBA(r: 1.0, g: 0.58, b: 0.0)
    @Published public var brushSize: Double = 0.35
    @Published public var brushOpacity: Double = 1.0

    /// Which tool the right side of the top bar has active.
    @Published public var tool: PCTool = .brush
    /// Which brush set the library's left column has selected.
    @Published public var selectedSet: String = "Pencils"

    /// Mirrors the document so the layer list and undo buttons stay in step.
    @Published public private(set) var layers: [Layer] = []
    @Published public private(set) var activeLayerID: UUID?
    @Published public private(set) var canUndo = false
    @Published public private(set) var canRedo = false

    public let initialDocument: Document
    private weak var canvas: MetalCanvasView?

    /// Brushes available to the library, keyed the same way the canvas keys them.
    public let brushes: [Brush]

    public init(document: Document = Document()) {
        self.initialDocument = document
        self.layers = document.layers
        self.activeLayerID = document.activeLayerID
        self.brushes = MetalCanvasView.defaultBrushes
            .values
            .sorted { $0.name < $1.name }
    }

    /// The right-hand column of the library. Every shipped brush is listed, since
    /// the stock Procreate set names are cosmetic until real sets exist.
    public var brushesInSelectedSet: [Brush] { brushes }

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

    // MARK: - Layer options

    /// Whether a layer may be deleted. The Background Color layer is pinned and
    /// the document must keep at least one paint layer.
    public func canDelete(layerID: UUID) -> Bool {
        guard let layer = canvas?.document.layer(id: layerID), layer.kind == .paint else {
            return false
        }
        return layers.filter { $0.kind == .paint }.count > 1
    }

    public func rename(layerID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty name would render as a blank row, so keep the old one.
        guard !trimmed.isEmpty else { return }
        canvas?.perform(.renameLayer(layerID: layerID, name: trimmed))
    }

    public func toggleLocked(layerID: UUID) {
        guard let layer = canvas?.document.layer(id: layerID) else { return }
        canvas?.perform(.setLayerLocked(layerID: layerID, isLocked: !layer.isLocked))
    }

    public func setOpacity(layerID: UUID, opacity: Double) {
        canvas?.perform(.setLayerOpacity(layerID: layerID, opacity: opacity))
    }

    public func toggleClippingMask(layerID: UUID) {
        guard let layer = canvas?.document.layer(id: layerID) else { return }
        canvas?.perform(
            .setLayerClippingMask(layerID: layerID, isClippingMask: !layer.isClippingMask)
        )
    }

    /// Inserts a copy directly above the source layer and selects it, which is
    /// what Procreate does after Duplicate.
    public func duplicate(layerID: UUID) {
        guard let canvas, let source = canvas.document.layer(id: layerID),
              let index = canvas.document.index(of: layerID) else { return }

        let copy = source.duplicated()
        canvas.perform(.addLayer(layer: copy, index: index + 1))
        canvas.perform(.setActiveLayer(layerID: copy.id))
    }

    /// Moves a layer to a new slot in the stack, expressed in the panel's
    /// top-first ordering.
    public func moveLayer(from source: Int, to destination: Int) {
        guard let canvas else { return }
        let count = canvas.document.layers.count
        // The panel lists top-first; the document stores bottom-first.
        let fromIndex = count - 1 - source
        let toIndex = count - 1 - destination
        guard fromIndex != toIndex, canvas.document.layers.indices.contains(fromIndex) else { return }
        let layerID = canvas.document.layers[fromIndex].id
        canvas.perform(.moveLayer(layerID: layerID, to: toIndex))
    }
}

/// Procreate-style painting UI, laid out to match the reference screenshots.
///
/// UNVERIFIED: never run on a device.
public struct PaintView: View {
    @StateObject private var model: CanvasModel
    @State private var panel: PCPanel = .none
    @State private var selectionMode = 0
    @State private var transformMode = 2

    public init(document: Document = Document()) {
        _model = StateObject(wrappedValue: CanvasModel(document: document))
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            PCGridBackdrop()

            canvasLayer

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .bottom)

            sidebar

            panelLayer

            bottomBarLayer
        }
        .statusBarHidden()
        // Tapping empty chrome dismisses whichever panel is open.
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { panel = .none }
        )
    }

    // MARK: - Canvas

    /// The canvas keeps its aspect ratio and sits below the top bar, leaving the
    /// grid visible around it exactly as the screenshots show.
    private var canvasLayer: some View {
        let size = model.initialDocument.canvasSize
        return CanvasRepresentable(model: model)
            .aspectRatio(CGFloat(size.width) / CGFloat(size.height), contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.top, PC.topBarHeight)
            .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 0) {
            Text("Gallery")
                .font(.system(size: PC.galleryFont))
                .foregroundStyle(.white)
                .padding(.trailing, 16)

            HStack(spacing: 9) {
                PCCircleButton(symbol: PC.iconActions, isActive: panel == .actions) {
                    toggle(.actions)
                }
                PCCircleButton(symbol: PC.iconAdjust, isActive: panel == .adjustments) {
                    toggle(.adjustments)
                }
                PCCircleButton(symbol: PC.iconSelect, isActive: panel == .selection) {
                    toggle(.selection)
                }
                PCCircleButton(symbol: PC.iconTransform, isActive: panel == .transform) {
                    toggle(.transform)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                PCBarIcon(symbol: PC.iconBrush, isActive: model.tool == .brush) {
                    // Tapping the active tool opens its library, as in Procreate.
                    if model.tool == .brush { toggle(.brushLibrary) } else { model.tool = .brush }
                }
                PCBarIcon(symbol: PC.iconSmudge, isActive: model.tool == .smudge) {
                    if model.tool == .smudge { toggle(.brushLibrary) } else { model.tool = .smudge }
                }
                PCBarIcon(symbol: PC.iconEraser, isActive: model.tool == .eraser) {
                    if model.tool == .eraser { toggle(.brushLibrary) } else { model.tool = .eraser }
                }
                PCBarIcon(symbol: PC.iconLayers, isActive: panel == .layers) {
                    toggle(.layers)
                }

                Button { toggle(.color) } label: {
                    Circle()
                        .fill(Color(
                            red: model.color.r,
                            green: model.color.g,
                            blue: model.color.b
                        ))
                        .frame(width: PC.colorWell, height: PC.colorWell)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
                .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: PC.topBarHeight)
        .background(PC.topBar)
    }

    // MARK: - Left sidebar

    /// Size slider, square brush-settings button, opacity slider, then undo/redo.
    private var sidebar: some View {
        VStack(spacing: 0) {
            PCVerticalSlider(value: $model.brushSize, range: 0.02...1)

            Button(action: {}) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color(white: 0.85), lineWidth: 1.6)
                    .frame(width: 17, height: 17)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 17)

            PCVerticalSlider(value: $model.brushOpacity, range: 0.02...1)

            Button { model.undo() } label: {
                Image(systemName: PC.iconUndo)
                    .font(.system(size: 15))
                    .foregroundStyle(model.canUndo ? PC.icon : PC.iconDim)
            }
            .buttonStyle(.plain)
            .disabled(!model.canUndo)
            .padding(.top, 26)

            Button { model.redo() } label: {
                Image(systemName: PC.iconRedo)
                    .font(.system(size: 15))
                    .foregroundStyle(model.canRedo ? PC.icon : PC.iconDim)
            }
            .buttonStyle(.plain)
            .padding(.top, 17)
        }
        .padding(.vertical, 12)
        .frame(width: PC.sidebarWidth)
        .background(
            RoundedRectangle(cornerRadius: PC.sidebarCorner, style: .continuous)
                .fill(PC.sidebar)
        )
        // Vertically centred, flush to the left edge.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Panels

    @ViewBuilder
    private var panelLayer: some View {
        switch panel {
        case .actions:
            PCActionsPanel()
                .padding(.leading, 52)
                .padding(.top, PC.topBarHeight + 4)
        case .adjustments:
            PCAdjustmentsPanel()
                .padding(.leading, 52)
                .padding(.top, PC.topBarHeight + 4)
        case .brushLibrary:
            PCBrushLibrary(model: model)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 88)
                .padding(.top, PC.topBarHeight + 4)
        case .layers:
            PCLayersPanel(model: model)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 16)
                .padding(.top, PC.topBarHeight + 4)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var bottomBarLayer: some View {
        if panel == .selection {
            PCBottomBar(
                modes: [
                    ("circle.dashed", "Automatic"), ("scribble", "Freehand"),
                    ("rectangle", "Rectangle"), ("circle.lefthalf.filled", "Ellipse")
                ],
                selectedMode: $selectionMode,
                actions: [
                    ("plus.rectangle.fill", "Add", true),
                    ("minus.rectangle", "Remove", false),
                    ("square.righthalf.filled", "Invert", false),
                    ("circle.righthalf.filled", "Copy & Paste", false),
                    ("circle.dotted", "Feather", false),
                    ("heart.fill", "Save & Load", false),
                    ("drop.fill", "Color Fill", true),
                    ("paintbrush.pointed", "Clear", false)
                ]
            )
            .frame(width: 600)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 12)
        } else if panel == .transform {
            PCBottomBar(
                modes: [
                    ("rectangle.split.2x1", "Freeform"), ("rectangle", "Uniform"),
                    ("skew", "Distort"), ("circle.lefthalf.filled", "Warp")
                ],
                selectedMode: $transformMode,
                actions: [
                    ("bolt.fill", "Snapping", false),
                    ("arrow.left.and.right", "Flip Horizontal", false),
                    ("arrow.up.and.down", "Flip Vertical", false),
                    ("arrow.clockwise", "Rotate 45°", false),
                    ("arrow.up.left.and.arrow.down.right", "Fit to Canvas", false),
                    ("circle.grid.3x3.fill", "Bicubic", false),
                    ("arrow.2.squarepath", "Reset", false)
                ]
            )
            .frame(width: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 12)
        }
    }

    private func toggle(_ target: PCPanel) {
        panel = (panel == target) ? .none : target
    }
}
#endif
