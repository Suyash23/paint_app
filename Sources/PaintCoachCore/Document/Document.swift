import Foundation

public enum DocumentError: Error, Equatable, Sendable {
    case layerNotFound(UUID)
    case strokeNotFound(UUID)
    case layerNotPaintable(UUID)
    case indexOutOfRange(Int)
    /// The Background Color layer is pinned at the bottom and cannot be moved or deleted.
    case backgroundLayerImmovable
    case lastPaintLayer
}

/// The whole drawing, as pure data. `layers[0]` is the bottom-most layer.
public struct Document: Equatable, Codable, Sendable {
    public var canvasSize: CanvasSize
    public internal(set) var layers: [Layer]
    public internal(set) var activeLayerID: UUID

    /// Creates a document with a pinned Background Color layer plus one empty paint layer.
    public init(canvasSize: CanvasSize = .screenSize, backgroundColor: RGBA = .white) {
        let background = Layer(
            name: "Background Color",
            kind: .backgroundColor,
            backgroundColor: backgroundColor
        )
        let first = Layer(name: "Layer 1")
        self.canvasSize = canvasSize
        self.layers = [background, first]
        self.activeLayerID = first.id
    }

    // MARK: - Lookup

    public var backgroundLayer: Layer { layers[0] }

    public var activeLayer: Layer {
        // activeLayerID is an invariant maintained by every mutation below.
        layers[index(of: activeLayerID)!]
    }

    public func layer(id: UUID) -> Layer? {
        layers.first { $0.id == id }
    }

    public func index(of id: UUID) -> Int? {
        layers.firstIndex { $0.id == id }
    }

    func requireIndex(of id: UUID) throws -> Int {
        guard let i = index(of: id) else { throw DocumentError.layerNotFound(id) }
        return i
    }

    func requirePaintableIndex(of id: UUID) throws -> Int {
        let i = try requireIndex(of: id)
        guard layers[i].isPaintable else { throw DocumentError.layerNotPaintable(id) }
        return i
    }

    /// Index of the top-most layer, used as the default insertion point for `+`.
    public var topIndex: Int { layers.count }

    // MARK: - Mutation (internal; all public change goes through DocumentCommand)

    mutating func insertLayer(_ layer: Layer, at index: Int) throws {
        // Nothing may be inserted below the pinned Background Color layer.
        guard (1...layers.count).contains(index) else { throw DocumentError.indexOutOfRange(index) }
        layers.insert(layer, at: index)
    }

    mutating func removeLayer(id: UUID) throws -> (layer: Layer, index: Int) {
        let i = try requireIndex(of: id)
        guard layers[i].kind != .backgroundColor else { throw DocumentError.backgroundLayerImmovable }
        guard layers.filter({ $0.kind == .paint }).count > 1 else { throw DocumentError.lastPaintLayer }
        let removed = layers.remove(at: i)
        if activeLayerID == id {
            activeLayerID = layers[min(i, layers.count - 1)].id
        }
        return (removed, i)
    }

    mutating func moveLayer(id: UUID, to newIndex: Int) throws -> Int {
        let i = try requireIndex(of: id)
        guard layers[i].kind != .backgroundColor else { throw DocumentError.backgroundLayerImmovable }
        guard (1..<layers.count).contains(newIndex) else { throw DocumentError.indexOutOfRange(newIndex) }
        let layer = layers.remove(at: i)
        layers.insert(layer, at: newIndex)
        return i
    }

    mutating func updateLayer(id: UUID, _ body: (inout Layer) -> Void) throws {
        let i = try requireIndex(of: id)
        body(&layers[i])
    }

    mutating func setActiveLayer(id: UUID) throws {
        _ = try requireIndex(of: id)
        activeLayerID = id
    }
}
