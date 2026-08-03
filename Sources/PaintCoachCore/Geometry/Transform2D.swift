import Foundation

/// A 2D affine transform, row-major:
///
///     | a  c  tx |
///     | b  d  ty |
///     | 0  0   1 |
///
/// Pure value type — Core never imports CoreGraphics, so this stands in for
/// `CGAffineTransform` and can be unit-tested without a device.
public struct Transform2D: Hashable, Codable, Sendable {
    public var a, b, c, d, tx, ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d
        self.tx = tx; self.ty = ty
    }

    public static let identity = Transform2D(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public var isIdentity: Bool { self == .identity }

    // MARK: - Constructors

    public static func translation(x: Double, y: Double) -> Transform2D {
        Transform2D(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    public static func scale(x: Double, y: Double) -> Transform2D {
        Transform2D(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0)
    }

    public static func rotation(_ radians: Double) -> Transform2D {
        let cosT = cos(radians), sinT = sin(radians)
        return Transform2D(a: cosT, b: sinT, c: -sinT, d: cosT, tx: 0, ty: 0)
    }

    /// Rotation about an arbitrary pivot rather than the origin — what dragging
    /// the rotation node actually does.
    public static func rotation(_ radians: Double, about pivot: Point) -> Transform2D {
        Transform2D.translation(x: -pivot.x, y: -pivot.y)
            .concatenating(.rotation(radians))
            .concatenating(.translation(x: pivot.x, y: pivot.y))
    }

    /// Scale about an arbitrary pivot — dragging a handle keeps the opposite
    /// corner (or the centre, for uniform scaling) fixed.
    public static func scale(x: Double, y: Double, about pivot: Point) -> Transform2D {
        Transform2D.translation(x: -pivot.x, y: -pivot.y)
            .concatenating(.scale(x: x, y: y))
            .concatenating(.translation(x: pivot.x, y: pivot.y))
    }

    // MARK: - Composition

    /// `self` followed by `other`.
    public func concatenating(_ other: Transform2D) -> Transform2D {
        Transform2D(
            a: a * other.a + b * other.c,
            b: a * other.b + b * other.d,
            c: c * other.a + d * other.c,
            d: c * other.b + d * other.d,
            tx: tx * other.a + ty * other.c + other.tx,
            ty: tx * other.b + ty * other.d + other.ty
        )
    }

    public func apply(to point: Point) -> Point {
        Point(a * point.x + c * point.y + tx, b * point.x + d * point.y + ty)
    }

    /// The signed area scale factor. Zero means the transform is degenerate.
    public var determinant: Double { a * d - b * c }

    /// The inverse, or `nil` when the transform collapses the plane.
    public func inverted() -> Transform2D? {
        let det = determinant
        guard det != 0, det.isFinite else { return nil }
        return Transform2D(
            a: d / det,
            b: -b / det,
            c: -c / det,
            d: a / det,
            tx: (c * ty - d * tx) / det,
            ty: (b * tx - a * ty) / det
        )
    }

    /// The axis-aligned bounds of a transformed rectangle. All four corners are
    /// mapped, so rotation and shear grow the box correctly.
    public func apply(to rect: Rect) -> Rect {
        let corners = [
            Point(rect.minX, rect.minY), Point(rect.maxX, rect.minY),
            Point(rect.maxX, rect.maxY), Point(rect.minX, rect.maxY)
        ].map(apply(to:))
        // Four mapped corners always yield a boundable set.
        return Rect(bounding: corners) ?? .zero
    }
}
