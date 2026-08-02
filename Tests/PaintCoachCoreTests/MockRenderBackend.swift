import Foundation
@testable import PaintCoachCore

/// Records backend calls instead of drawing, so frame scheduling can be verified
/// exactly — call order included — with no GPU involved.
final class MockRenderBackend: RenderBackend {

    enum Call: Equatable {
        case prepareCache(layerID: UUID, size: CanvasSize)
        case releaseCache(layerID: UUID)
        case clearCache(layerID: UUID, region: Rect?)
        case drawIntoCache(layerID: UUID, stampCount: Int, scissor: Rect?)
        case beginFrame(size: CanvasSize)
        case compositeColor(RGBA, opacity: Double)
        case compositeCache(layerID: UUID, opacity: Double)
        case compositeLiveStroke(stampCount: Int, opacity: Double)
        case endFrame
    }

    var calls: [Call] = []
    /// Set to throw from the next call to the named operation.
    var failOn: String?

    func reset() { calls.removeAll() }

    private func check(_ name: String) throws {
        if failOn == name { throw RenderError.backendUnavailable }
    }

    func prepareCache(layerID: UUID, size: CanvasSize) throws {
        try check("prepareCache")
        calls.append(.prepareCache(layerID: layerID, size: size))
    }

    func releaseCache(layerID: UUID) {
        calls.append(.releaseCache(layerID: layerID))
    }

    func clearCache(layerID: UUID, region: Rect?) throws {
        try check("clearCache")
        calls.append(.clearCache(layerID: layerID, region: region))
    }

    func drawIntoCache(layerID: UUID, batch: StampBatch, target: RenderTarget) throws {
        try check("drawIntoCache")
        calls.append(.drawIntoCache(layerID: layerID, stampCount: batch.stamps.count, scissor: target.scissor))
    }

    func beginFrame(size: CanvasSize) throws {
        try check("beginFrame")
        calls.append(.beginFrame(size: size))
    }

    func compositeColor(_ color: RGBA, opacity: Double) throws {
        try check("compositeColor")
        calls.append(.compositeColor(color, opacity: opacity))
    }

    func compositeCache(layerID: UUID, opacity: Double) throws {
        try check("compositeCache")
        calls.append(.compositeCache(layerID: layerID, opacity: opacity))
    }

    func compositeLiveStroke(batch: StampBatch, opacity: Double) throws {
        try check("compositeLiveStroke")
        calls.append(.compositeLiveStroke(stampCount: batch.stamps.count, opacity: opacity))
    }

    func endFrame() throws {
        try check("endFrame")
        calls.append(.endFrame)
    }

    // MARK: - Queries

    var drawCallCount: Int {
        calls.filter { if case .drawIntoCache = $0 { return true }; return false }.count
    }

    var didBeginFrame: Bool { calls.contains(.beginFrame(size: .screenSize)) || calls.contains { if case .beginFrame = $0 { return true }; return false } }

    func drawScissors(layerID: UUID) -> [Rect?] {
        calls.compactMap {
            if case let .drawIntoCache(id, _, scissor) = $0, id == layerID { return scissor }
            return nil
        }
    }

    var compositeOrder: [UUID] {
        calls.compactMap {
            if case let .compositeCache(id, _) = $0 { return id }
            return nil
        }
    }

    func index(of predicate: (Call) -> Bool) -> Int? {
        calls.firstIndex(where: predicate)
    }
}
