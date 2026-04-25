import Foundation
import simd

public enum CineLogVariant: String, Codable, CaseIterable {
    case v1
    case v2
}

public protocol CineLogCurve {
    static var variant: CineLogVariant { get }
    static var dynamicRangeStops: Float { get }
    static func encode(_ linear: Float) -> Float
    static func decode(_ log: Float) -> Float
}

public enum CineLogV1: CineLogCurve {
    public static let variant: CineLogVariant = .v1
    public static let dynamicRangeStops: Float = 15.0

    static let a: Float = 5.555556
    static let b: Float = 0.052272
    static let c: Float = 0.247190
    static let d: Float = 0.385537
    static let e: Float = 5.367655
    static let f: Float = 0.092809
    static let cut: Float = 0.010591

    public static func encode(_ linear: Float) -> Float {
        if linear >= cut {
            return c * log10(a * linear + b) + d
        }
        return e * linear + f
    }

    public static func decode(_ log: Float) -> Float {
        let cutLog = e * cut + f
        if log >= cutLog {
            return (pow(10.0, (log - d) / c) - b) / a
        }
        return (log - f) / e
    }
}

public enum CineLogV2: CineLogCurve {
    public static let variant: CineLogVariant = .v2
    public static let dynamicRangeStops: Float = 17.0

    static let a: Float = 6.5
    static let b: Float = 0.055
    static let c: Float = 0.235
    static let d: Float = 0.39
    static let cut: Float = 0.01

    static let e: Float = (c * a) / ((a * cut + b) * Float(log(10.0)))
    static let f: Float = (c * log10(a * cut + b) + d) - e * cut

    public static func encode(_ linear: Float) -> Float {
        let safe = max(linear, -b / a + 1e-7)
        if linear >= cut {
            let core = c * log10(a * safe + b) + d
            let knee: Float = 0.95
            if core <= knee { return core }
            let over = core - knee
            return knee + (1.0 - knee) * (1.0 - exp(-over / (1.0 - knee)))
        }
        return e * linear + f
    }

    public static func decode(_ log: Float) -> Float {
        let cutLog = e * cut + f
        let knee: Float = 0.95
        var coreLog = log
        if log > knee {
            let t = (log - knee) / (1.0 - knee)
            let clampedT = min(t, 0.999999)
            coreLog = knee - (1.0 - knee) * Float(log1p(-Double(clampedT)))
        }
        if coreLog >= cutLog {
            return (pow(10.0, (coreLog - d) / c) - b) / a
        }
        return (coreLog - f) / e
    }
}

public struct CineLog {
    public static func encode(_ rgb: SIMD3<Float>, variant: CineLogVariant) -> SIMD3<Float> {
        switch variant {
        case .v1: return SIMD3(CineLogV1.encode(rgb.x), CineLogV1.encode(rgb.y), CineLogV1.encode(rgb.z))
        case .v2: return SIMD3(CineLogV2.encode(rgb.x), CineLogV2.encode(rgb.y), CineLogV2.encode(rgb.z))
        }
    }

    public static func decode(_ rgb: SIMD3<Float>, variant: CineLogVariant) -> SIMD3<Float> {
        switch variant {
        case .v1: return SIMD3(CineLogV1.decode(rgb.x), CineLogV1.decode(rgb.y), CineLogV1.decode(rgb.z))
        case .v2: return SIMD3(CineLogV2.decode(rgb.x), CineLogV2.decode(rgb.y), CineLogV2.decode(rgb.z))
        }
    }
}
