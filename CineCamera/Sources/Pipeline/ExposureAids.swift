import Foundation
import simd

/// Pixel-level over-exposure warning. Marks any pixel whose luma exceeds
/// `threshold` (BT.709). The output mask matches the input dimensions:
/// 1.0 = clipped/at-risk, 0.0 = safe.
public enum ZebraDetector {

    public static func mask(_ pixels: [SIMD3<Float>],
                            width: Int,
                            height: Int,
                            threshold: Float = 0.95) -> [Float] {
        precondition(pixels.count == width * height, "pixel count != width*height")
        let lumaW = SIMD3<Float>(0.2126, 0.7152, 0.0722)
        var out = [Float](repeating: 0, count: pixels.count)
        for i in 0..<pixels.count {
            let p = simd_max(pixels[i], SIMD3<Float>(repeating: 0))
            let y = simd_dot(p, lumaW)
            out[i] = y >= threshold ? 1.0 : 0.0
        }
        return out
    }

    /// Striped variant: only mark every other diagonal line so the overlay
    /// reads as moving zebras instead of a flat blob. `phase` is a frame
    /// index used to animate the stripes.
    public static func stripedMask(_ pixels: [SIMD3<Float>],
                                   width: Int,
                                   height: Int,
                                   threshold: Float = 0.95,
                                   stripePeriod: Int = 8,
                                   phase: Int = 0) -> [Float] {
        precondition(pixels.count == width * height)
        precondition(stripePeriod >= 2)
        let lumaW = SIMD3<Float>(0.2126, 0.7152, 0.0722)
        var out = [Float](repeating: 0, count: pixels.count)
        let half = stripePeriod / 2
        for y in 0..<height {
            for x in 0..<width {
                let p = simd_max(pixels[y * width + x], SIMD3<Float>(repeating: 0))
                let luma = simd_dot(p, lumaW)
                if luma >= threshold {
                    let stripe = ((x + y + phase) % stripePeriod) < half
                    out[y * width + x] = stripe ? 1.0 : 0.0
                }
            }
        }
        return out
    }
}

/// Focus peaking: Sobel-style edge detection on luma. Pixels whose gradient
/// magnitude exceeds `threshold` are marked 1.0 (in-focus high-frequency
/// detail). The mask can be coloured later by the renderer.
public enum FocusPeaking {

    public static func mask(_ pixels: [SIMD3<Float>],
                            width: Int,
                            height: Int,
                            threshold: Float = 0.15) -> [Float] {
        precondition(pixels.count == width * height)
        precondition(width >= 3 && height >= 3, "image too small for Sobel")
        let lumaW = SIMD3<Float>(0.2126, 0.7152, 0.0722)
        var luma = [Float](repeating: 0, count: pixels.count)
        for i in 0..<pixels.count {
            let p = simd_max(pixels[i], SIMD3<Float>(repeating: 0))
            luma[i] = simd_dot(p, lumaW)
        }
        var out = [Float](repeating: 0, count: pixels.count)
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let tl = luma[(y - 1) * width + (x - 1)]
                let t  = luma[(y - 1) * width + x]
                let tr = luma[(y - 1) * width + (x + 1)]
                let l  = luma[y * width + (x - 1)]
                let r  = luma[y * width + (x + 1)]
                let bl = luma[(y + 1) * width + (x - 1)]
                let b  = luma[(y + 1) * width + x]
                let br = luma[(y + 1) * width + (x + 1)]

                let gx = (tr + 2 * r + br) - (tl + 2 * l + bl)
                let gy = (bl + 2 * b + br) - (tl + 2 * t + tr)
                let mag = sqrt(gx * gx + gy * gy)
                if mag >= threshold {
                    out[y * width + x] = 1.0
                }
            }
        }
        return out
    }

    /// Continuous gradient magnitude (not thresholded). Useful when the
    /// renderer wants to fade the peaking overlay rather than hard-mask it.
    public static func gradient(_ pixels: [SIMD3<Float>],
                                width: Int,
                                height: Int) -> [Float] {
        precondition(pixels.count == width * height)
        precondition(width >= 3 && height >= 3)
        let lumaW = SIMD3<Float>(0.2126, 0.7152, 0.0722)
        var luma = [Float](repeating: 0, count: pixels.count)
        for i in 0..<pixels.count {
            let p = simd_max(pixels[i], SIMD3<Float>(repeating: 0))
            luma[i] = simd_dot(p, lumaW)
        }
        var out = [Float](repeating: 0, count: pixels.count)
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let tl = luma[(y - 1) * width + (x - 1)]
                let t  = luma[(y - 1) * width + x]
                let tr = luma[(y - 1) * width + (x + 1)]
                let l  = luma[y * width + (x - 1)]
                let r  = luma[y * width + (x + 1)]
                let bl = luma[(y + 1) * width + (x - 1)]
                let b  = luma[(y + 1) * width + x]
                let br = luma[(y + 1) * width + (x + 1)]

                let gx = (tr + 2 * r + br) - (tl + 2 * l + bl)
                let gy = (bl + 2 * b + br) - (tl + 2 * t + tr)
                out[y * width + x] = sqrt(gx * gx + gy * gy)
            }
        }
        return out
    }
}

/// False-color exposure map. Returns an RGB image where each pixel is
/// re-coloured by its luma zone — useful as a DP-style exposure aid.
/// Zones (BT.709 luma):
///  - <  0.02       → purple   (crushed black)
///  -    0.02-0.18  → blue     (deep shadow)
///  -    0.18-0.40  → green    (mid-low)
///  -    0.40-0.60  → grey     (middle grey)
///  -    0.60-0.80  → yellow   (mid-high)
///  -    0.80-0.95  → orange   (highlight)
///  -    0.95-1.00  → red      (about to clip)
///  - >= 1.00       → white    (clipped)
public enum FalseColor {

    public static func map(_ pixels: [SIMD3<Float>]) -> [SIMD3<Float>] {
        let lumaW = SIMD3<Float>(0.2126, 0.7152, 0.0722)
        var out = [SIMD3<Float>](repeating: .zero, count: pixels.count)
        for i in 0..<pixels.count {
            let p = simd_max(pixels[i], SIMD3<Float>(repeating: 0))
            let y = simd_dot(p, lumaW)
            out[i] = colorFor(luma: y)
        }
        return out
    }

    @inline(__always)
    public static func colorFor(luma y: Float) -> SIMD3<Float> {
        switch y {
        case ..<0.02:           return SIMD3<Float>(0.50, 0.00, 0.50)
        case ..<0.18:           return SIMD3<Float>(0.10, 0.20, 0.90)
        case ..<0.40:           return SIMD3<Float>(0.10, 0.80, 0.20)
        case ..<0.60:           return SIMD3<Float>(0.50, 0.50, 0.50)
        case ..<0.80:           return SIMD3<Float>(0.95, 0.95, 0.10)
        case ..<0.95:           return SIMD3<Float>(0.95, 0.60, 0.10)
        case ..<1.00:           return SIMD3<Float>(0.95, 0.10, 0.10)
        default:                return SIMD3<Float>(1.00, 1.00, 1.00)
        }
    }
}
