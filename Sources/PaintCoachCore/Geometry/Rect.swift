import Foundation

/// An axis-aligned rectangle in canvas space.
///
/// Used for dirty-region tracking: the renderer only clears and redraws the
/// area a change actually touched.
public struct Rect: Hashable, Codable, Sendable {
    public var origin: Point
    public var width: Double
    public var height: Double

    public init(origin: Point, width: Double, height: Double) {
        self.origin = origin
        self.width = max(width, 0)
        self.height = max(height, 0)
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: Point(x, y), width: width, height: height)
    }

    public static let zero = Rect(x: 0, y: 0, width: 0, height: 0)

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + width }
    public var maxY: Double { origin.y + height }
    public var center: Point { Point(minX + width / 2, minY + height / 2) }

    /// True when the rectangle covers no area.
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    /// Builds the smallest rectangle spanning two corners, in any order.
    public init(corners a: Point, _ b: Point) {
        self.init(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    /// The smallest rectangle containing all the given points.
    public init?(bounding points: [Point]) {
        guard let first = points.first else { return nil }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        self.init(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The smallest rectangle containing both inputs. An empty rectangle is
    /// treated as "no contribution" rather than as a point at the origin.
    public func union(_ other: Rect) -> Rect {
        if isEmpty { return other }
        if other.isEmpty { return self }
        return Rect(
            x: min(minX, other.minX),
            y: min(minY, other.minY),
            width: max(maxX, other.maxX) - min(minX, other.minX),
            height: max(maxY, other.maxY) - min(minY, other.minY)
        )
    }

    /// The overlapping area, or `nil` when the rectangles are disjoint.
    public func intersection(_ other: Rect) -> Rect? {
        let x = max(minX, other.minX)
        let y = max(minY, other.minY)
        let w = min(maxX, other.maxX) - x
        let h = min(maxY, other.maxY) - y
        guard w > 0, h > 0 else { return nil }
        return Rect(x: x, y: y, width: w, height: h)
    }

    public func intersects(_ other: Rect) -> Bool { intersection(other) != nil }

    public func contains(_ point: Point) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    /// Grows the rectangle by `amount` on every side. Negative values shrink it.
    public func insetBy(_ amount: Double) -> Rect {
        Rect(
            x: minX - amount,
            y: minY - amount,
            width: width + amount * 2,
            height: height + amount * 2
        )
    }

    /// Expands to whole-pixel boundaries, so a dirty region never clips a
    /// partially-covered edge pixel.
    public func integral() -> Rect {
        let x = minX.rounded(.down)
        let y = minY.rounded(.down)
        return Rect(
            x: x,
            y: y,
            width: maxX.rounded(.up) - x,
            height: maxY.rounded(.up) - y
        )
    }

    /// Clips to a canvas of the given size, or `nil` when fully outside it.
    public func clipped(to size: CanvasSize) -> Rect? {
        intersection(Rect(x: 0, y: 0, width: Double(size.width), height: Double(size.height)))
    }
}
