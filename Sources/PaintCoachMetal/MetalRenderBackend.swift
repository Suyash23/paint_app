import Foundation
import Metal
import QuartzCore
import simd
import PaintCoachCore

/// GPU-side mirror of the `StampInstance` struct in Stamp.metal.
/// Field order and padding must match the shader exactly.
struct StampInstanceData {
    var position: SIMD2<Float>
    var diameter: Float
    var opacity: Float
    var rotation: Float
    var eccentricity: Float
}

/// Metal implementation of `RenderBackend`.
///
/// Verified on device: 20/20 checks in `PaintCoachApp` pass, covering the
/// clip-space transform, Y orientation, scissor origin, premultiplied blend
/// state, and `StampInstanceData` layout matching the shader struct. Run
/// `swift run PaintCoachApp` after changing anything here — those properties are
/// invisible to the compiler and only pixel readback catches a regression.
public final class MetalRenderBackend: RenderBackend {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let stampPipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let colorPipeline: MTLRenderPipelineState
    /// Blending disabled, so drawing transparent actually erases.
    private let erasePipeline: MTLRenderPipelineState

    /// Per-layer cache textures.
    private var caches: [UUID: MTLTexture] = [:]

    /// Frame state, valid only between `beginFrame` and `endFrame`.
    private var frameCommandBuffer: MTLCommandBuffer?
    private var frameEncoder: MTLRenderCommandEncoder?
    private var frameTarget: FrameTarget?

    /// Supplies the target to render into. Injected so this type depends on no
    /// specific view class, and so frames can be rendered offscreen for testing.
    public var frameTargetProvider: (() -> FrameTarget?)?

    /// Brush tip hardness, 0 soft ... 1 hard.
    public var hardness: Float = 0.85

    public static let colorPixelFormat: MTLPixelFormat = .bgra8Unorm

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device, let queue = device.makeCommandQueue() else {
            throw RenderError.backendUnavailable
        }
        self.device = device
        self.commandQueue = queue

        let library = try MetalRenderBackend.loadLibrary(device: device)

        func pipeline(
            vertex: String,
            fragment: String,
            blending: Bool = true
        ) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)

            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = MetalRenderBackend.colorPixelFormat
            // Premultiplied source-over. Shaders output premultiplied alpha, so
            // the source factor is 1 rather than sourceAlpha.
            attachment.isBlendingEnabled = blending
            if blending {
                attachment.rgbBlendOperation = .add
                attachment.alphaBlendOperation = .add
                attachment.sourceRGBBlendFactor = .one
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }

        self.stampPipeline = try pipeline(vertex: "stamp_vertex", fragment: "stamp_fragment")
        self.compositePipeline = try pipeline(vertex: "composite_vertex", fragment: "composite_fragment")
        self.colorPipeline = try pipeline(vertex: "composite_vertex", fragment: "color_fragment")
        self.erasePipeline = try pipeline(
            vertex: "composite_vertex", fragment: "erase_fragment", blending: false
        )
    }

    // MARK: - Shader library

    /// Loads the shader library.
    ///
    /// SwiftPM copies `.metal` files into the resource bundle as source rather
    /// than compiling them to a `.metallib`, so `makeDefaultLibrary` finds
    /// nothing. Try the precompiled library first (which is what an Xcode app
    /// target produces), then fall back to compiling the bundled source at
    /// runtime. The fallback costs a few hundred milliseconds on first launch.
    static func loadLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let library = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            return library
        }
        guard let url = Bundle.module.url(forResource: "Stamp", withExtension: "metal"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw RenderError.backendUnavailable
        }
        return try device.makeLibrary(source: source, options: nil)
    }

    // MARK: - Cache lifetime

    public func prepareCache(layerID: UUID, size: CanvasSize) throws {
        if let existing = caches[layerID],
           existing.width == size.width, existing.height == size.height {
            return
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: MetalRenderBackend.colorPixelFormat,
            width: size.width,
            height: size.height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RenderError.cacheAllocationFailed(layerID)
        }
        caches[layerID] = texture

        // A fresh texture has undefined contents; clear it before any partial
        // draw reads or blends against it.
        try clearCache(layerID: layerID, region: nil)
    }

    public func releaseCache(layerID: UUID) {
        caches.removeValue(forKey: layerID)
    }

    public func clearCache(layerID: UUID, region: Rect?) throws {
        guard let texture = caches[layerID] else { throw RenderError.noCacheForLayer(layerID) }
        guard let buffer = commandQueue.makeCommandBuffer() else { throw RenderError.backendUnavailable }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store

        if let region {
            // Partial clear: load existing contents, then overwrite the scissored
            // area with transparent. Uses a non-blending pipeline — the normal
            // source-over state would composite transparent over the old pixels
            // and leave them untouched instead of erasing them.
            descriptor.colorAttachments[0].loadAction = .load
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                throw RenderError.backendUnavailable
            }
            encoder.setScissorRect(scissorRect(for: region, in: texture))
            encoder.setRenderPipelineState(erasePipeline)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        } else {
            descriptor.colorAttachments[0].loadAction = .clear
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                throw RenderError.backendUnavailable
            }
            encoder.endEncoding()
        }
        buffer.commit()
    }

    // MARK: - Drawing into a cache

    public func drawIntoCache(layerID: UUID, batch: StampBatch, target: RenderTarget) throws {
        guard let texture = caches[layerID] else { throw RenderError.noCacheForLayer(layerID) }
        guard !batch.stamps.isEmpty else { return }
        guard let buffer = commandQueue.makeCommandBuffer() else { throw RenderError.backendUnavailable }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            throw RenderError.backendUnavailable
        }
        if let scissor = target.scissor {
            encoder.setScissorRect(scissorRect(for: scissor, in: texture))
        }
        try encode(batch: batch, into: encoder, canvasSize: target.size)
        encoder.endEncoding()
        buffer.commit()
    }

    /// Uploads stamp instances and issues one instanced draw for the batch.
    private func encode(
        batch: StampBatch,
        into encoder: MTLRenderCommandEncoder,
        canvasSize: CanvasSize
    ) throws {
        var instances = batch.stamps.map { stamp in
            StampInstanceData(
                position: SIMD2<Float>(Float(stamp.position.x), Float(stamp.position.y)),
                diameter: Float(stamp.diameter),
                opacity: Float(stamp.opacity),
                rotation: Float(stamp.rotation),
                eccentricity: Float(stamp.eccentricity)
            )
        }
        let byteCount = instances.count * MemoryLayout<StampInstanceData>.stride
        guard let instanceBuffer = device.makeBuffer(
            bytes: &instances, length: byteCount, options: .storageModeShared
        ) else {
            throw RenderError.backendUnavailable
        }

        var size = SIMD2<Float>(Float(canvasSize.width), Float(canvasSize.height))
        var color = SIMD4<Float>(
            Float(batch.color.r), Float(batch.color.g),
            Float(batch.color.b), Float(batch.color.a)
        )
        var tipHardness = hardness

        encoder.setRenderPipelineState(stampPipeline)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&size, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        encoder.setFragmentBytes(&color, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setFragmentBytes(&tipHardness, length: MemoryLayout<Float>.stride, index: 1)
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4,
            instanceCount: instances.count
        )
    }

    // MARK: - Frame compositing

    public func beginFrame(size: CanvasSize) throws {
        guard frameEncoder == nil else { throw RenderError.frameAlreadyInProgress }
        guard let target = frameTargetProvider?() else { throw RenderError.backendUnavailable }
        guard let buffer = commandQueue.makeCommandBuffer() else { throw RenderError.backendUnavailable }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            throw RenderError.backendUnavailable
        }
        frameCommandBuffer = buffer
        frameEncoder = encoder
        frameTarget = target
    }

    public func compositeColor(_ color: RGBA, opacity: Double) throws {
        guard let encoder = frameEncoder else { throw RenderError.noFrameInProgress }
        var rgba = SIMD4<Float>(Float(color.r), Float(color.g), Float(color.b), Float(color.a))
        var alpha = Float(opacity)
        encoder.setRenderPipelineState(colorPipeline)
        encoder.setFragmentBytes(&rgba, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setFragmentBytes(&alpha, length: MemoryLayout<Float>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    public func compositeCache(layerID: UUID, opacity: Double) throws {
        guard let encoder = frameEncoder else { throw RenderError.noFrameInProgress }
        guard let texture = caches[layerID] else { throw RenderError.noCacheForLayer(layerID) }
        var alpha = Float(opacity)
        encoder.setRenderPipelineState(compositePipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&alpha, length: MemoryLayout<Float>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    public func compositeLiveStroke(batch: StampBatch, opacity: Double) throws {
        guard let encoder = frameEncoder else { throw RenderError.noFrameInProgress }
        guard let target = frameTarget else { throw RenderError.noFrameInProgress }
        guard !batch.stamps.isEmpty else { return }

        // Drawn straight onto the frame, never into the layer cache — this is
        // what keeps a growing stroke from repainting the layer.
        var faded = batch
        if opacity < 1 {
            faded.stamps = batch.stamps.map {
                var stamp = $0
                stamp.opacity *= opacity
                return stamp
            }
        }
        try encode(
            batch: faded,
            into: encoder,
            canvasSize: CanvasSize(width: target.texture.width, height: target.texture.height)
        )
    }

    public func endFrame() throws {
        guard let encoder = frameEncoder, let buffer = frameCommandBuffer else {
            throw RenderError.noFrameInProgress
        }
        encoder.endEncoding()
        if let drawable = frameTarget?.presentable {
            buffer.present(drawable)
        }
        buffer.commit()
        // Offscreen targets are read back immediately after this returns, so the
        // GPU must have finished before the caller inspects the texture.
        if frameTarget?.presentable == nil {
            buffer.waitUntilCompleted()
        }
        frameEncoder = nil
        frameCommandBuffer = nil
        frameTarget = nil
    }

    // MARK: - Helpers

    /// Converts a canvas-space rect to a texture-clamped scissor rect.
    /// Metal rejects scissor rects extending past the attachment.
    private func scissorRect(for rect: Rect, in texture: MTLTexture) -> MTLScissorRect {
        let clamped = rect.integral()
        let x = max(Int(clamped.minX), 0)
        let y = max(Int(clamped.minY), 0)
        let maxWidth = texture.width - x
        let maxHeight = texture.height - y
        return MTLScissorRect(
            x: x,
            y: y,
            width: min(max(Int(clamped.width), 1), max(maxWidth, 1)),
            height: min(max(Int(clamped.height), 1), max(maxHeight, 1))
        )
    }
}
