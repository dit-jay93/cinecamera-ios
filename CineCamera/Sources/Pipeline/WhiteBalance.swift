import Foundation
import simd

public enum WhiteBalance {

    /// Tanner Helland's piecewise approximation of the Planckian black-body
    /// spectrum mapped to sRGB (returns components in [0,1]).
    public static func kelvinToRGB(_ kelvin: Float) -> SIMD3<Float> {
        let t = max(1000, min(40000, kelvin)) / 100.0

        let r: Float
        if t <= 66 {
            r = 1.0
        } else {
            let v = 329.698727446 * pow(Double(t - 60), -0.1332047592)
            r = clamp01(Float(v) / 255.0)
        }

        let g: Float
        if t <= 66 {
            let v = 99.4708025861 * log(Double(t)) - 161.1195681661
            g = clamp01(Float(v) / 255.0)
        } else {
            let v = 288.1221695283 * pow(Double(t - 60), -0.0755148492)
            g = clamp01(Float(v) / 255.0)
        }

        let b: Float
        if t >= 66 {
            b = 1.0
        } else if t <= 19 {
            b = 0.0
        } else {
            let v = 138.5177312231 * log(Double(t - 10)) - 305.0447927307
            b = clamp01(Float(v) / 255.0)
        }
        return SIMD3<Float>(r, g, b)
    }

    /// Per-channel gain that neutralizes a scene illuminated at `targetKelvin`
    /// when the reference white point is `referenceKelvin` (default 6500K /
    /// sRGB D65). `tint` shifts the green-magenta axis: -150 → green
    /// (boost G), +150 → magenta (boost R+B).
    public static func gains(targetKelvin: Float,
                             referenceKelvin: Float = 6500,
                             tint: Float = 0) -> SIMD3<Float> {
        let target = kelvinToRGB(targetKelvin)
        let reference = kelvinToRGB(referenceKelvin)
        let safeTarget = SIMD3<Float>(max(target.x, 1e-3),
                                      max(target.y, 1e-3),
                                      max(target.z, 1e-3))
        var gains = reference / safeTarget

        // Tint: remap [-150, 150] to ±0.20 swing on the G/M axis.
        let tShift = max(-150, min(150, tint)) / 150.0 * 0.20
        gains.y *= (1.0 - tShift)            // negative tShift → green boost
        gains.x *= (1.0 + tShift * 0.5)      // positive tShift → magenta boost
        gains.z *= (1.0 + tShift * 0.5)
        return gains
    }

    /// Apply WB gains to a pixel.
    public static func apply(_ rgb: SIMD3<Float>,
                             targetKelvin: Float,
                             referenceKelvin: Float = 6500,
                             tint: Float = 0) -> SIMD3<Float> {
        return rgb * gains(targetKelvin: targetKelvin,
                           referenceKelvin: referenceKelvin,
                           tint: tint)
    }

    @inline(__always)
    private static func clamp01(_ x: Float) -> Float { return max(0, min(1, x)) }
}
