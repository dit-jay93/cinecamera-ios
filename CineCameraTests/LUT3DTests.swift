import XCTest
import simd
@testable import CinePipeline

final class LUT3DTests: XCTestCase {

    private func approx(_ a: SIMD3<Float>, _ b: SIMD3<Float>, accuracy: Float = 0.001) -> Bool {
        return abs(a.x - b.x) < accuracy && abs(a.y - b.y) < accuracy && abs(a.z - b.z) < accuracy
    }

    // Identity LUT preserves any input.
    func test_identity_passthrough() {
        let lut = LUT3D.identity(size: 33)
        for input in [SIMD3<Float>(0, 0, 0),
                      SIMD3<Float>(0.18, 0.45, 0.9),
                      SIMD3<Float>(1, 1, 1),
                      SIMD3<Float>(0.5, 0.5, 0.5)] {
            let trilin = lut.sample(input, mode: .trilinear)
            let tetra = lut.sample(input, mode: .tetrahedral)
            XCTAssertTrue(approx(trilin, input, accuracy: 1e-5),
                          "Trilinear identity drift at \(input): got \(trilin)")
            XCTAssertTrue(approx(tetra, input, accuracy: 1e-5),
                          "Tetrahedral identity drift at \(input): got \(tetra)")
        }
    }

    // Out-of-range inputs must clamp safely (no crash, no NaN).
    func test_outOfRange_clamps() {
        let lut = LUT3D.identity(size: 17)
        let out = lut.sample(SIMD3<Float>(-0.5, 1.7, 0.5), mode: .trilinear)
        XCTAssertEqual(out.x, 0, accuracy: 1e-5)
        XCTAssertEqual(out.y, 1, accuracy: 1e-5)
        XCTAssertEqual(out.z, 0.5, accuracy: 1e-5)
    }

    // Trilinear and tetrahedral must agree on grid points exactly.
    func test_interpolation_agreesAtGridPoints() {
        let lut = LUTBaker.bake(size: 17) { rgb in
            SIMD3<Float>(rgb.x * rgb.x, sqrt(rgb.y), rgb.z)
        }
        let denom: Float = 16.0
        for r in stride(from: 0, through: 16, by: 4) {
            for g in stride(from: 0, through: 16, by: 4) {
                for b in stride(from: 0, through: 16, by: 4) {
                    let p = SIMD3<Float>(Float(r) / denom, Float(g) / denom, Float(b) / denom)
                    let tri = lut.sample(p, mode: .trilinear)
                    let tet = lut.sample(p, mode: .tetrahedral)
                    XCTAssertTrue(approx(tri, tet, accuracy: 1e-4),
                                  "Grid mismatch at \(p): tri=\(tri) tet=\(tet)")
                }
            }
        }
    }

    // .cube round-trip via encode→parse must be lossless within float precision.
    func test_cube_roundTrip() throws {
        let lut = LUT3D.identity(size: 17)
        let text = LUTParser.encodeCube(lut)
        let parsed = try LUTParser.parseCube(text)
        XCTAssertEqual(parsed.size, lut.size)
        XCTAssertEqual(parsed.data.count, lut.data.count)
        for (a, b) in zip(lut.data, parsed.data) {
            XCTAssertTrue(approx(a, b, accuracy: 1e-5))
        }
    }

    // .cube parser handles TITLE, comments, blank lines, and DOMAIN_*.
    func test_cube_parserHandlesAllDirectives() throws {
        let text = """
        # comment line
        TITLE "Test LUT"

        LUT_3D_SIZE 2
        DOMAIN_MIN 0.0 0.0 0.0
        DOMAIN_MAX 1.0 1.0 1.0
        0.0 0.0 0.0
        1.0 0.0 0.0
        0.0 1.0 0.0
        1.0 1.0 0.0
        0.0 0.0 1.0
        1.0 0.0 1.0
        0.0 1.0 1.0
        1.0 1.0 1.0
        """
        let lut = try LUTParser.parseCube(text)
        XCTAssertEqual(lut.title, "Test LUT")
        XCTAssertEqual(lut.size, 2)
        XCTAssertEqual(lut.data.count, 8)
        XCTAssertEqual(lut.data[0], SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(lut.data[7], SIMD3<Float>(1, 1, 1))
    }

    // Wrong data count must throw with a precise mismatch error.
    func test_cube_parserDetectsCountMismatch() {
        let text = """
        LUT_3D_SIZE 2
        0.0 0.0 0.0
        1.0 0.0 0.0
        """
        XCTAssertThrowsError(try LUTParser.parseCube(text)) { error in
            guard case let LUTError.dataCountMismatch(expected, got) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(expected, 8)
            XCTAssertEqual(got, 2)
        }
    }

    // .3dl parser detects 10-bit depth and produces a normalized identity LUT.
    func test_3dl_parser10bit() throws {
        // Build a 2x2x2 identity .3dl in 10-bit (max=1023).
        var lines = ["0 1023"]
        for b in 0...1 {
            for g in 0...1 {
                for r in 0...1 {
                    lines.append("\(r * 1023) \(g * 1023) \(b * 1023)")
                }
            }
        }
        let lut = try LUTParser.parse3DL(lines.joined(separator: "\n"))
        XCTAssertEqual(lut.size, 2)
        XCTAssertEqual(lut.data[0], SIMD3<Float>(0, 0, 0))
        XCTAssertTrue(approx(lut.data[7], SIMD3<Float>(1, 1, 1), accuracy: 1e-5))
    }

    // Bake CDL identity → identity LUT.
    func test_baker_cdlIdentityProducesIdentityLUT() {
        let lut = LUTBaker.bake(cdl: .identity, size: 17, title: "Bake")
        let identity = LUT3D.identity(size: 17)
        XCTAssertEqual(lut.size, identity.size)
        for (a, b) in zip(lut.data, identity.data) {
            XCTAssertTrue(approx(a, b, accuracy: 1e-4))
        }
    }

    // Bake CDL preset, then sampling the LUT must match CDLEngine.apply at grid points.
    func test_baker_matchesCDLEngineAtGridPoints() {
        let preset = CDLPresets.tealAndOrange.parameters
        let lut = LUTBaker.bake(cdl: preset, size: 33)
        let denom: Float = 32.0
        for (r, g, b) in [(0, 0, 0), (16, 16, 16), (32, 32, 32), (24, 8, 16), (4, 28, 12)] {
            let input = SIMD3<Float>(Float(r) / denom, Float(g) / denom, Float(b) / denom)
            let viaLUT = lut.sample(input, mode: .trilinear)
            let direct = CDLEngine.apply(input, params: preset)
            XCTAssertTrue(approx(viaLUT, direct, accuracy: 1e-4),
                          "LUT vs direct mismatch at \(input): \(viaLUT) vs \(direct)")
        }
    }

    // sampleMixed at amount=0 returns input; amount=1 returns full LUT result.
    func test_sampleMixed_endpoints() {
        let lut = LUTBaker.bake(cdl: CDLPresets.sepia.parameters, size: 17)
        let input = SIMD3<Float>(0.5, 0.5, 0.5)
        let zero = lut.sampleMixed(input, amount: 0)
        let full = lut.sampleMixed(input, amount: 1)
        XCTAssertTrue(approx(zero, input, accuracy: 1e-5))
        XCTAssertTrue(approx(full, lut.sample(input), accuracy: 1e-5))
    }

    // Invalid size must throw.
    func test_invalidSize_throws() {
        XCTAssertThrowsError(try LUT3D(size: 1, data: [.zero]))
        XCTAssertThrowsError(try LUT3D(size: 2, data: [.zero, .zero])) { error in
            guard case .dataCountMismatch = error as? LUTError else {
                return XCTFail("Wrong error: \(error)")
            }
        }
    }
}
