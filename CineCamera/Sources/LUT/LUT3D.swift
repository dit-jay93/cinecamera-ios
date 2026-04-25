import Foundation
import simd

public enum LUTInterpolation: String, Codable, CaseIterable {
    case trilinear
    case tetrahedral
}

public enum LUTError: Error, Equatable {
    case invalidSize(Int)
    case parseFailure(String)
    case dataCountMismatch(expected: Int, got: Int)
    case unsupportedFormat(String)
}

/// Immutable 3D LUT in [0,1]^3 input domain (after domain remap).
/// Storage order: R varies fastest, then G, then B (matches .cube spec).
public struct LUT3D: Equatable {
    public let size: Int
    public let title: String?
    public let domainMin: SIMD3<Float>
    public let domainMax: SIMD3<Float>
    public let data: [SIMD3<Float>]

    public init(size: Int,
                data: [SIMD3<Float>],
                title: String? = nil,
                domainMin: SIMD3<Float> = SIMD3(0, 0, 0),
                domainMax: SIMD3<Float> = SIMD3(1, 1, 1)) throws {
        guard size >= 2 else { throw LUTError.invalidSize(size) }
        let expected = size * size * size
        guard data.count == expected else {
            throw LUTError.dataCountMismatch(expected: expected, got: data.count)
        }
        self.size = size
        self.data = data
        self.title = title
        self.domainMin = domainMin
        self.domainMax = domainMax
    }

    /// Identity LUT — input == output.
    public static func identity(size: Int = 33) -> LUT3D {
        let n = size * size * size
        var data = [SIMD3<Float>](repeating: .zero, count: n)
        let denom = Float(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let idx = r + g * size + b * size * size
                    data[idx] = SIMD3(Float(r) / denom, Float(g) / denom, Float(b) / denom)
                }
            }
        }
        return try! LUT3D(size: size, data: data, title: "Identity")
    }

    @inlinable
    public func index(r: Int, g: Int, b: Int) -> Int {
        return r + g * size + b * size * size
    }

    /// Sample the LUT at the given input. Domain-remapped to [0,1]^3 first.
    public func sample(_ input: SIMD3<Float>, mode: LUTInterpolation = .trilinear) -> SIMD3<Float> {
        let normalized = remapToUnit(input)
        switch mode {
        case .trilinear:  return trilinear(normalized)
        case .tetrahedral: return tetrahedral(normalized)
        }
    }

    @inlinable
    func remapToUnit(_ input: SIMD3<Float>) -> SIMD3<Float> {
        let span = domainMax - domainMin
        let safeSpan = SIMD3(span.x == 0 ? 1 : span.x,
                             span.y == 0 ? 1 : span.y,
                             span.z == 0 ? 1 : span.z)
        let t = (input - domainMin) / safeSpan
        return simd_clamp(t, SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 1))
    }

    @inline(__always)
    private func corner(_ ri: Int, _ gi: Int, _ bi: Int) -> SIMD3<Float> {
        return data[index(r: ri, g: gi, b: bi)]
    }

    private func trilinear(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        let scaled = rgb * Float(size - 1)
        let i0 = SIMD3<Int>(Int(floor(scaled.x)), Int(floor(scaled.y)), Int(floor(scaled.z)))
        let max = size - 1
        let r0 = min(i0.x, max - 1).clamped(min: 0)
        let g0 = min(i0.y, max - 1).clamped(min: 0)
        let b0 = min(i0.z, max - 1).clamped(min: 0)
        let r1 = r0 + 1; let g1 = g0 + 1; let b1 = b0 + 1
        let f = scaled - SIMD3<Float>(Float(r0), Float(g0), Float(b0))

        let c000 = corner(r0, g0, b0)
        let c100 = corner(r1, g0, b0)
        let c010 = corner(r0, g1, b0)
        let c110 = corner(r1, g1, b0)
        let c001 = corner(r0, g0, b1)
        let c101 = corner(r1, g0, b1)
        let c011 = corner(r0, g1, b1)
        let c111 = corner(r1, g1, b1)

        let c00 = mix(c000, c100, t: f.x)
        let c10 = mix(c010, c110, t: f.x)
        let c01 = mix(c001, c101, t: f.x)
        let c11 = mix(c011, c111, t: f.x)
        let c0 = mix(c00, c10, t: f.y)
        let c1 = mix(c01, c11, t: f.y)
        return mix(c0, c1, t: f.z)
    }

    private func tetrahedral(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        let scaled = rgb * Float(size - 1)
        let max = size - 1
        let r0 = min(Int(floor(scaled.x)), max - 1).clamped(min: 0)
        let g0 = min(Int(floor(scaled.y)), max - 1).clamped(min: 0)
        let b0 = min(Int(floor(scaled.z)), max - 1).clamped(min: 0)
        let r1 = r0 + 1; let g1 = g0 + 1; let b1 = b0 + 1
        let f = scaled - SIMD3<Float>(Float(r0), Float(g0), Float(b0))
        let a = f.x; let b = f.y; let c = f.z

        let p000 = corner(r0, g0, b0)
        let p111 = corner(r1, g1, b1)

        if a > b && b > c {
            let p100 = corner(r1, g0, b0)
            let p110 = corner(r1, g1, b0)
            return (1 - a) * p000 + (a - b) * p100 + (b - c) * p110 + c * p111
        } else if a > c && c >= b {
            let p100 = corner(r1, g0, b0)
            let p101 = corner(r1, g0, b1)
            return (1 - a) * p000 + (a - c) * p100 + (c - b) * p101 + b * p111
        } else if c > a && a >= b {
            let p001 = corner(r0, g0, b1)
            let p101 = corner(r1, g0, b1)
            return (1 - c) * p000 + (c - a) * p001 + (a - b) * p101 + b * p111
        } else if b >= a && a > c {
            let p010 = corner(r0, g1, b0)
            let p110 = corner(r1, g1, b0)
            return (1 - b) * p000 + (b - a) * p010 + (a - c) * p110 + c * p111
        } else if b >= c && c >= a {
            let p010 = corner(r0, g1, b0)
            let p011 = corner(r0, g1, b1)
            return (1 - b) * p000 + (b - c) * p010 + (c - a) * p011 + a * p111
        } else {
            let p001 = corner(r0, g0, b1)
            let p011 = corner(r0, g1, b1)
            return (1 - c) * p000 + (c - b) * p001 + (b - a) * p011 + a * p111
        }
    }

    /// Mix LUT output with the original input. amount=0 → identity, amount=1 → full LUT.
    public func sampleMixed(_ input: SIMD3<Float>,
                            mode: LUTInterpolation = .trilinear,
                            amount: Float) -> SIMD3<Float> {
        let lut = sample(input, mode: mode)
        let t = max(0, min(1, amount))
        return mix(input, lut, t: t)
    }
}

@inline(__always)
private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
    return a * (1 - t) + b * t
}

private extension Int {
    func clamped(min lower: Int) -> Int { return Swift.max(self, lower) }
}
