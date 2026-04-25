import XCTest
import simd
@testable import CinePipeline

final class CDLEngineTests: XCTestCase {

    private func approxEqual(_ a: SIMD3<Float>, _ b: SIMD3<Float>, accuracy: Float = 0.0005) -> Bool {
        return abs(a.x - b.x) < accuracy && abs(a.y - b.y) < accuracy && abs(a.z - b.z) < accuracy
    }

    // Identity parameters must leave RGB untouched.
    func test_identity_isPassthrough() {
        let params = CDLParameters.identity
        for rgb in [SIMD3<Float>(0, 0, 0),
                    SIMD3<Float>(0.18, 0.18, 0.18),
                    SIMD3<Float>(0.7, 0.4, 0.1),
                    SIMD3<Float>(1, 1, 1)] {
            let out = CDLEngine.apply(rgb, params: params)
            XCTAssertTrue(approxEqual(out, rgb), "Identity drift at \(rgb): got \(out)")
        }
    }

    // Negative inputs must be clamped at zero before powering (no NaN).
    func test_negativeInputs_areFinite() {
        let params = CDLParameters(
            shadows: CDLZone(luma: CDLChannelSOP(slope: 1, offset: 0, power: 0.5)),
            midtones: .identity,
            highlights: .identity
        )
        let out = CDLEngine.apply(SIMD3<Float>(-0.1, -0.05, 0), params: params)
        XCTAssertTrue(out.x.isFinite && out.y.isFinite && out.z.isFinite)
    }

    // Tone-zone weights must sum to 1 across the luma range.
    func test_toneZoneWeights_sumToOne() {
        var luma: Float = 0
        while luma <= 1.0 {
            let w = CDLEngine.toneZoneWeights(luma: luma)
            XCTAssertEqual(w.x + w.y + w.z, 1.0, accuracy: 1e-5, "Weights sum != 1 at luma=\(luma)")
            XCTAssertGreaterThanOrEqual(w.x, 0); XCTAssertGreaterThanOrEqual(w.y, 0); XCTAssertGreaterThanOrEqual(w.z, 0)
            luma += 0.05
        }
    }

    // Endpoints: pure shadow → only shadow weight; pure highlight → only highlight.
    func test_toneZoneWeights_endpoints() {
        let s = CDLEngine.toneZoneWeights(luma: 0)
        XCTAssertEqual(s.x, 1, accuracy: 1e-5); XCTAssertEqual(s.y, 0, accuracy: 1e-5); XCTAssertEqual(s.z, 0, accuracy: 1e-5)
        let h = CDLEngine.toneZoneWeights(luma: 1)
        XCTAssertEqual(h.x, 0, accuracy: 1e-5); XCTAssertEqual(h.y, 0, accuracy: 1e-5); XCTAssertEqual(h.z, 1, accuracy: 1e-5)
        let m = CDLEngine.toneZoneWeights(luma: 0.5)
        XCTAssertEqual(m.y, 1, accuracy: 1e-5)
    }

    // Slope acts as a multiplier; verify at the midtone peak (luma=0.5).
    func test_slope_scalesMidtone() {
        let params = CDLParameters(
            shadows: .identity,
            midtones: CDLZone(red: CDLChannelSOP(slope: 2, offset: 0, power: 1)),
            highlights: .identity
        )
        let mid = SIMD3<Float>(0.5, 0.5, 0.5)
        let out = CDLEngine.apply(mid, params: params)
        // Midtone weight = 1.0 exactly at luma=0.5; R should roughly double.
        XCTAssertGreaterThan(out.x, mid.x * 1.5)
        XCTAssertEqual(out.y, mid.y, accuracy: 0.05)
        XCTAssertEqual(out.z, mid.z, accuracy: 0.05)
    }

    // Shadow zone slope must dominate at low luma (e.g., 0.18).
    func test_slope_scalesShadowAtLowLuma() {
        let params = CDLParameters(
            shadows: CDLZone(red: CDLChannelSOP(slope: 2, offset: 0, power: 1)),
            midtones: .identity,
            highlights: .identity
        )
        let dark = SIMD3<Float>(0.18, 0.18, 0.18)
        let out = CDLEngine.apply(dark, params: params)
        XCTAssertGreaterThan(out.x, dark.x * 1.5, "Shadow slope should dominate at luma=0.18")
    }

    // Saturation = 0 produces grayscale output.
    func test_zeroSaturation_isGrayscale() {
        let zone = CDLZone(saturation: 0)
        let params = CDLParameters(shadows: zone, midtones: zone, highlights: zone)
        let out = CDLEngine.apply(SIMD3<Float>(0.7, 0.3, 0.1), params: params)
        XCTAssertEqual(out.x, out.y, accuracy: 0.001)
        XCTAssertEqual(out.y, out.z, accuracy: 0.001)
    }

    // All 20 presets must round-trip through JSON encoding without loss.
    func test_allPresets_roundTripJSON() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        XCTAssertEqual(CDLPresets.all.count, 20, "Expected 20 presets, got \(CDLPresets.all.count)")
        for preset in CDLPresets.all {
            let data = try encoder.encode(preset.parameters)
            let decoded = try decoder.decode(CDLParameters.self, from: data)
            XCTAssertEqual(decoded, preset.parameters, "Round-trip failed for preset \(preset.id)")
        }
    }

    // Preset IDs must be unique.
    func test_presetIDs_areUnique() {
        let ids = CDLPresets.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // Identity preset must produce no visible change on a midtone.
    func test_identityPreset_noChange() {
        let mid = SIMD3<Float>(0.18, 0.18, 0.18)
        let out = CDLEngine.apply(mid, params: CDLPresets.identity.parameters)
        XCTAssertTrue(approxEqual(out, mid))
    }

    // Uniform buffer layout: 39 floats in the documented order.
    func test_uniformBuffer_layout() {
        let zone = CDLZone(
            luma:  CDLChannelSOP(slope: 1.1, offset: 0.01, power: 0.95),
            red:   CDLChannelSOP(slope: 1.2, offset: 0.02, power: 0.90),
            green: CDLChannelSOP(slope: 0.95, offset: -0.01, power: 1.05),
            blue:  CDLChannelSOP(slope: 0.85, offset: 0.03, power: 1.10),
            saturation: 1.15
        )
        let params = CDLParameters(shadows: zone, midtones: .identity, highlights: .identity)
        let buf = CDLUniformBuffer(params).floats
        XCTAssertEqual(buf.count, 39)
        XCTAssertEqual(buf[0], 1.1); XCTAssertEqual(buf[1], 0.01); XCTAssertEqual(buf[2], 0.95)
        XCTAssertEqual(buf[3], 1.2); XCTAssertEqual(buf[12], 1.15)
        XCTAssertEqual(buf[13], 1.0) // midtones luma slope = identity
        XCTAssertEqual(buf[26], 1.0) // midtones saturation = identity
    }

    // A noticeable preset (Sepia) must shift hue toward red/yellow on a neutral input.
    func test_sepia_shiftsTowardRed() {
        let neutral = SIMD3<Float>(0.5, 0.5, 0.5)
        let out = CDLEngine.apply(neutral, params: CDLPresets.sepia.parameters)
        XCTAssertGreaterThan(out.x, out.z, "Sepia should pull blue down relative to red")
        XCTAssertGreaterThan(out.x, out.y, "Sepia red should exceed green")
    }
}
