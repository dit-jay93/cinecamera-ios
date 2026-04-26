import Foundation
import simd

public enum CinemaFilterEngine {

    public static let lumaWeights = SIMD3<Float>(0.2126, 0.7152, 0.0722)

    /// Apply a filter to a single pixel — combines transmittance, saturation
    /// reduction, and black lift. Bloom (spatial) is not applied here; use
    /// `applyTile` or the GPU shader for that.
    public static func applyPixel(_ rgb: SIMD3<Float>,
                                  filter: CinemaFilter,
                                  intensity: Float) -> SIMD3<Float> {
        let t = max(0, min(1, intensity))
        if t == 0 { return rgb }
        var out = filter.applyPixel(rgb, intensity: t)

        let sr = filter.spatial.saturationReduction * t
        if sr > 0 {
            let luma = simd_dot(out, lumaWeights)
            let mono = SIMD3<Float>(repeating: luma)
            out = mono + (1 - sr) * (out - mono)
        }
        let lift = filter.spatial.blackLift * t
        if lift > 0 {
            out = out + SIMD3<Float>(repeating: lift) * (1 - out)
        }
        return out
    }

    // MARK: - Separable Gaussian (CPU reference)

    /// Build a 1D Gaussian kernel with (2 * radius + 1) taps, normalized to sum = 1.
    public static func gaussianKernel(radius: Int) -> [Float] {
        let r = max(radius, 0)
        if r == 0 { return [1.0] }
        let sigma = Float(r) / 3.0
        let twoSigmaSq = 2.0 * sigma * sigma
        var weights = [Float](repeating: 0, count: 2 * r + 1)
        var sum: Float = 0
        for i in -r...r {
            let w = exp(-Float(i * i) / twoSigmaSq)
            weights[i + r] = w
            sum += w
        }
        for i in 0..<weights.count { weights[i] /= sum }
        return weights
    }

    /// Apply a separable Gaussian blur to an RGB tile (CPU reference).
    /// Edges use clamp-to-edge sampling.
    public static func applySeparableGaussian(_ pixels: [SIMD3<Float>],
                                              width: Int,
                                              height: Int,
                                              radius: Int) -> [SIMD3<Float>] {
        let r = max(radius, 0)
        if r == 0 { return pixels }
        let kernel = gaussianKernel(radius: r)
        var horiz = [SIMD3<Float>](repeating: .zero, count: pixels.count)

        for y in 0..<height {
            for x in 0..<width {
                var sum = SIMD3<Float>(0, 0, 0)
                for k in -r...r {
                    let xi = min(width - 1, max(0, x + k))
                    sum += pixels[y * width + xi] * kernel[k + r]
                }
                horiz[y * width + x] = sum
            }
        }

        var vert = [SIMD3<Float>](repeating: .zero, count: pixels.count)
        for y in 0..<height {
            for x in 0..<width {
                var sum = SIMD3<Float>(0, 0, 0)
                for k in -r...r {
                    let yi = min(height - 1, max(0, y + k))
                    sum += horiz[yi * width + x] * kernel[k + r]
                }
                vert[y * width + x] = sum
            }
        }
        return vert
    }

    /// Apply bloom: blur the (optionally thresholded) frame and additively
    /// mix with the original by `bloomGain`.
    public static func applyBloom(_ pixels: [SIMD3<Float>],
                                  width: Int,
                                  height: Int,
                                  spatial: SpatialEffect,
                                  intensity: Float) -> [SIMD3<Float>] {
        let t = max(0, min(1, intensity))
        let radius = Int((spatial.bloomRadius * t).rounded())
        let gain = spatial.bloomGain * t
        if radius == 0 || gain == 0 { return pixels }

        let bright: [SIMD3<Float>]
        if spatial.bloomThreshold > 0 {
            bright = pixels.map { rgb -> SIMD3<Float> in
                let luma = simd_dot(simd_max(rgb, SIMD3<Float>(repeating: 0)), lumaWeights)
                let m = max(0, luma - spatial.bloomThreshold) / max(1e-3, 1 - spatial.bloomThreshold)
                return rgb * m
            }
        } else {
            bright = pixels
        }
        let blurred = applySeparableGaussian(bright, width: width, height: height, radius: radius)
        var out = [SIMD3<Float>](repeating: .zero, count: pixels.count)
        for i in 0..<pixels.count {
            out[i] = pixels[i] + blurred[i] * gain
        }
        return out
    }

    /// Full per-tile filter application — pixel transform first, then bloom.
    public static func applyTile(_ pixels: [SIMD3<Float>],
                                 width: Int,
                                 height: Int,
                                 filter: CinemaFilter,
                                 intensity: Float) -> [SIMD3<Float>] {
        let t = max(0, min(1, intensity))
        if t == 0 { return pixels }
        let perPixel = pixels.map { applyPixel($0, filter: filter, intensity: t) }
        return applyBloom(perPixel, width: width, height: height,
                          spatial: filter.spatial, intensity: t)
    }
}
