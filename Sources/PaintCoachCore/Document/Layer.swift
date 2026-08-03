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
    public var strokes: [Stroke]

    public init(
        id: UUID = UUID(),
        name: String,
        kind: Kind = .paint,
        isVisible: Bool = true,
        isLocked: Bool = false,
        opacity: Double = 1,
        backgroundColor: RGBA = .white,
        isClippingMask: Bool = false,
        strokes: [Stroke] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.opacity = opacity
        self.backgroundColor = backgroundColor
        self.isClippingMask = isClippingMask
        self.strokes = strokes
    }

    /// A layer accepts paint only when it is a paint layer and unlocked.
    public var isPaintable: Bool { kind == .paint && !isLocked }
}
