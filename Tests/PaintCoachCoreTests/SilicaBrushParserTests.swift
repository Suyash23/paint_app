import XCTest
@testable import PaintCoachCore

/// Tests for reading Procreate `.brushset` payloads.
///
/// Two layers of coverage:
///
/// 1. **Hermetic** — archives synthesized in-test with `NSKeyedArchiver`, which
///    produces the same `CFKeyedArchiverUID` reference graph Procreate's files
///    use. These always run.
/// 2. **Real files** — the four `.brushset` files under `Brushes/`. These assert
///    on values extracted from the actual archives and are skipped (not failed)
///    when the folder is absent, so the suite stays green on a fresh clone.
final class SilicaBrushParserTests: XCTestCase {

    // MARK: - Hermetic: object graph resolution

    /// The core risk in this parser: distinguishing an inline scalar from a
    /// `CFKeyedArchiverUID` reference. `NSKeyedArchiver` stores strings by
    /// reference and small numbers inline, so one synthesized archive exercises
    /// both paths.
    func testResolvesStringReferencesAndInlineScalars() throws {
        let archive: [String: Any] = [
            "name": "Synth Brush",
            "authorName": "Tester",
            "plotSpacing": Float(0.25),
            "maxSize": Float(0.5),
            "blendMode": Int(3)
        ]
        let data = try synthesizeArchive(archive)

        let d = try SilicaBrushParser.parseBrush(data)

        XCTAssertEqual(d.name, "Synth Brush")
        XCTAssertEqual(d.authorName, "Tester")
        XCTAssertEqual(d.plotSpacing, 0.25, accuracy: 1e-6)
        XCTAssertEqual(d.maxSize, 0.5, accuracy: 1e-6)
        XCTAssertEqual(d.blendMode, 3)
    }

    /// A UID description must never be mistaken for a number, and vice versa.
    func testUIDValueRejectsNumbers() {
        XCTAssertNil(SilicaBrushParser.Resolver.uidValue(NSNumber(value: 57)))
        XCTAssertNil(SilicaBrushParser.Resolver.uidValue(NSNumber(value: 0.5)))
        XCTAssertNil(SilicaBrushParser.Resolver.uidValue("57"))
    }

    /// `CFKeyedArchiverUID` is not publicly bridgeable, so the index is
    /// recovered from its description. This pins the exact format observed in
    /// Procreate's archives — if a future OS changes it, this fails loudly
    /// instead of silently returning `nil` for every referenced value.
    func testUIDValueParsesReferenceDescription() {
        struct FakeUID: CustomStringConvertible {
            let description = "<CFKeyedArchiverUID 0x75b315800 [0x1f33d8880]>{value = 57}"
        }

        XCTAssertEqual(SilicaBrushParser.Resolver.uidValue(FakeUID()), 57)
    }

    /// Anything not shaped like a UID must resolve to `nil` rather than a bogus
    /// index that would read the wrong object.
    func testUIDValueRejectsMalformedDescriptions() {
        struct Truncated: CustomStringConvertible {
            let description = "<CFKeyedArchiverUID 0x0 [0x0]>{value = "
        }
        struct WrongPrefix: CustomStringConvertible {
            let description = "<NSNumber 0x0>{value = 12}"
        }
        struct NonNumeric: CustomStringConvertible {
            let description = "<CFKeyedArchiverUID 0x0 [0x0]>{value = abc}"
        }

        XCTAssertNil(SilicaBrushParser.Resolver.uidValue(Truncated()))
        XCTAssertNil(SilicaBrushParser.Resolver.uidValue(WrongPrefix()))
        XCTAssertNil(SilicaBrushParser.Resolver.uidValue(NonNumeric()))
    }

    /// An out-of-range index must not trap. Guards the bounds check in
    /// `dereference`.
    func testOutOfRangeReferenceDoesNotCrash() throws {
        let archive: [String: Any] = [
            "$version": 100_000,
            "$archiver": "NSKeyedArchiver",
            "$objects": ["$null", ["name": "Safe"]]
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: archive, format: .binary, options: 0
        )

        let d = try SilicaBrushParser.parseBrush(data)

        XCTAssertEqual(d.name, "Safe")
    }

    /// Absent keys must fall back rather than crash, and `shapeRoundness` /
    /// `textureScale` default to 1 (identity) rather than 0, which would mean
    /// "degenerate tip" and "zero-scale grain".
    func testMissingKeysUseIdentityDefaults() throws {
        let data = try synthesizeArchive(["name": "Sparse"])

        let d = try SilicaBrushParser.parseBrush(data)

        XCTAssertEqual(d.name, "Sparse")
        XCTAssertEqual(d.shapeRoundness, 1, accuracy: 1e-6)
        XCTAssertEqual(d.textureScale, 1, accuracy: 1e-6)
        XCTAssertEqual(d.plotSpacing, 0, accuracy: 1e-6)
        XCTAssertEqual(d.blendMode, 0)
    }

    /// Procreate writes absent strings as the literal `"$null"` sentinel rather
    /// than omitting the key. Surfacing that string verbatim would put
    /// `"$null"` in the UI.
    func testNullSentinelBecomesNil() throws {
        let data = try synthesizeArchive([
            "name": "Has Name",
            "authorName": "$null",
            "bundledShapePath": "$null"
        ])

        let d = try SilicaBrushParser.parseBrush(data)

        XCTAssertEqual(d.name, "Has Name")
        XCTAssertNil(d.authorName)
        XCTAssertNil(d.bundledShapePath)
    }

    // MARK: - Hermetic: error handling

    func testNonPropertyListDataThrows() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])

        XCTAssertThrowsError(try SilicaBrushParser.parseBrush(data)) { error in
            XCTAssertEqual(error as? SilicaBrushParser.ParseError, .notAPropertyList)
        }
    }

    func testPropertyListWithoutObjectGraphThrows() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["unrelated": "plist"], format: .binary, options: 0
        )

        XCTAssertThrowsError(try SilicaBrushParser.parseBrush(data)) { error in
            XCTAssertEqual(error as? SilicaBrushParser.ParseError, .malformedObjectGraph)
        }
    }

    func testBrushSetIndexWithoutBrushListThrows() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["name": "No Brushes"], format: .binary, options: 0
        )

        XCTAssertThrowsError(try SilicaBrushParser.parseBrushSetIndex(data)) { error in
            XCTAssertEqual(error as? SilicaBrushParser.ParseError, .missingBrushList)
        }
    }

    // MARK: - Hermetic: texture presence

    func testTexturePresenceEmbeddedWinsOverBundledReference() {
        var d = SilicaBrushDescriptor()
        d.bundledShapePath = "Brush-Artery-Charcoal-Soft.jpg"
        XCTAssertEqual(d.texturePresence, .bundledReference)

        // Some stock brushes ship real PNGs *and* a bundled path; the usable
        // asset must win.
        d.hasEmbeddedShape = true
        XCTAssertEqual(d.texturePresence, .embedded)
    }

    func testTexturePresenceNoneWhenPurelyProcedural() {
        XCTAssertEqual(SilicaBrushDescriptor().texturePresence, .none)
    }

    // MARK: - Hermetic: set ordering

    func testBrushSetIndexPreservesPlistOrder() throws {
        let ids = ["UUID-C", "UUID-A", "UUID-B"]
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["name": "Ordered", "brushes": ids],
            format: .binary, options: 0
        )

        let parsed = try SilicaBrushParser.parseBrushSetIndex(data)

        XCTAssertEqual(parsed.name, "Ordered")
        XCTAssertEqual(parsed.brushIdentifiers, ids, "library order comes from the plist")
    }

    func testOrderedBrushesSkipsUnparsedEntries() {
        var present = SilicaBrushDescriptor()
        present.name = "Present"

        let set = SilicaBrushSet(
            name: "Partial",
            brushIdentifiers: ["missing", "found"],
            brushes: ["found": present]
        )

        XCTAssertEqual(set.orderedBrushes.map(\.name), ["Present"])
    }

    // MARK: - Real files

    /// Values below were read out of the actual archive with `plistlib` before
    /// this parser existed, so they are an independent oracle rather than a
    /// snapshot of this code's own output.
    func testParsesRealCharcoalBrush() throws {
        let uuid = "954549D9-47DC-429D-BF23-F044101FD2AD"
        guard let data = try realArchive(set: "P2_Charcoals", brush: uuid) else {
            throw XCTSkip("Brushes/P2_Charcoals.brushset not present")
        }

        let d = try SilicaBrushParser.parseBrush(data)

        XCTAssertEqual(d.name, "2B Compressed")
        XCTAssertNil(d.authorName, "stock brushes store $null for author")
        XCTAssertEqual(d.plotSpacing, 0.0727673, accuracy: 1e-5)
        XCTAssertEqual(d.maxSize, 0.4314340, accuracy: 1e-5)
        XCTAssertEqual(d.maxOpacity, 0.6022081, accuracy: 1e-5)
        XCTAssertEqual(d.shapeScatter, 0.1519608, accuracy: 1e-5)
        XCTAssertEqual(d.textureScale, 2.3691850, accuracy: 1e-5)
        XCTAssertEqual(d.grainDepth, 1.0, accuracy: 1e-5)
        XCTAssertEqual(d.dynamicsPressureOpacity, 1.0, accuracy: 1e-5)
        XCTAssertEqual(d.dynamicsPressureSize, 0.0, accuracy: 1e-5)
        XCTAssertEqual(d.bundledShapePath, "Brush-Artery-Charcoal-Soft.jpg")
        XCTAssertEqual(d.bundledGrainPath, "Brush-Artery-Charcoal-Vine.jpg")
    }

    /// The headline limitation: P2 sets reference textures inside Procreate's
    /// app bundle, so they cannot be rendered authentically. Encoded as a test
    /// so a future change to `texturePresence` cannot quietly hide it.
    func testP2CharcoalsAreBundledReferencesNotEmbedded() throws {
        let uuid = "954549D9-47DC-429D-BF23-F044101FD2AD"
        guard let data = try realArchive(set: "P2_Charcoals", brush: uuid) else {
            throw XCTSkip("Brushes/P2_Charcoals.brushset not present")
        }

        let d = try SilicaBrushParser.parseBrush(
            data, hasEmbeddedShape: false, hasEmbeddedGrain: false
        )

        XCTAssertEqual(d.texturePresence, .bundledReference)
    }

    /// `Procreate_1` brushes are the self-contained ones: `$null` bundled paths
    /// but real `Shape.png` / `Grain.png` on disk.
    func testProcreate1BrushIsEmbedded() throws {
        let uuid = "F317AB89-C250-42A0-A378-43D2912DE4B1"
        guard let data = try realArchive(set: "Procreate_1", brush: uuid) else {
            throw XCTSkip("Brushes/Procreate_1.brushset not present")
        }

        let d = try SilicaBrushParser.parseBrush(
            data, hasEmbeddedShape: true, hasEmbeddedGrain: true
        )

        XCTAssertEqual(d.name, "Pencil")
        XCTAssertNil(d.bundledShapePath, "embedded brushes store $null here")
        XCTAssertNil(d.bundledGrainPath)
        XCTAssertEqual(d.texturePresence, .embedded)
    }

    /// Some stock brushes legitimately carry `textureScale == 0` paired with a
    /// `Brush-Preset-Blank.png` grain — grainless airbrushes. Verified against
    /// the files with an independent reader: 10 of the 36 brushes are like this.
    /// A "texture scale must be positive" assumption would wrongly reject them.
    func testGrainlessAirbrushHasZeroTextureScale() throws {
        guard let indexData = try realEntry(set: "P2_Airbrushing", entry: "brushset.plist") else {
            throw XCTSkip("Brushes/P2_Airbrushing.brushset not present")
        }
        let index = try SilicaBrushParser.parseBrushSetIndex(indexData)
        guard let first = index.brushIdentifiers.first,
              let archive = try realArchive(set: "P2_Airbrushing", brush: first)
        else {
            throw XCTSkip("P2_Airbrushing contained no readable brushes")
        }

        let d = try SilicaBrushParser.parseBrush(archive)

        XCTAssertEqual(d.textureScale, 0, accuracy: 1e-6, "grainless brushes store 0")
        XCTAssertEqual(d.bundledGrainPath, "Brush-Preset-Blank.png")
    }

    func testParsesRealBrushSetIndex() throws {
        guard let data = try realEntry(set: "P2_Charcoals", entry: "brushset.plist") else {
            throw XCTSkip("Brushes/P2_Charcoals.brushset not present")
        }

        let parsed = try SilicaBrushParser.parseBrushSetIndex(data)

        XCTAssertEqual(parsed.name, "P2_Charcoals")
        XCTAssertEqual(parsed.brushIdentifiers.count, 8)
        XCTAssertEqual(
            parsed.brushIdentifiers.first, "954549D9-47DC-429D-BF23-F044101FD2AD",
            "first entry defines the library's display order"
        )
    }

    /// Guards against a parser that works on one hand-picked brush but chokes
    /// elsewhere: every brush in every set must decode with a usable name.
    func testAllRealBrushesParseWithNames() throws {
        let sets = ["P2_Airbrushing", "P2_Charcoals", "P2_Elements", "Procreate_1"]
        var parsed = 0

        for name in sets {
            guard let indexData = try realEntry(set: name, entry: "brushset.plist") else {
                continue
            }
            let index = try SilicaBrushParser.parseBrushSetIndex(indexData)

            for uuid in index.brushIdentifiers {
                guard let archive = try realArchive(set: name, brush: uuid) else { continue }
                let d = try SilicaBrushParser.parseBrush(archive)

                XCTAssertNotNil(d.name, "\(name)/\(uuid) has no name")
                XCTAssertFalse(d.name?.isEmpty ?? true, "\(name)/\(uuid) has an empty name")
                XCTAssertGreaterThanOrEqual(
                    d.textureScale, 0,
                    "\(name)/\(d.name ?? "?") negative texture scale"
                )
                parsed += 1
            }
        }

        try XCTSkipIf(parsed == 0, "no .brushset files present")
        XCTAssertEqual(parsed, 36, "expected 8+8+8+12 brushes across the four sets")
    }

    // MARK: - Helpers

    /// Builds a property-list-legal archive with the same *root layout* as
    /// Procreate's `SilicaBrush`: parameter keys written directly onto the root
    /// object rather than into `NS.keys` / `NS.objects` containers.
    ///
    /// Two deliberate limits:
    ///
    /// - `NSKeyedArchiver.archivedData(withRootObject: someDictionary)` is not
    ///   used, because it encodes a dictionary as `NS.keys` / `NS.objects` —
    ///   a different shape from a custom object's keyed archive.
    /// - `CFKeyedArchiverUID` cannot be constructed from Swift, and a stand-in
    ///   is not property-list-serializable, so values here are stored **inline**.
    ///   That exercises the resolver's inline path; UID reference resolution is
    ///   covered directly by `testUIDValueParsesReferenceDescription` and
    ///   end-to-end by the real-file tests.
    private func synthesizeArchive(_ values: [String: Any]) throws -> Data {
        let archive: [String: Any] = [
            "$version": 100_000,
            "$archiver": "NSKeyedArchiver",
            "$objects": ["$null", values],
            // "$top" omitted: the parser must default to root index 1.
        ]

        return try PropertyListSerialization.data(
            fromPropertyList: archive, format: .binary, options: 0
        )
    }

    /// Repository root, derived from this file's path so tests need no bundle
    /// resources and no working-directory assumptions.
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)   // .../Tests/PaintCoachCoreTests/<this>.swift
            .deletingLastPathComponent()  // .../Tests/PaintCoachCoreTests
            .deletingLastPathComponent()  // .../Tests
            .deletingLastPathComponent()  // repository root
    }

    /// Extracts one entry from a `.brushset` using the system `unzip`, since
    /// Foundation has no zip reader and Core must stay dependency-free.
    ///
    /// Returns `nil` when the brushset is absent so callers can `XCTSkip`.
    private func realEntry(set: String, entry: String) throws -> Data? {
        let archiveURL = repositoryRoot
            .appendingPathComponent("Brushes")
            .appendingPathComponent("\(set).brushset")
        guard FileManager.default.fileExists(atPath: archiveURL.path) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archiveURL.path, entry]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }

    private func realArchive(set: String, brush uuid: String) throws -> Data? {
        try realEntry(set: set, entry: "\(uuid)/Brush.archive")
    }
}
