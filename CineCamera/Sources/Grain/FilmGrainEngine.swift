import Foundation
import simd

public struct FilmGrainParameters {
    public var profile: FilmGrainProfile
    public var iso: Float
    public var intensityMultiplier: Float
    public var frame: Int
    public var seed: UInt32

    public init(profile: FilmGrainProfile,
                iso: Float = 800,
                intensityMultiplier: Float = 1.0,
                frame: Int = 0,
                seed: UInt32 = 0x9E3779B9) {
        self.profile = profile
        self.iso = iso
        self.intensityMultiplier = intensityMultiplier
        self.frame = frame
        self.seed = seed
    }
}

public enum FilmGrainEngine {

    public static let lumaWeights = SIMD3<Float>(0.2126, 0.7152, 0.0722)

    /// ISO scaling — grain intensity grows roughly linearly per stop above the
    /// profile's native ISO. Below native, grain is dampened (cleaner image).
    @inlinable
    public static func isoScale(iso: Float, native: Float) -> Float {
        let safeIso = max(iso, 1)
        let safeNative = max(native, 1)
        let stops = log2(safeIso / safeNative)
        return max(0.25, 1.0 + 0.5 * stops)
    }

    /// Apply grain to a single pixel. Deterministic for the same (position, params).
    public static func apply(_ rgb: SIMD3<Float>,
                             at position: SIMD2<Int>,
                             params: FilmGrainParameters) -> SIMD3<Float> {
        let grain = sampleGrain(at: position, params: params)
        let luma = simd_dot(simd_max(rgb, SIMD3<Float>(repeating: 0)), lumaWeights)
        let mask = pow(max(0, 1 - min(luma, 1)), params.profile.shadowBias)
        let strength = params.profile.intensity
                     * isoScale(iso: params.iso, native: params.profile.nativeISO)
                     * params.intensityMultiplier
                     * mask
        return rgb + grain * strength
    }

    /// Returns a centered-around-zero per-channel grain sample for the given pixel.
    /// Output is unmasked (no luma weighting) and unscaled by ISO/intensity.
    public static func sampleGrain(at position: SIMD2<Int>,
                                   params: FilmGrainParameters) -> SIMD3<Float> {
        let p = params.profile
        let cellX = Int(floor(Float(position.x) / max(p.size, 1e-3)))
        let cellY = Int(floor(Float(position.y) / max(p.size, 1e-3)))

        if p.monochrome {
            let n = noise(cellX, cellY, params.frame &* 3, seed: params.seed)
            return SIMD3<Float>(n, n, n) * p.channelGain
        }
        let nR = noise(cellX, cellY, params.frame &* 3 &+ 0, seed: params.seed)
        let nG = noise(cellX, cellY, params.frame &* 3 &+ 1, seed: params.seed)
        let nB = noise(cellX, cellY, params.frame &* 3 &+ 2, seed: params.seed)
        return SIMD3<Float>(nR, nG, nB) * p.channelGain
    }

    /// Generate grain values for a tile (CPU reference, useful for tests/preview).
    public static func generateGrainTile(width: Int,
                                         height: Int,
                                         params: FilmGrainParameters) -> [SIMD3<Float>] {
        var out = [SIMD3<Float>](repeating: .zero, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                out[y * width + x] = sampleGrain(at: SIMD2<Int>(x, y), params: params)
            }
        }
        return out
    }

    // MARK: - Hash-based noise (deterministic, centered ~ [-1, 1])

    @usableFromInline
    static func noise(_ x: Int, _ y: Int, _ z: Int, seed: UInt32) -> Float {
        var h: UInt32 = seed
        h = mix32(h, UInt32(bitPattern: Int32(truncatingIfNeeded: x)))
        h = mix32(h, UInt32(bitPattern: Int32(truncatingIfNeeded: y)))
        h = mix32(h, UInt32(bitPattern: Int32(truncatingIfNeeded: z)))
        // xorshift finalizer
        h ^= h >> 16
        h = h &* 0x7feb352d
        h ^= h >> 15
        h = h &* 0x846ca68b
        h ^= h >> 16
        let unit = Float(h) / Float(UInt32.max)  // [0, 1]
        return unit * 2 - 1                       // [-1, 1]
    }

    @inline(__always)
    private static func mix32(_ a: UInt32, _ b: UInt32) -> UInt32 {
        var x = a ^ b
        x = x &* 0x9E3779B1
        x ^= x >> 16
        return x
    }
}
