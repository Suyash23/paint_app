import Foundation

/// How a new selection region combines with the existing selection.
public enum SelectionMode: String, Hashable, Codable, Sendable, CaseIterable {
    /// Discard the old selection.
    case replace
    /// Union with the old selection.
    case add
    /// Remove from the old selection.
    case subtract
    /// Keep only the overlap.
    case intersect
}

/// One region contributed to a selection, in canvas space.
///
/// Freehand and rectangle cover Procreate's Freehand and Rectangle selection
/// tools; ellipse covers Ellipse. Automatic (colour-based) selection is not
/// modelled here because it depends on rasterized pixels.
public enum SelectionRegion: Hashable, Codable, Sendable {
    case rectangle(Rect)
    case ellipse(Rect)
    /// A closed polygon. Implicitly closed — the last point joins the first.
    case polygon([Point])

    /// Whether the region contains a point.
    public func contains(_ p: Point) -> Bool {
        switch self {
        case let .rectangle(rect):
            return rect.contains(p)

        case let .ellipse(rect):
            let rx = rect.width / 2, ry = rect.height / 2
            guard rx > 0, ry > 0 else { return false }
            let nx = (p.x - rect.center.x) / rx
            let ny = (p.y - rect.center.y) / ry
            return nx * nx + ny * ny <= 1

        case let .polygon(points):
            return SelectionRegion.polygonContains(points, p)
        }
    }

    /// Axis-aligned bounds, or `nil` for an empty polygon.
    public var bounds: Rect? {
        switch self {
        case let .rectangle(rect), let .ellipse(rect): return rect
        case let .polygon(points): return Rect(bounding: points)
        }
    }

    /// Even-odd ray casting. Counts crossings of a ray heading in +x.
    static func polygonContains(_ points: [Point], _ p: Point) -> Bool {
        guard points.count >= 3 else { return false }
        var inside = false
        var j = points.count - 1
        for i in 0..<points.count {
            let a = points[i], b = points[j]
            // Does the edge straddle the horizontal line through p?
            if (a.y > p.y) != (b.y > p.y) {
                let t = (p.y - a.y) / (b.y - a.y)
                if p.x < a.x + t * (b.x - a.x) { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}

/// A selection: an ordered list of regions combined by their modes, plus
/// document-level state like feathering and inversion.
///
/// Stored as intent rather than as a pixel mask, so it stays resolution
/// independent, cheap to undo, and testable without a GPU. The renderer
/// rasterizes it into a mask buffer at draw time.
public struct Selection: Hashable, Codable, Sendable {
    /// A region together with how it combines with everything before it.
    public struct Step: Hashable, Codable, Sendable {
        public var region: SelectionRegion
        public var mode: SelectionMode

        public init(region: SelectionRegion, mode: SelectionMode = .replace) {
            self.region = region
            self.mode = mode
        }
    }

    public var steps: [Step]
    /// Inverts the final coverage. Applied after all steps.
    public var isInverted: Bool
    /// Feather radius in canvas pixels. 0 is a hard edge.
    public var featherRadius: Double

    public init(steps: [Step] = [], isInverted: Bool = false, featherRadius: Double = 0) {
        self.steps = steps
        self.isInverted = isInverted
        self.featherRadius = max(0, featherRadius)
    }

    /// A selection covering nothing — the default, meaning "paint anywhere".
    public static let none = Selection()

    /// True when no region has been added. An empty *non-inverted* selection
    /// means the whole canvas is paintable, matching Procreate: with nothing
    /// selected you can draw anywhere.
    public var isEmpty: Bool { steps.isEmpty }

    /// True when the selection actively restricts painting.
    public var isActive: Bool { !steps.isEmpty || isInverted }

    /// Whether a point is inside the selection, ignoring feathering.
    ///
    /// An empty, non-inverted selection contains everything.
    public func contains(_ p: Point) -> Bool {
        guard isActive else { return true }

        // With no regions the selection covers the whole canvas, so inverting it
        // covers nothing. Once regions exist the base is empty and each step
        // builds up coverage — otherwise a leading `.add` would select everything.
        var inside = steps.isEmpty
        for step in steps {
            let hit = step.region.contains(p)
            switch step.mode {
            case .replace:   inside = hit
            case .add:       inside = inside || hit
            case .subtract:  inside = inside && !hit
            case .intersect: inside = inside && hit
            }
        }
        return isInverted ? !inside : inside
    }

    /// Coverage at a point, 0...1 — what the renderer multiplies paint alpha by.
    ///
    /// With no feathering this is a hard 0 or 1. Feathering ramps linearly across
    /// `featherRadius`, measured from the selection edge.
    public func coverage(at p: Point) -> Double {
        guard isActive else { return 1 }
        let inside = contains(p)
        guard featherRadius > 0 else { return inside ? 1 : 0 }

        let distance = distanceToEdge(from: p)
        guard distance < featherRadius else { return inside ? 1 : 0 }

        // Ramp from 0.5 exactly on the edge to 1 (inside) or 0 (outside).
        let t = distance / featherRadius
        return inside ? 0.5 + 0.5 * t : 0.5 - 0.5 * t
    }

    /// Approximate distance from `p` to the nearest selection edge.
    ///
    /// Uses the bounds of the contributing regions, which is exact for
    /// rectangles and a close approximation elsewhere — enough for a feather ramp.
    private func distanceToEdge(from p: Point) -> Double {
        let distances = steps.compactMap { step -> Double? in
            guard let b = step.region.bounds else { return nil }
            return Selection.distanceToRectEdge(from: p, rect: b)
        }
        return distances.min() ?? .greatestFiniteMagnitude
    }

    /// Distance from a point to the boundary of a rectangle, inside or out.
    static func distanceToRectEdge(from p: Point, rect: Rect) -> Double {
        let dx = max(rect.minX - p.x, p.x - rect.maxX)
        let dy = max(rect.minY - p.y, p.y - rect.maxY)
        if dx <= 0 && dy <= 0 {
            // Inside: distance to the closest of the four edges.
            return min(
                min(p.x - rect.minX, rect.maxX - p.x),
                min(p.y - rect.minY, rect.maxY - p.y)
            )
        }
        // Outside: Euclidean distance to the nearest edge or corner.
        return Point(max(dx, 0), max(dy, 0)).length
    }

    /// Axis-aligned bounds of the selection, or `nil` when it covers everything
    /// or nothing definable (an inverted selection is unbounded).
    public var bounds: Rect? {
        guard !isInverted else { return nil }
        let boxes = steps.compactMap { step -> Rect? in
            // Subtraction can only shrink coverage, so it never extends bounds.
            step.mode == .subtract ? nil : step.region.bounds
        }
        guard !boxes.isEmpty else { return nil }
        let corners = boxes.flatMap {
            [Point($0.minX, $0.minY), Point($0.maxX, $0.maxY)]
        }
        return Rect(bounding: corners)
    }

    // MARK: - Mutation

    public mutating func add(_ region: SelectionRegion, mode: SelectionMode = .replace) {
        if mode == .replace { steps.removeAll() }
        steps.append(Step(region: region, mode: mode))
    }

    /// Clears every region and resets inversion, so painting is unrestricted again.
    public mutating func clear() {
        steps.removeAll()
        isInverted = false
    }
}
