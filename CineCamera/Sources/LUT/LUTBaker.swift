import Foundation
import simd

public enum LUTBaker {

    /// Bake a CDL grade into a 3D LUT. Each grid sample (r,g,b) ∈ [0,1]^3 is fed
    /// directly through `CDLEngine.apply` — i.e. the LUT operates in the same
    /// color space the CDL was authored for (typically ACEScg).
    public static func bake(cdl params: CDLParameters,
                            size: Int = 33,
                            title: String? = nil) -> LUT3D {
        let n = size
        let denom = Float(n - 1)
        var data = [SIMD3<Float>](repeating: .zero, count: n * n * n)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let input = SIMD3<Float>(Float(r) / denom, Float(g) / denom, Float(b) / denom)
                    let output = CDLEngine.apply(input, params: params)
                    data[r + g * n + b * n * n] = output
                }
            }
        }
        return try! LUT3D(size: n, data: data, title: title)
    }

    /// Bake an arbitrary closure into a LUT (for unit tests or custom transforms).
    public static func bake(size: Int = 33,
                            title: String? = nil,
                            transform: (SIMD3<Float>) -> SIMD3<Float>) -> LUT3D {
        let n = size
        let denom = Float(n - 1)
        var data = [SIMD3<Float>](repeating: .zero, count: n * n * n)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let input = SIMD3<Float>(Float(r) / denom, Float(g) / denom, Float(b) / denom)
                    data[r + g * n + b * n * n] = transform(input)
                }
            }
        }
        return try! LUT3D(size: n, data: data, title: title)
    }
}
