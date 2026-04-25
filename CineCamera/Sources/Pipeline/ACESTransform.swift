import Foundation
import simd

public enum OutputTarget: String, Codable, CaseIterable {
    case displayP3
    case rec709
    case rec2020
}

public enum ACESTransform {

    // MARK: - Reference Matrices (row-major in comments, column-major in code)

    /// Display P3 (D65 primaries) → XYZ (D65)
    public static let p3D65ToXYZ = simd_float3x3(columns: (
        SIMD3<Float>(0.4865709, 0.2289746, 0.0000000),
        SIMD3<Float>(0.2656677, 0.6917385, 0.0451134),
        SIMD3<Float>(0.1982173, 0.0792869, 1.0439444)
    ))

    /// XYZ (D65) → XYZ (D60), Bradford chromatic adaptation
    public static let bradfordD65ToD60 = simd_float3x3(columns: (
        SIMD3<Float>( 1.01278,  0.00768, -0.00284),
        SIMD3<Float>( 0.00607,  0.99816,  0.00468),
        SIMD3<Float>(-0.01497, -0.00503,  0.92450)
    ))

    /// XYZ (D60) → ACES2065-1 (AP0)
    public static let xyzD60ToAP0 = simd_float3x3(columns: (
        SIMD3<Float>( 1.0498110175, -0.4959030231,  0.0000000000),
        SIMD3<Float>( 0.0000000000,  1.3733130458,  0.0000000000),
        SIMD3<Float>(-0.0000974845,  0.0982400361,  0.9912520182)
    ))

    /// ACES2065-1 (AP0) → ACEScg (AP1)
    public static let ap0ToAP1 = simd_float3x3(columns: (
        SIMD3<Float>( 1.4514393161, -0.0765537734,  0.0083161484),
        SIMD3<Float>(-0.2365107469,  1.1762296998, -0.0060324498),
        SIMD3<Float>(-0.2149285693, -0.0996759264,  0.9977163014)
    ))

    /// ACEScg (AP1) → ACES2065-1 (AP0)
    public static let ap1ToAP0 = simd_float3x3(columns: (
        SIMD3<Float>( 0.6954522414,  0.0447945634, -0.0055258826),
        SIMD3<Float>( 0.1406786965,  0.8596711185,  0.0040252103),
        SIMD3<Float>( 0.1638690622,  0.0955343182,  1.0015006723)
    ))

    /// ACES (AP1) → XYZ (D60), used for ODT
    public static let ap1ToXYZ = simd_float3x3(columns: (
        SIMD3<Float>(0.6624541811, 0.2722287168, -0.0055746495),
        SIMD3<Float>(0.1340042065, 0.6740817658,  0.0040607335),
        SIMD3<Float>(0.1561876870, 0.0536895174,  1.0103391003)
    ))

    /// XYZ (D60) → XYZ (D65), Bradford CAT inverse
    public static let bradfordD60ToD65 = simd_float3x3(columns: (
        SIMD3<Float>( 0.987224,   -0.00759836,  0.00307257),
        SIMD3<Float>(-0.00611327,  1.00186,    -0.00509595),
        SIMD3<Float>( 0.0159533,   0.00533002,  1.08168)
    ))

    /// XYZ (D65) → Display P3
    public static let xyzToP3D65 = simd_float3x3(columns: (
        SIMD3<Float>( 2.4934969119, -0.8294889696,  0.0358458302),
        SIMD3<Float>(-0.9313836179,  1.7626640603, -0.0761723893),
        SIMD3<Float>(-0.4027107844,  0.0236246858,  0.9568845240)
    ))

    /// XYZ (D65) → Rec.709 (sRGB primaries)
    public static let xyzToRec709 = simd_float3x3(columns: (
        SIMD3<Float>( 3.2404542, -0.9692660,  0.0556434),
        SIMD3<Float>(-1.5371385,  1.8760108, -0.2040259),
        SIMD3<Float>(-0.4985314,  0.0415560,  1.0572252)
    ))

    /// XYZ (D65) → Rec.2020
    public static let xyzToRec2020 = simd_float3x3(columns: (
        SIMD3<Float>( 1.7166512, -0.6666844,  0.0176399),
        SIMD3<Float>(-0.3556708,  1.6164812, -0.0427706),
        SIMD3<Float>(-0.2533663,  0.0157685,  0.9421031)
    ))

    // MARK: - Composed IDT/ODT matrices

    /// IDT: Apple Log primaries (P3-D65) linear → ACES2065-1 (AP0).
    public static let appleLogLinearToAP0: simd_float3x3 = {
        return xyzD60ToAP0 * bradfordD65ToD60 * p3D65ToXYZ
    }()

    /// Inverse IDT: AP0 → P3-D65 linear
    public static let ap0ToAppleLogLinear: simd_float3x3 = {
        return appleLogLinearToAP0.inverse
    }()

    // MARK: - Color Space Conversions

    public static func appleLogLinearToACES2065(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        return appleLogLinearToAP0 * rgb
    }

    public static func aces2065ToACEScg(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        return ap0ToAP1 * rgb
    }

    public static func acescgToACES2065(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        return ap1ToAP0 * rgb
    }

    // MARK: - ACEScc / ACEScct Transfer Functions

    /// ACEScct encode (linear AP1 → ACEScct).
    public static func acescctEncode(_ x: Float) -> Float {
        let xBrk: Float = 0.0078125
        let a: Float = 10.5402377416545
        let b: Float = 0.0729055341958355
        if x <= xBrk {
            return a * x + b
        }
        return (log2(x) + 9.72) / 17.52
    }

    public static func acescctDecode(_ y: Float) -> Float {
        let yBrk: Float = 0.155251141552511
        let a: Float = 10.5402377416545
        let b: Float = 0.0729055341958355
        if y <= yBrk {
            return (y - b) / a
        }
        return pow(2.0, y * 17.52 - 9.72)
    }

    /// ACEScc encode (linear AP1 → ACEScc).
    public static func acesccEncode(_ x: Float) -> Float {
        if x <= 0 {
            return -0.3013698630 // (log2(2^-16) + 9.72) / 17.52
        }
        if x < 1.0 / 65536.0 {
            return (log2(1.0 / 65536.0 + x * 0.5) + 9.72) / 17.52
        }
        return (log2(x) + 9.72) / 17.52
    }

    public static func acesccDecode(_ y: Float) -> Float {
        let lo: Float = (-15.0 + 9.72) / 17.52 // ≈ -0.3014
        let hi: Float = (log2(65504.0) + 9.72) / 17.52
        if y < lo {
            return (pow(2.0, y * 17.52 - 9.72) - 1.0 / 65536.0) * 2.0
        }
        if y < hi {
            return pow(2.0, y * 17.52 - 9.72)
        }
        return 65504.0
    }

    // MARK: - Simplified RRT (polynomial approximation)

    /// Reference Rendering Transform — simplified ACES tonemap.
    /// Polynomial approximation of the ACES Filmic curve, in AP1 (ACEScg) space.
    public static func rrt(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        let a: Float = 2.51
        let b: Float = 0.03
        let c: Float = 2.43
        let d: Float = 0.59
        let e: Float = 0.14
        let num = rgb * (a * rgb + SIMD3<Float>(repeating: b))
        let den = rgb * (c * rgb + SIMD3<Float>(repeating: d)) + SIMD3<Float>(repeating: e)
        let result = num / den
        return simd_clamp(result, SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 1))
    }

    // MARK: - ODT (Output Display Transform)

    /// ACEScg (AP1) → display-encoded RGB (gamma-corrected) for the given target.
    public static func odt(_ acescg: SIMD3<Float>, target: OutputTarget) -> SIMD3<Float> {
        let toned = rrt(acescg)
        let xyz = bradfordD60ToD65 * (ap1ToXYZ * toned)
        let displayLinear: SIMD3<Float>
        switch target {
        case .displayP3: displayLinear = xyzToP3D65 * xyz
        case .rec709:    displayLinear = xyzToRec709 * xyz
        case .rec2020:   displayLinear = xyzToRec2020 * xyz
        }
        let clamped = simd_clamp(displayLinear, SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 1))
        switch target {
        case .displayP3, .rec709:
            return SIMD3<Float>(srgbEncode(clamped.x), srgbEncode(clamped.y), srgbEncode(clamped.z))
        case .rec2020:
            return SIMD3<Float>(rec2020Encode(clamped.x), rec2020Encode(clamped.y), rec2020Encode(clamped.z))
        }
    }

    private static func srgbEncode(_ x: Float) -> Float {
        if x <= 0.0031308 { return 12.92 * x }
        return 1.055 * pow(x, 1.0 / 2.4) - 0.055
    }

    private static func rec2020Encode(_ x: Float) -> Float {
        let alpha: Float = 1.09929682680944
        let beta: Float = 0.018053968510807
        if x < beta { return 4.5 * x }
        return alpha * pow(x, 0.45) - (alpha - 1.0)
    }
}
