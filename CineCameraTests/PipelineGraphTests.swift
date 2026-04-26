import XCTest
import simd
@testable import CinePipeline

final class PipelineGraphTests: XCTestCase {

    private func approx(_ a: SIMD3<Float>, _ b: SIMD3<Float>, accuracy: Float = 1e-4) -> Bool {
        return abs(a.x - b.x) < accuracy && abs(a.y - b.y) < accuracy && abs(a.z - b.z) < accuracy
    }

    // The empty graph leaves any input untouched.
    func test_identity_passthrough() {
        let g = PipelineGraph.identity
        XCTAssertTrue(g.isIdentity)
        let rgb = SIMD3<Float>(0.4, 0.5, 0.6)
        XCTAssertTrue(approx(g.applyPixel(rgb), rgb))
    }

    // Per-pixel apply == per-tile apply for stages that have no spatial component.
    func test_pixelMatchesTile_forNonSpatialChain() {
        var graph = PipelineGraph()
        graph.whiteBalance = .init(targetKelvin: 4300, referenceKelvin: 6500, tint: 0)
        var cdl = CDLParameters.identity
        cdl.midtones.luma.slope = 1.1
        graph.cdl = cdl

        let pixels = (0..<64).map { _ in SIMD3<Float>(0.4, 0.5, 0.6) }
        let tiled = graph.applyTile(pixels, width: 8, height: 8)
        for i in 0..<pixels.count {
            let viaPixel = graph.applyPixel(pixels[i],
                                             position: SIMD2<Int>(i % 8, i / 8),
                                             frame: 0)
            XCTAssertTrue(approx(tiled[i], viaPixel),
                          "tile vs pixel diverged at i=\(i): tile=\(tiled[i]) pix=\(viaPixel)")
        }
    }

    // Stage ordering: WB applies before CDL. Reverse-engineered by checking
    // that WB-only output × CDL == full pipeline output.
    func test_stageOrder_wbThenCdl() {
        var graph = PipelineGraph()
        graph.whiteBalance = .init(targetKelvin: 3200)
        var cdl = CDLParameters.identity
        cdl.midtones.luma.slope = 0.8
        graph.cdl = cdl

        let rgb = SIMD3<Float>(0.5, 0.5, 0.5)
        let full = graph.applyPixel(rgb)
        let wbOnly = WhiteBalance.apply(rgb, targetKelvin: 3200)
        let manual = CDLEngine.apply(wbOnly, params: cdl)
        XCTAssertTrue(approx(full, manual, accuracy: 1e-4))
    }

    // LUT amount = 0 → no change. amount = 1 → full LUT mapping.
    func test_lutAmount_blendsCorrectly() throws {
        let identity = LUT3D.identity(size: 17)
        var graph = PipelineGraph()
        graph.lut = .init(lut: identity, amount: 1.0, interpolation: .trilinear)

        let rgb = SIMD3<Float>(0.42, 0.13, 0.77)
        XCTAssertTrue(approx(graph.applyPixel(rgb), rgb, accuracy: 1e-3))

        // amount = 0 still passes through (identity LUT mixed at 0 == input)
        graph.lut?.amount = 0
        XCTAssertTrue(approx(graph.applyPixel(rgb), rgb, accuracy: 1e-4))
    }

    // Filter intensity = 0 leaves the pixel untouched even if a filter is set.
    func test_filterStage_zeroIntensityIsPassthrough() {
        var graph = PipelineGraph()
        graph.filter = .init(filter: CinemaFilters.wratten85B, intensity: 0)
        let rgb = SIMD3<Float>(0.4, 0.5, 0.6)
        XCTAssertTrue(approx(graph.applyPixel(rgb), rgb))
    }

    // Per-tile bloom from cinema filter must brighten a midtone tile under
    // BlackProMist (whole-frame bloom).
    func test_perTile_bloomActsAcrossPixels() {
        var graph = PipelineGraph()
        graph.filter = .init(filter: CinemaFilters.blackProMist1, intensity: 1.0)
        let mid = Array(repeating: SIMD3<Float>(0.5, 0.5, 0.5), count: 16 * 16)
        let tiled = graph.applyTile(mid, width: 16, height: 16)
        // applyPixel skips bloom; tile output average must exceed it.
        let perPixel = mid.map { graph.applyPixel($0) }
        let avgTile = tiled.reduce(SIMD3<Float>(0, 0, 0), +) / Float(tiled.count)
        let avgPix  = perPixel.reduce(SIMD3<Float>(0, 0, 0), +) / Float(perPixel.count)
        XCTAssertGreaterThan(avgTile.x, avgPix.x)
    }

    // Codable round-trip: WB / CDL / grain / filter survive JSON;
    // LUT is intentionally dropped (looks reference LUTs by id).
    func test_codable_roundTrip() throws {
        var graph = PipelineGraph()
        graph.whiteBalance = .init(targetKelvin: 4300, tint: 18)
        var cdl = CDLParameters.identity
        cdl.shadows.luma.offset = -0.04
        cdl.highlights.red.power = 1.1
        graph.cdl = cdl
        graph.grain = .init(profile: FilmGrainProfiles.classicNegative,
                            iso: 1600, intensityMultiplier: 0.7, seed: 12345)
        graph.filter = .init(filter: CinemaFilters.proMist1, intensity: 0.6)

        let identity = LUT3D.identity(size: 9)
        graph.lut = .init(lut: identity, amount: 0.5, interpolation: .tetrahedral)

        let json = try JSONEncoder().encode(graph)
        let decoded = try JSONDecoder().decode(PipelineGraph.self, from: json)

        XCTAssertEqual(decoded.whiteBalance, graph.whiteBalance)
        XCTAssertEqual(decoded.cdl, graph.cdl)
        XCTAssertEqual(decoded.grain, graph.grain)
        XCTAssertEqual(decoded.filter, graph.filter)
        XCTAssertNil(decoded.lut, "LUT mesh should not survive JSON round-trip")

        // The reference handle survives via a separate accessor.
        let ref = graph.lutReference(id: "look.identity")
        XCTAssertEqual(ref?.amount, 0.5)
        XCTAssertEqual(ref?.interpolation, .tetrahedral)
    }

    // isIdentity flips off when any meaningful stage is configured.
    func test_isIdentity_detectsAnyActiveStage() {
        var g = PipelineGraph()
        XCTAssertTrue(g.isIdentity)
        g.whiteBalance = .init(targetKelvin: 6500)   // identity (==reference)
        XCTAssertTrue(g.isIdentity)
        g.whiteBalance = .init(targetKelvin: 3200)
        XCTAssertFalse(g.isIdentity)
        g.whiteBalance = nil
        var cdl = CDLParameters.identity
        cdl.midtones.luma.slope = 1.05
        g.cdl = cdl
        XCTAssertFalse(g.isIdentity)
    }

    // The same frame index must produce a deterministic grain pattern.
    func test_grain_deterministicForSameFrame() {
        var g = PipelineGraph()
        g.grain = .init(profile: FilmGrainProfiles.classicNegative,
                        iso: 800, intensityMultiplier: 1.0, seed: 0xABCD1234)
        let rgb = SIMD3<Float>(0.5, 0.5, 0.5)
        let a = g.applyPixel(rgb, position: SIMD2<Int>(7, 11), frame: 42)
        let b = g.applyPixel(rgb, position: SIMD2<Int>(7, 11), frame: 42)
        XCTAssertTrue(approx(a, b, accuracy: 1e-6))
    }
}
