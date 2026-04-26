import Foundation
import simd

#if canImport(Metal)
import Metal

public enum MetalImageBufferError: Error {
    case textureCreationFailed
    case dimensionMismatch(expected: Int, got: Int)
}

/// Helpers for moving CPU pixel arrays (`[SIMD3<Float>]`) into and out of
/// `MTLTexture`s. We always use `rgba32Float` because the entire color
/// pipeline operates in linear-light float space — narrower formats would
/// quantize the CDL/LUT math and break the GPU↔CPU parity tests.
///
/// SIMD3<Float> stores as 16 bytes (3 lanes + 1 padding lane) on Apple
/// Silicon, so we explicitly pack into a contiguous `[Float]` buffer of
/// 4·width·height before uploading. The alpha channel is set to 1.0 on
/// upload and dropped on download.
public enum MetalImageBuffer {

    public static let pixelFormat: MTLPixelFormat = .rgba32Float

    public static func makeTexture(device: MTLDevice,
                                    width: Int,
                                    height: Int,
                                    usage: MTLTextureUsage = [.shaderRead, .shaderWrite]) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = usage
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else {
            throw MetalImageBufferError.textureCreationFailed
        }
        return tex
    }

    /// Uploads a row-major pixel array into a fresh texture sized
    /// `width × height`. The pixel count must equal `width * height`.
    public static func makeTexture(device: MTLDevice,
                                    pixels: [SIMD3<Float>],
                                    width: Int,
                                    height: Int) throws -> MTLTexture {
        guard pixels.count == width * height else {
            throw MetalImageBufferError.dimensionMismatch(expected: width * height,
                                                           got: pixels.count)
        }
        let texture = try makeTexture(device: device, width: width, height: height)
        try upload(pixels: pixels, to: texture)
        return texture
    }

    public static func upload(pixels: [SIMD3<Float>], to texture: MTLTexture) throws {
        let width = texture.width
        let height = texture.height
        guard pixels.count == width * height else {
            throw MetalImageBufferError.dimensionMismatch(expected: width * height,
                                                           got: pixels.count)
        }
        var packed = [Float](repeating: 0, count: width * height * 4)
        for i in 0..<pixels.count {
            let p = pixels[i]
            let base = i * 4
            packed[base + 0] = p.x
            packed[base + 1] = p.y
            packed[base + 2] = p.z
            packed[base + 3] = 1.0
        }
        let region = MTLRegionMake2D(0, 0, width, height)
        let bytesPerRow = width * 4 * MemoryLayout<Float>.size
        packed.withUnsafeBytes { raw in
            texture.replace(region: region,
                            mipmapLevel: 0,
                            withBytes: raw.baseAddress!,
                            bytesPerRow: bytesPerRow)
        }
    }

    /// Downloads a texture's contents as `[SIMD3<Float>]` (alpha discarded).
    public static func download(_ texture: MTLTexture) -> [SIMD3<Float>] {
        let width = texture.width
        let height = texture.height
        var packed = [Float](repeating: 0, count: width * height * 4)
        let region = MTLRegionMake2D(0, 0, width, height)
        let bytesPerRow = width * 4 * MemoryLayout<Float>.size
        packed.withUnsafeMutableBytes { raw in
            texture.getBytes(raw.baseAddress!,
                             bytesPerRow: bytesPerRow,
                             from: region,
                             mipmapLevel: 0)
        }
        var out = [SIMD3<Float>](repeating: .zero, count: width * height)
        for i in 0..<out.count {
            let base = i * 4
            out[i] = SIMD3<Float>(packed[base + 0], packed[base + 1], packed[base + 2])
        }
        return out
    }
}

#endif
