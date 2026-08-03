import Foundation

/// Parses Procreate `Brush.archive` and `brushset.plist` payloads.
///
/// Deliberately operates on `Data` rather than file paths so it stays pure and
/// unit-testable, and so the caller owns zip extraction (Foundation has no zip
/// reader). Nothing here touches Metal, image decoding, or the file system.
///
/// ## Archive shape
///
/// `Brush.archive` is a binary plist written by `NSKeyedArchiver`:
///
/// ```
/// $version  = 100000
/// $archiver = "NSKeyedArchiver"
/// $top      = { root: CFKeyedArchiverUID(1) }
/// $objects  = [ "$null", <root dict>, "Brush-Artery-...jpg", ... ]
/// ```
///
/// Values in the root dict are either inline scalars or `CFKeyedArchiverUID`
/// references into `$objects`. `NSKeyedUnarchiver` is not used: it would require
/// Procreate's `SilicaBrush` class to be present, and on non-Apple platforms it
/// is unavailable. Reading the graph directly avoids both problems.
public enum SilicaBrushParser {

    public enum ParseError: Error, Equatable {
        /// Payload was not a property list at all.
        case notAPropertyList
        /// Property list parsed but was not the expected top-level dictionary.
        case unexpectedRootType
        /// `$objects` array missing, or the root object index was out of range.
        case malformedObjectGraph
        /// `brushset.plist` lacked a usable `brushes` array.
        case missingBrushList
    }

    /// Procreate stores absent strings as the literal `"$null"` sentinel rather
    /// than omitting the key.
    static let nullSentinel = "$null"

    // MARK: - brushset.plist

    /// Reads the set name and ordered brush UUIDs from a `brushset.plist`.
    public static func parseBrushSetIndex(
        _ data: Data
    ) throws -> (name: String?, brushIdentifiers: [String]) {
        let plist = try propertyList(from: data)
        guard let dict = plist as? [String: Any] else { throw ParseError.unexpectedRootType }
        guard let ids = dict["brushes"] as? [Any] else { throw ParseError.missingBrushList }

        let identifiers = ids.compactMap { $0 as? String }
        return (cleaned(dict["name"] as? String), identifiers)
    }

    // MARK: - Brush.archive

    /// Decodes a single `Brush.archive` payload.
    ///
    /// - Parameters:
    ///   - data: Raw contents of `Brush.archive`.
    ///   - hasEmbeddedShape: Whether a sibling `Shape.png` exists. The parser
    ///     cannot know this; the caller supplies it from the archive listing.
    ///   - hasEmbeddedGrain: Whether a sibling `Grain.png` exists.
    public static func parseBrush(
        _ data: Data,
        hasEmbeddedShape: Bool = false,
        hasEmbeddedGrain: Bool = false
    ) throws -> SilicaBrushDescriptor {
        let plist = try propertyList(from: data)
        guard let archive = plist as? [String: Any] else { throw ParseError.unexpectedRootType }
        guard let objects = archive["$objects"] as? [Any], objects.count > 1 else {
            throw ParseError.malformedObjectGraph
        }
        guard let root = objects[rootIndex(in: archive)] as? [String: Any] else {
            throw ParseError.malformedObjectGraph
        }

        let resolve = Resolver(objects: objects)

        var d = SilicaBrushDescriptor()
        d.name = resolve.string(root["name"])
        d.authorName = resolve.string(root["authorName"])

        d.bundledShapePath = resolve.string(root["bundledShapePath"])
        d.bundledGrainPath = resolve.string(root["bundledGrainPath"])
        d.hasEmbeddedShape = hasEmbeddedShape
        d.hasEmbeddedGrain = hasEmbeddedGrain

        d.plotSpacing = resolve.float(root["plotSpacing"])
        d.shapeScatter = resolve.float(root["shapeScatter"])
        d.shapeRotation = resolve.float(root["shapeRotation"])
        d.shapeRoundness = resolve.float(root["shapeRoundness"], default: 1)

        d.maxSize = resolve.float(root["maxSize"])
        d.minSize = resolve.float(root["minSize"])
        d.maxOpacity = resolve.float(root["maxOpacity"])
        d.minOpacity = resolve.float(root["minOpacity"])

        d.grainDepth = resolve.float(root["grainDepth"])
        d.textureScale = resolve.float(root["textureScale"], default: 1)

        d.dynamicsPressureSize = resolve.float(root["dynamicsPressureSize"])
        d.dynamicsPressureOpacity = resolve.float(root["dynamicsPressureOpacity"])

        d.blendMode = resolve.int(root["blendMode"])

        return d
    }

    // MARK: - Internals

    private static func propertyList(from data: Data) throws -> Any {
        do {
            return try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            )
        } catch {
            throw ParseError.notAPropertyList
        }
    }

    /// `$top.root` names the root object index; it is 1 in every archive
    /// observed, but reading it is cheap and avoids hardcoding.
    private static func rootIndex(in archive: [String: Any]) -> Int {
        guard let top = archive["$top"] as? [String: Any],
              let uid = top["root"],
              let index = Resolver.uidValue(uid)
        else { return 1 }
        return index
    }

    static func cleaned(_ s: String?) -> String? {
        guard let s, s != nullSentinel else { return nil }
        return s
    }

    /// Resolves inline scalars and `CFKeyedArchiverUID` references uniformly.
    struct Resolver {
        let objects: [Any]

        /// `CFKeyedArchiverUID` is not publicly bridgeable: it is not an
        /// `NSNumber` and casting fails. Its description has the stable form
        ///
        /// ```
        /// <CFKeyedArchiverUID 0x600002d0c000 [0x1f33d8880]>{value = 57}
        /// ```
        ///
        /// so the index is recovered from the trailing `{value = N}`. Verified
        /// against all 36 archives in the four bundled brushsets. Inline
        /// scalars, by contrast, arrive as ordinary `NSNumber`s and are handled
        /// by the callers below.
        static func uidValue(_ value: Any) -> Int? {
            // An NSNumber is a real value, never a reference.
            if value is NSNumber { return nil }

            let description = String(describing: value)
            guard description.hasPrefix("<CFKeyedArchiverUID"),
                  let marker = description.range(of: "{value = "),
                  let close = description.range(
                    of: "}", range: marker.upperBound..<description.endIndex
                  )
            else { return nil }

            return Int(description[marker.upperBound..<close.lowerBound])
        }

        private func dereference(_ value: Any?) -> Any? {
            guard let value else { return nil }
            if let index = Self.uidValue(value), index >= 0, index < objects.count {
                return objects[index]
            }
            return value
        }

        func string(_ value: Any?) -> String? {
            SilicaBrushParser.cleaned(dereference(value) as? String)
        }

        func float(_ value: Any?, default fallback: Float = 0) -> Float {
            guard let resolved = dereference(value) as? NSNumber else { return fallback }
            return resolved.floatValue
        }

        func int(_ value: Any?, default fallback: Int = 0) -> Int {
            guard let resolved = dereference(value) as? NSNumber else { return fallback }
            return resolved.intValue
        }
    }
}
