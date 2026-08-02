import XCTest
@testable import PaintCoachCore

final class DocumentTests: XCTestCase {

    // MARK: - Initial state

    func testNewDocumentHasBackgroundPlusOnePaintLayer() {
        let doc = Document()
        XCTAssertEqual(doc.layers.count, 2)
        XCTAssertEqual(doc.layers[0].kind, .backgroundColor)
        XCTAssertEqual(doc.layers[1].kind, .paint)
        XCTAssertEqual(doc.layers[1].name, "Layer 1")
    }

    func testActiveLayerStartsAsThePaintLayerNotTheBackground() {
        let doc = Document()
        XCTAssertEqual(doc.activeLayerID, doc.layers[1].id)
        XCTAssertEqual(doc.activeLayer.kind, .paint)
    }

    func testBackgroundLayerIsNotPaintable() {
        let doc = Document()
        XCTAssertFalse(doc.backgroundLayer.isPaintable)
    }

    func testLockedPaintLayerIsNotPaintable() {
        var layer = Layer(name: "L")
        XCTAssertTrue(layer.isPaintable)
        layer.isLocked = true
        XCTAssertFalse(layer.isPaintable)
    }

    func testDefaultCanvasIsScreenSize() {
        XCTAssertEqual(Document().canvasSize, CanvasSize.screenSize)
    }

    // MARK: - Codable round-trip

    func testDocumentSurvivesJSONRoundTrip() throws {
        var doc = Document()
        let stroke = Stroke.fixture()
        try DocumentCommand.addStroke(layerID: doc.activeLayerID, stroke: stroke).apply(to: &doc)

        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(Document.self, from: data)

        XCTAssertEqual(decoded, doc)
        XCTAssertEqual(decoded.activeLayer.strokes.first?.id, stroke.id)
    }
}

// MARK: - Fixtures

extension Stroke {
    static func fixture(id: UUID = UUID()) -> Stroke {
        Stroke(
            id: id,
            brushID: "studio-pen",
            color: .black,
            size: 0.25,
            opacity: 1,
            points: [
                StrokePoint(position: Point(10, 10), pressure: 0.4, timestamp: 0),
                StrokePoint(position: Point(20, 24), pressure: 0.8, timestamp: 0.016)
            ]
        )
    }
}
