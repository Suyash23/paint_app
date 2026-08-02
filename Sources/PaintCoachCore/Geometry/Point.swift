import Foundation

/// A 2D point in canvas space. Pure value type — Core never imports CoreGraphics/UIKit/Metal.
public struct Point: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point(0, 0)

    public static func + (a: Point, b: Point) -> Point { Point(a.x + b.x, a.y + b.y) }
    public static func - (a: Point, b: Point) -> Point { Point(a.x - b.x, a.y - b.y) }
    public static func * (p: Point, s: Double) -> Point { Point(p.x * s, p.y * s) }

    public var length: Double { (x * x + y * y).squareRoot() }

    public func distance(to other: Point) -> Double { (other - self).length }

    /// Linear interpolation from `self` to `other`, `t` in 0...1.
    public func lerp(to other: Point, _ t: Double) -> Point {
        Point(x + (other.x - x) * t, y + (other.y - y) * t)
    }
}

/// Canvas dimensions in pixels.
public struct CanvasSize: Hashable, Codable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Procreate's "Screen Size" preset for a 12.9" iPad Pro, at 2x.
    public static let screenSize = CanvasSize(width: 2732, height: 2048)
}
