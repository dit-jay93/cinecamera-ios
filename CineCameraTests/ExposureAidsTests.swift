import XCTest
import simd
@testable import CinePipeline

final class ExposureAidsTests: XCTestCase {

    // Zebra: bright pixels are flagged, dim ones are not.
    func test_zebra_flagsBrightPixels() {
        var pixels = Array(repeating: SIMD3<Float>(0.4, 0.4, 0.4), count: 4 * 4)
        pixels[0] = SIMD3<Float>(1, 1, 1)
        pixels[5] = SIMD3<Float>(0.99, 0.99, 0.99)
        let mask = ZebraDetector.mask(pixels, width: 4, height: 4, threshold: 0.95)
        XCTAssertEqual(mask[0], 1.0)
        XCTAssertEqual(mask[5], 1.0)
        XCTAssertEqual(mask[1], 0.0)
    }

    // Striped variant: only stripes inside hot pixels are 1.0.
    func test_zebra_stripedSubsetOfFullMask() {
        let pixels = Array(repeating: SIMD3<Float>(1, 1, 1), count: 16 * 16)
        let full = ZebraDetector.mask(pixels, width: 16, height: 16, threshold: 0.95)
        let striped = ZebraDetector.stripedMask(pixels, width: 16, height: 16,
                                                 threshold: 0.95, stripePeriod: 8)
        let fullSum = full.reduce(0, +)
        let stripedSum = striped.reduce(0, +)
        XCTAssertGreaterThan(stripedSum, 0)
        XCTAssertLessThan(stripedSum, fullSum)
        XCTAssertEqual(stripedSum, fullSum * 0.5, accuracy: 1.0)
    }

    // Focus peaking: a high-contrast edge must be flagged inside the image,
    // and a flat region must not be.
    func test_focusPeaking_detectsEdge() {
        let w = 16, h = 16
        var pixels = Array(repeating: SIMD3<Float>(0, 0, 0), count: w * h)
        for y in 0..<h {
            for x in (w / 2)..<w {
                pixels[y * w + x] = SIMD3<Float>(1, 1, 1)
            }
        }
        let mask = FocusPeaking.mask(pixels, width: w, height: h, threshold: 0.5)
        // Pixels right next to the seam (x = w/2 - 1, x = w/2) should peak.
        XCTAssertEqual(mask[8 * w + (w / 2 - 1)], 1.0)
        // Far interior on either side should NOT peak.
        XCTAssertEqual(mask[8 * w + 1], 0.0)
        XCTAssertEqual(mask[8 * w + (w - 2)], 0.0)
    }

    // Gradient on a flat tile must be zero everywhere.
    func test_focusPeaking_flatTileHasZeroGradient() {
        let pixels = Array(repeating: SIMD3<Float>(0.5, 0.5, 0.5), count: 8 * 8)
        let g = FocusPeaking.gradient(pixels, width: 8, height: 8)
        for v in g { XCTAssertEqual(v, 0, accuracy: 1e-5) }
    }

    // FalseColor: middle-grey luma maps to grey output, clipped to white.
    func test_falseColor_zoneAssignment() {
        XCTAssertEqual(FalseColor.colorFor(luma: 0.0).x, 0.50, accuracy: 1e-5)  // purple
        XCTAssertEqual(FalseColor.colorFor(luma: 0.10).z, 0.90, accuracy: 1e-5) // blue
        XCTAssertEqual(FalseColor.colorFor(luma: 0.50).x, 0.50, accuracy: 1e-5) // grey
        XCTAssertEqual(FalseColor.colorFor(luma: 0.97).x, 0.95, accuracy: 1e-5) // red
        let clipped = FalseColor.colorFor(luma: 1.5)
        XCTAssertEqual(clipped, SIMD3<Float>(1, 1, 1))
    }

    // Map preserves pixel count.
    func test_falseColor_lengthMatchesInput() {
        let pixels = Array(repeating: SIMD3<Float>(0.5, 0.5, 0.5), count: 25)
        let mapped = FalseColor.map(pixels)
        XCTAssertEqual(mapped.count, pixels.count)
    }
}
