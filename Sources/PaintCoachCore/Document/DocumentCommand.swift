import Foundation

/// An undoable change to the document.
///
/// Undo is a command log, never a pixel snapshot. Each command knows how to apply
/// itself and how to produce the inverse command that exactly reverses it.
public enum DocumentCommand: Equatable, Sendable {
    case addStroke(layerID: UUID, stroke: Stroke)
    case removeStroke(layerID: UUID, strokeID: UUID)
    case addLayer(layer: Layer, index: Int)
    case deleteLayer(layerID: UUID)
    case moveLayer(layerID: UUID, to: Int)
    case setLayerVisibility(layerID: UUID, isVisible: Bool)
    case setLayerLocked(layerID: UUID, isLocked: Bool)
    case setLayerOpacity(layerID: UUID, opacity: Double)
    case renameLayer(layerID: UUID, name: String)
    /// Toggles Procreate's "Clipping Mask" on a paint layer.
    case setLayerClippingMask(layerID: UUID, isClippingMask: Bool)
    case setActiveLayer(layerID: UUID)
    /// 3-finger scrub: remove every stroke on a layer.
    case clearLayer(layerID: UUID)
    /// Inverse of `clearLayer` — re-appends a previously removed run of strokes.
    case restoreStrokes(layerID: UUID, strokes: [Stroke])

    /// Applies the command and returns the command that undoes it.
    @discardableResult
    func apply(to document: inout Document) throws -> DocumentCommand {
        switch self {
        case let .addStroke(layerID, stroke):
            let i = try document.requirePaintableIndex(of: layerID)
            document.layers[i].strokes.append(stroke)
            return .removeStroke(layerID: layerID, strokeID: stroke.id)

        case let .removeStroke(layerID, strokeID):
            let i = try document.requireIndex(of: layerID)
            guard let s = document.layers[i].strokes.firstIndex(where: { $0.id == strokeID }) else {
                throw DocumentError.strokeNotFound(strokeID)
            }
            let removed = document.layers[i].strokes.remove(at: s)
            return .addStroke(layerID: layerID, stroke: removed)

        case let .addLayer(layer, index):
            try document.insertLayer(layer, at: index)
            return .deleteLayer(layerID: layer.id)

        case let .deleteLayer(layerID):
            let (layer, index) = try document.removeLayer(id: layerID)
            return .addLayer(layer: layer, index: index)

        case let .moveLayer(layerID, to):
            let oldIndex = try document.moveLayer(id: layerID, to: to)
            return .moveLayer(layerID: layerID, to: oldIndex)

        case let .setLayerVisibility(layerID, isVisible):
            let i = try document.requireIndex(of: layerID)
            let previous = document.layers[i].isVisible
            document.layers[i].isVisible = isVisible
            return .setLayerVisibility(layerID: layerID, isVisible: previous)

        case let .setLayerLocked(layerID, isLocked):
            let i = try document.requireIndex(of: layerID)
            let previous = document.layers[i].isLocked
            document.layers[i].isLocked = isLocked
            return .setLayerLocked(layerID: layerID, isLocked: previous)

        case let .setLayerOpacity(layerID, opacity):
            let i = try document.requireIndex(of: layerID)
            let previous = document.layers[i].opacity
            document.layers[i].opacity = min(max(opacity, 0), 1)
            return .setLayerOpacity(layerID: layerID, opacity: previous)

        case let .renameLayer(layerID, name):
            let i = try document.requireIndex(of: layerID)
            let previous = document.layers[i].name
            document.layers[i].name = name
            return .renameLayer(layerID: layerID, name: previous)

        case let .setLayerClippingMask(layerID, isClippingMask):
            let i = try document.requireIndex(of: layerID)
            // The Background Color layer has nothing beneath it to clip to.
            guard document.layers[i].kind == .paint else {
                throw DocumentError.layerNotClippable(layerID)
            }
            let previous = document.layers[i].isClippingMask
            document.layers[i].isClippingMask = isClippingMask
            return .setLayerClippingMask(layerID: layerID, isClippingMask: previous)

        case let .setActiveLayer(layerID):
            let previous = document.activeLayerID
            try document.setActiveLayer(id: layerID)
            return .setActiveLayer(layerID: previous)

        case let .clearLayer(layerID):
            let i = try document.requirePaintableIndex(of: layerID)
            let removed = document.layers[i].strokes
            document.layers[i].strokes = []
            return .restoreStrokes(layerID: layerID, strokes: removed)

        case let .restoreStrokes(layerID, strokes):
            let i = try document.requirePaintableIndex(of: layerID)
            document.layers[i].strokes.append(contentsOf: strokes)
            return .clearLayer(layerID: layerID)
        }
    }
}

/// Document plus its undo / redo command log.
public struct DocumentStore {
    public private(set) var document: Document
    private var undoStack: [DocumentCommand] = []
    private var redoStack: [DocumentCommand] = []

    public init(document: Document = Document()) {
        self.document = document
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoDepth: Int { undoStack.count }
    public var redoDepth: Int { redoStack.count }

    /// Applies a command, pushing its inverse onto the undo stack and clearing redo.
    public mutating func perform(_ command: DocumentCommand) throws {
        let inverse = try execute(command)
        undoStack.append(inverse)
        redoStack.removeAll()
    }

    public mutating func undo() throws {
        guard let inverse = undoStack.popLast() else { return }
        let redoCommand = try execute(inverse)
        redoStack.append(redoCommand)
    }

    public mutating func redo() throws {
        guard let command = redoStack.popLast() else { return }
        let inverse = try execute(command)
        undoStack.append(inverse)
    }

    private mutating func execute(_ command: DocumentCommand) throws -> DocumentCommand {
        var working = document
        // Only commit the mutation once it has fully succeeded — a throwing
        // command must leave the document untouched.
        let inverse = try command.apply(to: &working)
        document = working
        return inverse
    }
}
