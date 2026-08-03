import Foundation

/// Raw, loss-free representation of one brush as stored inside a Procreate
/// `.brushset` archive (`SilicaBrush`, serialized by `NSKeyedArchiver`).
///
/// This type deliberately mirrors Procreate's own vocabulary and value ranges
/// rather than this app's `Brush` model. Keeping the import loss-free in one
/// step and lossy in a separate, explicit mapping step means the mapping can be
/// revised later without re-reading the source files.
///
/// Pure value type: no Metal, no image decoding, no file-system access.
public struct SilicaBrushDescriptor: Equatable, Sendable {

    // MARK: Identity

    /// Display name, e.g. `"2B Compressed"`. `nil` when the archive stores the
    /// `$null` sentinel.
    public var name: String?
    /// Brush author, frequently `$null` in stock Procreate content.
    public var authorName: String?

    // MARK: Shape and grain sources

    /// Filename of a texture that lives inside *Procreate's own app bundle*,
    /// e.g. `"Brush-Artery-Charcoal-Soft.jpg"`.
    ///
    /// Important: the referenced image is **not** contained in the `.brushset`.
    /// A brush carrying this cannot be rendered authentically without shipping
    /// Procreate's proprietary assets. See `texturePresence`.
    public var bundledShapePath: String?
    /// As `bundledShapePath`, for the grain texture.
    public var bundledGrainPath: String?

    /// True when the brush folder carried its own `Shape.png`.
    public var hasEmbeddedShape: Bool = false
    /// True when the brush folder carried its own `Grain.png`.
    public var hasEmbeddedGrain: Bool = false

    // MARK: Stroke path

    /// Distance between stamps as a fraction of stamp size. Procreate's
    /// "Spacing" slider under Stroke Path.
    public var plotSpacing: Float = 0
    /// Per-stamp lateral scatter, 0...1.
    public var shapeScatter: Float = 0
    /// Per-stamp rotation jitter, 0...1.
    public var shapeRotation: Float = 0
    /// Tip roundness, 1 = circular.
    public var shapeRoundness: Float = 1

    // MARK: Size and opacity

    /// Upper bound of the size slider, normalized 0...1.
    public var maxSize: Float = 0
    /// Lower bound of the size slider, normalized 0...1.
    public var minSize: Float = 0
    /// Upper bound of the opacity slider, normalized 0...1.
    public var maxOpacity: Float = 0
    /// Lower bound of the opacity slider, normalized 0...1.
    public var minOpacity: Float = 0

    // MARK: Grain

    /// Grain intensity, 0...1.
    public var grainDepth: Float = 0
    /// Grain texture scale multiplier. Not normalized; values above 1 are
    /// common (e.g. 2.37).
    public var textureScale: Float = 1

    // MARK: Pressure dynamics

    /// How strongly pressure drives stamp size, 0...1.
    public var dynamicsPressureSize: Float = 0
    /// How strongly pressure drives stamp opacity, 0...1.
    public var dynamicsPressureOpacity: Float = 0

    // MARK: Compositing

    /// Procreate's blend-mode index. Retained verbatim; this app does not yet
    /// have a blend-mode model to map it onto.
    public var blendMode: Int = 0

    public init() {}

    /// Whether this brush's textures are usable without Procreate installed.
    public enum TexturePresence: Equatable, Sendable {
        /// Brush folder carried its own `Shape.png` / `Grain.png`.
        case embedded
        /// Brush points at textures inside Procreate's app bundle. Parameters
        /// import fine; the textures are unavailable.
        case bundledReference
        /// Neither embedded images nor bundled references — a purely
        /// procedural tip.
        case none
    }

    /// Classifies texture availability. Embedded images win: some stock brushes
    /// carry both a `$null` bundled path and real PNGs on disk.
    public var texturePresence: TexturePresence {
        if hasEmbeddedShape || hasEmbeddedGrain { return .embedded }
        if bundledShapePath != nil || bundledGrainPath != nil { return .bundledReference }
        return .none
    }
}

/// One parsed `.brushset`: an ordered list of brushes plus the set name.
public struct SilicaBrushSet: Equatable, Sendable {
    /// Set name from `brushset.plist`, e.g. `"P2_Charcoals"`.
    public var name: String?
    /// Brush UUIDs in the order the plist lists them. This ordering is what the
    /// brush library UI should present.
    public var brushIdentifiers: [String]
    /// Descriptors keyed by UUID. May contain fewer entries than
    /// `brushIdentifiers` if a folder was missing or unreadable.
    public var brushes: [String: SilicaBrushDescriptor]

    public init(
        name: String?,
        brushIdentifiers: [String],
        brushes: [String: SilicaBrushDescriptor]
    ) {
        self.name = name
        self.brushIdentifiers = brushIdentifiers
        self.brushes = brushes
    }

    /// Descriptors in plist order, skipping any that failed to parse.
    public var orderedBrushes: [SilicaBrushDescriptor] {
        brushIdentifiers.compactMap { brushes[$0] }
    }
}
