import XCTest
import simd
@testable import CinePipeline

#if canImport(Metal)
import Metal

final class MetalRendererTests: XCTestCase {

    private func skipIfNoGPU() throws -> MetalContext {
        guard let ctx = MetalContext.makeDefault() else {
            throw XCTSkip("No usable Metal device on this host (likely CI / headless macOS).")
        }
        return ctx
    }

    private func approx(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ tol: Float) -> Bool {
        return abs(a.x - b.x) <= tol && abs(a.y - b.y) <= tol && abs(a.z - b.z) <= tol
    }

    // MetalContext compiles every shipped .metal file and exposes them as
    // separate libraries (per-file, to avoid `kLumaWeights` collisions).
    func test_context_compilesAllShippedLibraries() throws {
        let ctx = try skipIfNoGPU()
        for name in MetalContext.kernelSources {
            XCTAssertNotNil(ctx.libraries[name], "Library missing for \(name)")
        }
    }

    // Pipeline lookup must find the CDL kernel and cache the result.
    func test_context_pipelineLookupCachesByName() throws {
        let ctx = try skipIfNoGPU()
        let p1 = try ctx.computePipeline(named: "cdlApplyKernel")
        let p2 = try ctx.computePipeline(named: "cdlApplyKernel")
        XCTAssertTrue(p1 === p2, "Pipeline cache returned a different instance")
    }

    // Unknown kernel name throws kernelMissing.
    func test_context_unknownKernelThrows() throws {
        let ctx = try skipIfNoGPU()
        XCTAssertThrowsError(try ctx.computePipeline(named: "thisKernelDoesNotExist")) { err in
            guard case MetalContextError.kernelMissing = err else {
                XCTFail("Expected kernelMissing, got \(err)")
                return
            }
        }
    }

    // MetalImageBuffer round-trips a small pixel array unchanged.
    func test_imageBuffer_roundTrip() throws {
        let ctx = try skipIfNoGPU()
        let pixels: [SIMD3<Float>] = [
            .init(0.10, 0.20, 0.30), .init(0.40, 0.50, 0.60),
            .init(0.70, 0.80, 0.90), .init(0.05, 0.95, 0.50),
            .init(1.00, 0.00, 0.00), .init(0.00, 1.00, 0.00)
        ]
        let tex = try MetalImageBuffer.makeTexture(device: ctx.device,
                                                    pixels: pixels,
                                                    width: 3, height: 2)
        let back = MetalImageBuffer.download(tex)
        XCTAssertEqual(back.count, pixels.count)
        for i in 0..<pixels.count {
            XCTAssertTrue(approx(back[i], pixels[i], 1e-6),
                          "Pixel \(i) differs: got \(back[i]), expected \(pixels[i])")
        }
    }

    // Dimension mismatch on upload throws.
    func test_imageBuffer_dimensionMismatchThrows() throws {
        let ctx = try skipIfNoGPU()
        XCTAssertThrowsError(
            try MetalImageBuffer.makeTexture(device: ctx.device,
                                              pixels: [.zero, .zero, .zero],
                                              width: 4, height: 4)
        )
    }

    // GPU CDL pass with identity parameters must equal the input within
    // float tolerance (it's still going through pow(x,1) etc.).
    func test_cdlPass_identityIsPassthrough() throws {
        let ctx = try skipIfNoGPU()
        let pass = try CDLPass(context: ctx)
        let pixels = stride(from: Float(0.0), through: 1.0, by: 0.05).flatMap { v -> [SIMD3<Float>] in
            [SIMD3<Float>(v, v * 0.5, 1 - v)]
        }
        let w = pixels.count, h = 1
        let out = try pass.apply(pixels: pixels, width: w, height: h,
                                  parameters: .identity)
        for i in 0..<pixels.count {
            XCTAssertTrue(approx(out[i], pixels[i], 1e-4),
                          "Identity CDL changed pixel \(i): \(out[i]) vs \(pixels[i])")
        }
    }

    // GPU CDL output must match CPU CDLEngine output for a non-trivial preset.
    func test_cdlPass_matchesCPU_forBleachBypass() throws {
        let ctx = try skipIfNoGPU()
        let pass = try CDLPass(context: ctx)
        let params = CDLPresets.bleachBypass.parameters

        // Build a 16×16 swatch of varied colors.
        var pixels: [SIMD3<Float>] = []
        for y in 0..<16 {
            for x in 0..<16 {
                let r = Float(x) / 15.0
                let g = Float(y) / 15.0
                let b = Float((x + y) % 16) / 15.0
                pixels.append(SIMD3<Float>(r, g, b))
            }
        }

        let gpuOut = try pass.apply(pixels: pixels, width: 16, height: 16, parameters: params)
        let cpuOut = pixels.map { CDLEngine.apply($0, params: params) }

        XCTAssertEqual(gpuOut.count, cpuOut.count)
        for i in 0..<pixels.count {
            XCTAssertTrue(approx(gpuOut[i], cpuOut[i], 5e-3),
                          "GPU/CPU CDL diverge at \(i): gpu=\(gpuOut[i]) cpu=\(cpuOut[i])")
        }
    }

    // Same parity check across all factory CDL presets, on a smaller grid
    // for speed. Catches per-zone or per-channel regressions.
    func test_cdlPass_matchesCPU_acrossAllPresets() throws {
        let ctx = try skipIfNoGPU()
        let pass = try CDLPass(context: ctx)

        let pixels: [SIMD3<Float>] = [
            .init(0.05, 0.05, 0.05),
            .init(0.18, 0.18, 0.18),
            .init(0.50, 0.50, 0.50),
            .init(0.85, 0.85, 0.85),
            .init(0.95, 0.20, 0.10),
            .init(0.10, 0.85, 0.30),
            .init(0.20, 0.30, 0.95),
            .init(0.50, 0.20, 0.80)
        ]

        for preset in CDLPresets.all {
            let gpuOut = try pass.apply(pixels: pixels, width: pixels.count, height: 1,
                                         parameters: preset.parameters)
            let cpuOut = pixels.map { CDLEngine.apply($0, params: preset.parameters) }
            for i in 0..<pixels.count {
                XCTAssertTrue(approx(gpuOut[i], cpuOut[i], 5e-3),
                              "Preset \(preset.name) diverges at pixel \(i): gpu=\(gpuOut[i]) cpu=\(cpuOut[i])")
            }
        }
    }
}

#endif
