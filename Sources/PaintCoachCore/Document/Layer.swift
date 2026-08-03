import Foundation

public struct Layer: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Hashable, Codable, Sendable {
        /// A normal, paintable layer.
        case paint
        /// The Background Color layer — pinned at the bottom, cannot be painted on.
        case backgroundColor
    }

    public let id: UUID
    public var name: String
    public var kind: Kind
    public var isVisible: Bool
    public var isLocked: Bool
    /// Layer opacity, 0...1.
    public var opacity: Double
    /// Only meaningful for `.backgroundColor` layers.
    public var backgroundColor: RGBA
    /// When true this layer is masked by the opaque area of the layer below it
    /// (Procreate's "Clipping Mask"). Only meaningful for `.paint` layers.
    public var isClippingMask: Bool

    /// Everything painted on this layer, in draw order (first is bottom-most).
    ///
    /// Strokes and fills share one ordered list because paint over a fill and a
    /// fill over paint are different pictures — order is part of the document.
    public var elements: [LayerElement]

    public init(
        id: UUID = UUID(),
        name: String,
        kind: Kind = .paint,
        isVisible: Bool = true,
        isLocked: Bool = false,
        opacity: Double = 1,
        backgroundColor: RGBA = .white,
        isClippingMask: Bool = false,
        elements: [LayerElement] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.opacity = opacity
        self.backgroundColor = backgroundColor
        self.isClippingMask = isClippingMask
        self.elements = elements
    }

    /// Convenience for the common stroke-only case.
    public init(
        id: UUID = UUID(),
        name: String,
        kind: Kind = .paint,
        isVisible: Bool = true,
        isLocked: Bool = false,
        opacity: Double = 1,
        backgroundColor: RGBA = .white,
        isClippingMask: Bool = false,
        strokes: [Stroke]
    ) {
        self.init(
            id: id,
            name: name,
            kind: kind,
            isVisible: isVisible,
            isLocked: isLocked,
            opacity: opacity,
            backgroundColor: backgroundColor,
            isClippingMask: isClippingMask,
            elements: strokes.map(LayerElement.stroke)
        )
    }

    /// A layer accepts paint only when it is a paint layer and unlocked.
    public var isPaintable: Bool { kind == .paint && !isLocked }

    // MARK: - Element access

    /// The strokes on this layer, in draw order.
    public var strokes: [Stroke] {
        elements.compactMap { if case let .stroke(s) = $0 { return s } else { return nil } }
    }

    /// The fills on this layer, in draw order.
    public var fills: [Fill] {
        elements.compactMap { if case let .fill(f) = $0 { return f } else { return nil } }
    }

    public var isEmpty: Bool { elements.isEmpty }
}

/// One painted item on a layer. Stored as intent, never as pixels, so undo stays
/// a command-log operation and the document re-renders at any resolution.
public enum LayerElement: Identifiable, Hashable, Codable, Sendable {
    case stroke(Stroke)
    case fill(Fill)

    public var id: UUID {
        switch self {
        case let .stroke(s): return s.id
        case let .fill(f): return f.id
        }
    }
}
