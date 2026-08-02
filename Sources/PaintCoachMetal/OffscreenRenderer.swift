import Foundation
import Metal
import PaintCoachCore

/// Renders frames into a plain texture and reads the pixels back.
///
/// This is how the Metal backend gets verified without a window: render a known
/// document, then assert on actual pixel values. Failures in the clip-space
/// transform, Y flip, or blend state become concrete numbers instead of guesses.
public final class OffscreenRenderer {

    public struct Pixel: Equatable, CustomStringConvertible {
        public var r: UInt8
        public var g: UInt8
        public var b: UInt8
        public var a: UInt8

        public var isTransparent: Bool { a == 0 }
        public var description: String { "rgba(\(r), \(g), \(b), \(a))" }
    }

    private let device: MTLDevice
    private let texture: MTLTexture
    public let backend: MetalRenderBackend
    public let size: CanvasSize

    /// Whether this machine exposes a Metal device at all. Sandboxes and some CI
    /// environments have none, and that is worth reporting differently from a
    /// genuine rendering failure.
    public static var isMetalAvailable: Bool { MTLCreateSystemDefaultDevice() != nil }

    public init(size: CanvasSize) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RenderError.backendUnavailable
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: MetalRenderBackend.colorPixelFormat,
            width: size.width,
            height: size.height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        // Shared storage so the CPU can read the result back.
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RenderError.backendUnavailable
        }
        self.device = device
        self.texture = texture
        self.size = size
        self.backend = try MetalRenderBackend(device: device)
        self.backend.frameTargetProvider = { [texture] in .texture(texture) }
    }

    /// Reads one pixel in canvas coordinates, where y grows downward from the top.
    public func pixel(x: Int, y: Int) -> Pixel {
        var bytes = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &bytes,
            bytesPerRow: 4,
            from: MTLRegionMake2D(x, y, 1, 1),
            mipmapLevel: 0
        )
        // Texture is BGRA; expose it as RGBA.
        return Pixel(r: bytes[2], g: bytes[1], b: bytes[0], a: bytes[3])
    }

    /// Reads the whole texture, row-major from the top-left.
    public func allPixels() -> [Pixel] {
        let count = size.width * size.height
        var bytes = [UInt8](repeating: 0, count: count * 4)
        texture.getBytes(
            &bytes,
            bytesPerRow: size.width * 4,
            from: MTLRegionMake2D(0, 0, size.width, size.height),
            mipmapLevel: 0
        )
        return (0..<count).map { i in
            let o = i * 4
            return Pixel(r: bytes[o + 2], g: bytes[o + 1], b: bytes[o], a: bytes[o + 3])
        }
    }

    /// Count of pixels with any coverage — a cheap "did anything draw?" check.
    public func coveredPixelCount() -> Int {
        allPixels().filter { !$0.isTransparent }.count
    }

    /// Bounding box of all non-transparent pixels, in canvas coordinates.
    public func coverageBounds() -> Rect? {
        let pixels = allPixels()
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        for y in 0..<size.height {
            for x in 0..<size.width where !pixels[y * size.width + x].isTransparent {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        guard minX <= maxX else { return nil }
        return Rect(
            x: Double(minX), y: Double(minY),
            width: Double(maxX - minX + 1), height: Double(maxY - minY + 1)
        )
    }
}
