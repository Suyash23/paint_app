import Foundation
import Metal
import QuartzCore

/// Somewhere a frame can be composited into.
///
/// Abstracting this away from `CAMetalDrawable` means frames can be rendered
/// offscreen into a plain texture and read back, so shader output can be
/// asserted on rather than merely eyeballed in a window.
public enum FrameTarget {
    /// A live drawable from a `CAMetalLayer`, to be presented.
    case drawable(CAMetalDrawable)
    /// An offscreen texture, with nothing presented.
    case texture(MTLTexture)

    public var texture: MTLTexture {
        switch self {
        case let .drawable(drawable): return drawable.texture
        case let .texture(texture): return texture
        }
    }

    /// The drawable to present, if this target is presentable.
    var presentable: CAMetalDrawable? {
        switch self {
        case let .drawable(drawable): return drawable
        case .texture: return nil
        }
    }
}
