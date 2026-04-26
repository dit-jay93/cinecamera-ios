import XCTest
import simd
@testable import CinePipeline

final class FilmGrainEngineTests: XCTestCase {

    private func params(_ profile: FilmGrainProfile,
                        iso: Float = 800,
                        frame: Int = 0,
                        seed: UInt32 = 0x9E3779B9) -> FilmGrainParameters {
        return FilmGrainParameters(profile: profile, iso: iso, frame: frame, seed: seed)
    }

    // 8 profiles, all unique IDs.
    func test_profileCatalog() {
        XCTAssertEqual(FilmGrainProfiles.all.count, 8)
        let ids = FilmGrainProfiles.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // Same position + same params → same grain (deterministic).
    func test_grain_isDeterministic() {
        let p = params(FilmGrainProfiles.visionPrime, frame: 7)
        let a = FilmGrainEngine.sampleGrain(at: SIMD2(120, 200), params: p)
        let b = FilmGrainEngine.sampleGrain(at: SIMD2(120, 200), params: p)
        XCTAssertEqual(a, b)
    }

    // Different frames produce different grain (temporal).
    func test_grain_changesWithFrame() {
        let p0 = params(FilmGrainProfiles.classicNegative, frame: 0)
        let p1 = params(FilmGrainProfiles.classicNegative, frame: 1)
        let pos = SIMD2<Int>(50, 50)
        let g0 = FilmGrainEngine.sampleGrain(at: pos, params: p0)
        let g1 = FilmGrainEngine.sampleGrain(at: pos, params: p1)
        XCTAssertNotEqual(g0, g1)
    }

    // Different seeds produce different grain.
    func test_grain_changesWithSeed() {
        let p0 = params(FilmGrainProfiles.classicNegative, seed: 1)
        let p1 = params(FilmGrainProfiles.classicNegative, seed: 2)
        let pos = SIMD2<Int>(50, 50)
        XCTAssertNotEqual(FilmGrainEngine.sampleGrain(at: pos, params: p0),
                          FilmGrainEngine.sampleGrain(at: pos, params: p1))
    }

    // Monochrome films produce equal channel noise (modulo channel gain — which is 1,1,1 for B&W).
    func test_monochrome_hasMatchingChannels() {
        let p = params(FilmGrainProfiles.bw3200)
        let g = FilmGrainEngine.sampleGrain(at: SIMD2(10, 20), params: p)
        XCTAssertEqual(g.x, g.y, accuracy: 1e-6)
        XCTAssertEqual(g.y, g.z, accuracy: 1e-6)
    }

    // Color films produce non-equal channels at most pixels.
    func test_colorFilm_hasIndependentChannels() {
        let p = params(FilmGrainProfiles.visionNight)
        // sample several pixels and assert at least one shows clear channel divergence
        var sawDivergence = false
        for x in 0..<32 {
            let g = FilmGrainEngine.sampleGrain(at: SIMD2(x, 0), params: p)
            if abs(g.x - g.y) > 0.05 || abs(g.y - g.z) > 0.05 {
                sawDivergence = true; break
            }
        }
        XCTAssertTrue(sawDivergence)
    }

    // Cluster size: pixels within the same cluster cell must produce identical samples.
    func test_clusterSize_producesBlockyGrain() {
        let profile = FilmGrainProfiles.silentEra // size = 3.2
        let p = params(profile)
        // Pixels (0,0) and (1,1) should fall in the same cell (cell size > 1).
        let g0 = FilmGrainEngine.sampleGrain(at: SIMD2(0, 0), params: p)
        let g1 = FilmGrainEngine.sampleGrain(at: SIMD2(1, 1), params: p)
        XCTAssertEqual(g0, g1)
    }

    // ISO scaling: higher ISO produces larger amplitude on graded output.
    func test_iso_scalesIntensity() {
        let pos = SIMD2<Int>(100, 100)
        let baseRGB = SIMD3<Float>(0.2, 0.2, 0.2) // dark, in shadow zone
        let lowISO = params(FilmGrainProfiles.visionPrime, iso: 100)
        let highISO = params(FilmGrainProfiles.visionPrime, iso: 6400)
        let outLow = FilmGrainEngine.apply(baseRGB, at: pos, params: lowISO)
        let outHigh = FilmGrainEngine.apply(baseRGB, at: pos, params: highISO)
        let deltaLow = simd_length(outLow - baseRGB)
        let deltaHigh = simd_length(outHigh - baseRGB)
        XCTAssertGreaterThan(deltaHigh, deltaLow, "Higher ISO must produce stronger grain")
    }

    // Hurter-Driffield: shadows show grain more strongly than highlights.
    func test_shadowBias_strongerInShadows() {
        let pos = SIMD2<Int>(42, 42)
        let p = params(FilmGrainProfiles.classicNegative)
        let dark = SIMD3<Float>(0.05, 0.05, 0.05)
        let bright = SIMD3<Float>(0.95, 0.95, 0.95)
        let outDark = FilmGrainEngine.apply(dark, at: pos, params: p) - dark
        let outBright = FilmGrainEngine.apply(bright, at: pos, params: p) - bright
        XCTAssertGreaterThan(simd_length(outDark), simd_length(outBright))
    }

    // Identity case: with intensityMultiplier = 0, output equals input.
    func test_zeroIntensity_isPassthrough() {
        var p = params(FilmGrainProfiles.visionPrime)
        p.intensityMultiplier = 0
        let rgb = SIMD3<Float>(0.4, 0.5, 0.6)
        let out = FilmGrainEngine.apply(rgb, at: SIMD2(11, 22), params: p)
        XCTAssertEqual(out, rgb)
    }

    // Generated tile size matches request.
    func test_generateGrainTile_sizes() {
        let p = params(FilmGrainProfiles.visionPrime)
        let tile = FilmGrainEngine.generateGrainTile(width: 16, height: 9, params: p)
        XCTAssertEqual(tile.count, 16 * 9)
    }

    // Profile JSON round-trip.
    func test_profileJSONRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for profile in FilmGrainProfiles.all {
            let data = try encoder.encode(profile)
            let decoded = try decoder.decode(FilmGrainProfile.self, from: data)
            XCTAssertEqual(decoded, profile)
        }
    }

    // Mean of the noise distribution should be near zero across many samples.
    func test_noiseDistribution_meanNearZero() {
        let p = params(FilmGrainProfiles.classicNegative)
        let tile = FilmGrainEngine.generateGrainTile(width: 64, height: 64, params: p)
        var sum = SIMD3<Float>(0, 0, 0)
        for v in tile { sum += v }
        let mean = sum / Float(tile.count)
        XCTAssertLessThan(abs(mean.x), 0.1)
        XCTAssertLessThan(abs(mean.y), 0.1)
        XCTAssertLessThan(abs(mean.z), 0.1)
    }
}
