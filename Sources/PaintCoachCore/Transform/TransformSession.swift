import Foundation

/// Procreate's Transform modes (the four buttons on the transform bottom bar).
public enum TransformMode: String, Hashable, Codable, Sendable, CaseIterable {
    /// Handles scale width and height independently.
    case freeform
    /// Handles preserve the original aspect ratio.
    case uniform
    /// Corners move independently — a projective warp.
    case distort
    /// Mesh deformation.
    case warp

    /// Whether dragging a handle is constrained to the original aspect ratio.
    public var preservesAspectRatio: Bool { self == .uniform }
}

/// The eight resize handles plus the rotation node on a transform bounding box.
public enum TransformHandle: String, Hashable, Codable, Sendable, CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    case rotation

    public var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomRight, .bottomLeft: return true
        default: return false
        }
    }

    /// The handle diagonally opposite, which stays fixed while dragging.
    /// The rotation node has no opposite.
    public var opposite: TransformHandle? {
        switch self {
        case .topLeft: return .bottomRight
        case .top: return .bottom
        case .topRight: return .bottomLeft
        case .right: return .left
        case .bottomRight: return .topLeft
        case .bottom: return .top
        case .bottomLeft: return .topRight
        case .left: return .right
        case .rotation: return nil
        }
    }
}

/// A live transform of the current selection or layer.
///
/// Pure geometry: the session tracks the bounding box and accumulated transform
/// so the renderer can be handed a final matrix. No pixels are touched here.
public struct TransformSession: Equatable, Sendable {
    /// The untransformed bounds the session started from.
    public let originalBounds: Rect
    public var mode: TransformMode
    /// Transform accumulated so far, relative to `originalBounds`.
    public private(set) var transform: Transform2D
    /// Rotation snaps to multiples of this angle when snapping is enabled.
    public var rotationSnapIncrement: Double
    /// Rotation must come within this tolerance of a snap angle to be pulled in.
    public var rotationSnapTolerance: Double
    public var isSnappingEnabled: Bool

    public init(
        bounds: Rect,
        mode: TransformMode = .freeform,
        isSnappingEnabled: Bool = true,
        rotationSnapIncrement: Double = .pi / 4,
        rotationSnapTolerance: Double = .pi / 36
    ) {
        self.originalBounds = bounds
        self.mode = mode
        self.transform = .identity
        self.isSnappingEnabled = isSnappingEnabled
        self.rotationSnapIncrement = rotationSnapIncrement
        self.rotationSnapTolerance = rotationSnapTolerance
    }

    /// The axis-aligned bounds after the accumulated transform.
    public var currentBounds: Rect { transform.apply(to: originalBounds) }

    /// The four transformed corners, clockwise from the top-left of the original box.
    public var corners: [Point] {
        [
            Point(originalBounds.minX, originalBounds.minY),
            Point(originalBounds.maxX, originalBounds.minY),
            Point(originalBounds.maxX, originalBounds.maxY),
            Point(originalBounds.minX, originalBounds.maxY)
        ].map(transform.apply(to:))
    }

    // MARK: - Handle positions

    /// Where a handle currently sits, for hit-testing and drawing.
    /// The rotation node floats above the top edge.
    public func position(of handle: TransformHandle) -> Point {
        let b = originalBounds
        let local: Point
        switch handle {
        case .topLeft:     local = Point(b.minX, b.minY)
        case .top:         local = Point(b.center.x, b.minY)
        case .topRight:    local = Point(b.maxX, b.minY)
        case .right:       local = Point(b.maxX, b.center.y)
        case .bottomRight: local = Point(b.maxX, b.maxY)
        case .bottom:      local = Point(b.center.x, b.maxY)
        case .bottomLeft:  local = Point(b.minX, b.maxY)
        case .left:        local = Point(b.minX, b.center.y)
        case .rotation:    local = Point(b.center.x, b.minY - TransformSession.rotationNodeOffset)
        }
        return transform.apply(to: local)
    }

    /// Distance the rotation node sits above the top edge, in canvas units.
    public static let rotationNodeOffset: Double = 44

    /// The handle within `radius` of a point, preferring corners so they stay
    /// grabbable where they overlap an edge handle.
    public func handle(at point: Point, radius: Double) -> TransformHandle? {
        let hits = TransformHandle.allCases.filter {
            position(of: $0).distance(to: point) <= radius
        }
        return hits.first(where: { $0 == .rotation })
            ?? hits.first(where: \.isCorner)
            ?? hits.first
    }

    // MARK: - Operations

    public mutating func translate(by delta: Point) {
        transform = transform.concatenating(.translation(x: delta.x, y: delta.y))
    }

    /// Rotates about the box centre, snapping to `rotationSnapIncrement` when
    /// the angle lands within tolerance of a multiple.
    public mutating func rotate(to radians: Double) {
        let angle = isSnappingEnabled ? TransformSession.snap(
            radians,
            increment: rotationSnapIncrement,
            tolerance: rotationSnapTolerance
        ) : radians
        transform = Transform2D.rotation(angle, about: originalBounds.center)
    }

    /// Snaps `angle` to the nearest multiple of `increment` when within `tolerance`.
    public static func snap(_ angle: Double, increment: Double, tolerance: Double) -> Double {
        guard increment > 0 else { return angle }
        let nearest = (angle / increment).rounded() * increment
        return abs(angle - nearest) <= tolerance ? nearest : angle
    }

    /// Scales by dragging a handle to `point`. The opposite handle stays fixed;
    /// `.uniform` mode preserves the aspect ratio by applying the larger factor
    /// to both axes.
    ///
    /// A no-op for `.rotation`, which is not a scaling handle.
    public mutating func scale(handle: TransformHandle, to point: Point) {
        guard handle != .rotation, let anchorHandle = handle.opposite else { return }
        let anchor = position(of: anchorHandle)
        let current = position(of: handle)

        // Guard against a zero-extent axis: an edge handle shares its
        // anchor's coordinate on one axis, so that axis must not scale.
        let dxOld = current.x - anchor.x
        let dyOld = current.y - anchor.y
        let dxNew = point.x - anchor.x
        let dyNew = point.y - anchor.y

        var sx = abs(dxOld) > TransformSession.epsilon ? dxNew / dxOld : 1
        var sy = abs(dyOld) > TransformSession.epsilon ? dyNew / dyOld : 1

        if mode.preservesAspectRatio {
            let factor = max(abs(sx), abs(sy))
            sx = sx < 0 ? -factor : factor
            sy = sy < 0 ? -factor : factor
        }

        transform = transform.concatenating(.scale(x: sx, y: sy, about: anchor))
    }

    static let epsilon: Double = 1e-9

    /// Flips horizontally about the box centre.
    public mutating func flipHorizontally() {
        transform = transform.concatenating(.scale(x: -1, y: 1, about: currentBounds.center))
    }

    /// Flips vertically about the box centre.
    public mutating func flipVertically() {
        transform = transform.concatenating(.scale(x: 1, y: -1, about: currentBounds.center))
    }

    /// Discards the accumulated transform.
    public mutating func reset() {
        transform = .identity
    }
}
