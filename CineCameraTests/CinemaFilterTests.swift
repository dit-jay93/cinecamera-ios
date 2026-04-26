import XCTest
import simd
@testable import CinePipeline

final class CinemaFilterTests: XCTestCase {

    private func approx(_ a: SIMD3<Float>, _ b: SIMD3<Float>, accuracy: Float = 0.001) -> Bool {
        return abs(a.x - b.x) < accuracy && abs(a.y - b.y) < accuracy && abs(a.z - b.z) < accuracy
    }

    // 12 filters present, all unique IDs.
    func test_catalog() {
        XCTAssertEqual(CinemaFilters.all.count, 12)
        let ids = CinemaFilters.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // intensity = 0 must leave the input unchanged for every filter.
    func test_zeroIntensity_isPassthrough() {
        let rgb = SIMD3<Float>(0.4, 0.5, 0.6)
        for filter in CinemaFilters.all {
            let out = CinemaFilterEngine.applyPixel(rgb, filter: filter, intensity: 0)
            XCTAssertTrue(approx(out, rgb), "Filter \(filter.id) altered input at intensity=0")
        }
    }

    // 85B must drop blue significantly while preserving red.
    func test_wratten85B_attenuatesBlue() {
        let rgb = SIMD3<Float>(0.5, 0.5, 0.5)
        let out = CinemaFilterEngine.applyPixel(rgb, filter: CinemaFilters.wratten85B, intensity: 1.0)
        XCTAssertGreaterThan(out.x, out.z, "85B should preserve red over blue")
        XCTAssertLessThan(out.z, 0.25, "85B should strongly drop blue")
    }

    // 80A is the inverse: blue > red.
    func test_wratten80A_attenuatesRed() {
        let rgb = SIMD3<Float>(0.5, 0.5, 0.5)
        let out = CinemaFilterEngine.applyPixel(rgb, filter: CinemaFilters.wratten80A, intensity: 1.0)
        XCTAssertGreaterThan(out.z, out.x)
    }

    // IRND 0.6 must reduce all channels by ~2 stops (0.25× ± slight IR tweak).
    func test_irnd_isApprox2Stops() {
        let rgb = SIMD3<Float>(1, 1, 1)
        let out = CinemaFilterEngine.applyPixel(rgb, filter: CinemaFilters.irnd0_6, intensity: 1.0)
        for c in [out.x, out.y, out.z] {
            XCTAssertEqual(c, 0.245, accuracy: 0.02)
        }
    }

    // Coral 3 should warm a neutral midtone (red unchanged, blue reduced).
    func test_coral3_warmsNeutral() {
        let neutral = SIMD3<Float>(0.5, 0.5, 0.5)
        let out = CinemaFilterEngine.applyPixel(neutral, filter: CinemaFilters.coral3, intensity: 1.0)
        XCTAssertGreaterThanOrEqual(out.x, neutral.x * 0.99)
        XCTAssertLessThan(out.z, out.x)
    }

    // LowCon must lift blacks (black input no longer pure black).
    func test_lowCon_liftsBlacks() {
        let black = SIMD3<Float>(0, 0, 0)
        let out = CinemaFilterEngine.applyPixel(black, filter: CinemaFilters.lowCon, intensity: 1.0)
        XCTAssertGreaterThan(out.x, 0.02)
        XCTAssertGreaterThan(out.y, 0.02)
        XCTAssertGreaterThan(out.z, 0.02)
    }

    // LowCon must reduce saturation on a saturated input.
    func test_lowCon_desaturates() {
        let red = SIMD3<Float>(0.9, 0.1, 0.1)
        let out = CinemaFilterEngine.applyPixel(red, filter: CinemaFilters.lowCon, intensity: 1.0)
        let inSaturation = red.x - 0.5 * (red.y + red.z)
        let outSaturation = out.x - 0.5 * (out.y + out.z)
        XCTAssertLessThan(outSaturation, inSaturation)
    }

    // Diffusion ProMist 1 must reserve bloom for highlights only (threshold > 0).
    func test_proMist1_isHighlightOnly() {
        XCTAssertGreaterThan(CinemaFilters.proMist1.spatial.bloomThreshold, 0.0)
        XCTAssertEqual(CinemaFilters.blackProMist1.spatial.bloomThreshold, 0.0)
    }

    // Gaussian kernel must sum to ~1 and be symmetric.
    func test_gaussianKernel_isNormalizedAndSymmetric() {
        for r in [1, 3, 5, 8, 16] {
            let k = CinemaFilterEngine.gaussianKernel(radius: r)
            XCTAssertEqual(k.count, 2 * r + 1)
            let sum = k.reduce(0, +)
            XCTAssertEqual(sum, 1.0, accuracy: 1e-5)
            for i in 0..<r {
                XCTAssertEqual(k[i], k[2 * r - i], accuracy: 1e-6, "Kernel asymmetry at r=\(r), i=\(i)")
            }
        }
    }

    // Blur a flat tile — output must equal input (Gaussian preserves DC).
    func test_blur_preservesFlatTile() {
        let pixels = Array(repeating: SIMD3<Float>(0.4, 0.5, 0.6), count: 32 * 32)
        let blurred = CinemaFilterEngine.applySeparableGaussian(pixels, width: 32, height: 32, radius: 5)
        for v in blurred {
            XCTAssertEqual(v.x, 0.4, accuracy: 1e-4)
            XCTAssertEqual(v.y, 0.5, accuracy: 1e-4)
            XCTAssertEqual(v.z, 0.6, accuracy: 1e-4)
        }
    }

    // Blur a single bright pixel — energy must be conserved (sum unchanged).
    func test_blur_preservesEnergy() {
        var pixels = Array(repeating: SIMD3<Float>(0, 0, 0), count: 16 * 16)
        pixels[8 * 16 + 8] = SIMD3<Float>(1, 1, 1)
        let blurred = CinemaFilterEngine.applySeparableGaussian(pixels, width: 16, height: 16, radius: 3)
        let sum = blurred.reduce(SIMD3<Float>(0, 0, 0), +)
        XCTAssertEqual(sum.x, 1.0, accuracy: 0.05)
        XCTAssertEqual(sum.y, 1.0, accuracy: 0.05)
        XCTAssertEqual(sum.z, 1.0, accuracy: 0.05)
    }

    // Black ProMist must brighten a dim mid-gray tile (whole-frame bloom).
    func test_blackProMistBloom_brightensMidtones() {
        let mid = Array(repeating: SIMD3<Float>(0.5, 0.5, 0.5), count: 16 * 16)
        let out = CinemaFilterEngine.applyTile(mid, width: 16, height: 16,
                                               filter: CinemaFilters.blackProMist1, intensity: 1.0)
        // Pre-pixel transform reduces the midtone slightly; bloom adds it back and then some.
        // Confirm the average brightness exceeds the per-pixel-only path.
        let perPixelOnly = mid.map {
            CinemaFilterEngine.applyPixel($0, filter: CinemaFilters.blackProMist1, intensity: 1.0)
        }
        let avgBloom = out.reduce(SIMD3<Float>(0, 0, 0), +) / Float(out.count)
        let avgFlat  = perPixelOnly.reduce(SIMD3<Float>(0, 0, 0), +) / Float(perPixelOnly.count)
        XCTAssertGreaterThan(avgBloom.x, avgFlat.x)
    }

    // ProMist 1 (highlight-only bloom): a dark midtone tile must NOT bloom much.
    func test_proMistBloom_skipsShadowsAndMidtones() {
        let mid = Array(repeating: SIMD3<Float>(0.4, 0.4, 0.4), count: 16 * 16)
        let out = CinemaFilterEngine.applyTile(mid, width: 16, height: 16,
                                               filter: CinemaFilters.proMist1, intensity: 1.0)
        let perPixelOnly = mid.map {
            CinemaFilterEngine.applyPixel($0, filter: CinemaFilters.proMist1, intensity: 1.0)
        }
        // Outputs must be very close — no significant bloom under threshold.
        for i in 0..<out.count {
            XCTAssertEqual(out[i].x, perPixelOnly[i].x, accuracy: 1e-3)
        }
    }
}
