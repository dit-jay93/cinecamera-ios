import Foundation
import simd

public struct CDLChannelSOP: Codable, Equatable {
    public var slope: Float
    public var offset: Float
    public var power: Float

    public init(slope: Float = 1.0, offset: Float = 0.0, power: Float = 1.0) {
        self.slope = slope
        self.offset = offset
        self.power = power
    }

    public static let identity = CDLChannelSOP()
}

public struct CDLZone: Codable, Equatable {
    public var luma: CDLChannelSOP
    public var red: CDLChannelSOP
    public var green: CDLChannelSOP
    public var blue: CDLChannelSOP
    public var saturation: Float

    public init(luma: CDLChannelSOP = .identity,
                red: CDLChannelSOP = .identity,
                green: CDLChannelSOP = .identity,
                blue: CDLChannelSOP = .identity,
                saturation: Float = 1.0) {
        self.luma = luma
        self.red = red
        self.green = green
        self.blue = blue
        self.saturation = saturation
    }

    public static let identity = CDLZone()
}

public struct CDLParameters: Codable, Equatable {
    public var shadows: CDLZone
    public var midtones: CDLZone
    public var highlights: CDLZone

    public init(shadows: CDLZone = .identity,
                midtones: CDLZone = .identity,
                highlights: CDLZone = .identity) {
        self.shadows = shadows
        self.midtones = midtones
        self.highlights = highlights
    }

    public static let identity = CDLParameters()

    public var isIdentity: Bool { self == .identity }
}

public enum CDLEngine {

    /// ITU-R BT.709 luma weights (matches Rec.709 ODT primaries).
    public static let lumaWeights = SIMD3<Float>(0.2126, 0.7152, 0.0722)

    /// Returns (shadowWeight, midWeight, highlightWeight). Weights sum to 1 for any luma.
    public static func toneZoneWeights(luma: Float) -> SIMD3<Float> {
        let s = smoothstep(0.5, 0.0, luma)
        let h = smoothstep(0.5, 1.0, luma)
        let m = max(0, 1 - s - h)
        return SIMD3<Float>(s, m, h)
    }

    public static func apply(_ rgb: SIMD3<Float>, params: CDLParameters) -> SIMD3<Float> {
        let luma = simd_dot(simd_max(rgb, SIMD3<Float>(repeating: 0)), lumaWeights)
        let w = toneZoneWeights(luma: luma)

        let slope = blendSOP(params, weights: w) { zone in
            SIMD3<Float>(zone.luma.slope * zone.red.slope,
                         zone.luma.slope * zone.green.slope,
                         zone.luma.slope * zone.blue.slope)
        }
        let offset = blendSOP(params, weights: w) { zone in
            SIMD3<Float>(zone.luma.offset + zone.red.offset,
                         zone.luma.offset + zone.green.offset,
                         zone.luma.offset + zone.blue.offset)
        }
        let power = blendSOP(params, weights: w) { zone in
            SIMD3<Float>(zone.luma.power * zone.red.power,
                         zone.luma.power * zone.green.power,
                         zone.luma.power * zone.blue.power)
        }
        let sat = w.x * params.shadows.saturation
                + w.y * params.midtones.saturation
                + w.z * params.highlights.saturation

        // ASC CDL: out = clamp(in * slope + offset, 0, +inf)^power
        let lifted = simd_max(rgb * slope + offset, SIMD3<Float>(repeating: 0))
        let safePower = simd_max(power, SIMD3<Float>(repeating: 1e-6))
        var graded = SIMD3<Float>(pow(lifted.x, safePower.x),
                                  pow(lifted.y, safePower.y),
                                  pow(lifted.z, safePower.z))

        // Saturation around the post-grade luma (preserves brightness).
        let newLuma = simd_dot(graded, lumaWeights)
        let mono = SIMD3<Float>(repeating: newLuma)
        graded = mono + sat * (graded - mono)
        return graded
    }

    private static func blendSOP(_ p: CDLParameters,
                                 weights w: SIMD3<Float>,
                                 _ extract: (CDLZone) -> SIMD3<Float>) -> SIMD3<Float> {
        return extract(p.shadows) * w.x + extract(p.midtones) * w.y + extract(p.highlights) * w.z
    }

    private static func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let denom = b - a
        if denom == 0 { return x < a ? 0 : 1 }
        let raw = (x - a) / denom
        let t = max(0, min(1, raw))
        return t * t * (3 - 2 * t)
    }
}

// MARK: - Metal-friendly flat layout

/// Tightly-packed CDL parameter buffer (matches CDL.metal layout).
/// 3 zones × (4 channels × 3 floats + 1 saturation) = 39 floats.
public struct CDLUniformBuffer {
    public var floats: [Float]

    public init(_ params: CDLParameters) {
        var buf: [Float] = []
        buf.reserveCapacity(39)
        for zone in [params.shadows, params.midtones, params.highlights] {
            for ch in [zone.luma, zone.red, zone.green, zone.blue] {
                buf.append(ch.slope)
                buf.append(ch.offset)
                buf.append(ch.power)
            }
            buf.append(zone.saturation)
        }
        self.floats = buf
    }
}
