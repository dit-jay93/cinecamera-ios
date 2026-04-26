import XCTest
import simd
@testable import CinePipeline

final class ImageAnalysisTests: XCTestCase {

    // Solid 50% grey image → every column has all pixels in the same bin.
    func test_waveform_flatGrey() {
        let w = 8, h = 4
        let pixels = Array(repeating: SIMD3<Float>(0.5, 0.5, 0.5), count: w * h)
        let wf = WaveformAnalyzer.compute(pixels, width: w, height: h, bins: 256, channel: .luma)
        XCTAssertEqual(wf.columns, w)
        XCTAssertEqual(wf.bins, 256)

        // Total counts must equal total pixels.
        let total = wf.data.reduce(UInt32(0), &+)
        XCTAssertEqual(total, UInt32(w * h))

        // The bin for luma 0.5 is exactly 128 (round of 0.5 * 255 + 0.5).
        let expectedBin = Int(0.5 * 255.0 + 0.5)
        for column in 0..<w {
            XCTAssertEqual(wf.data[expectedBin * w + column], UInt32(h))
        }
    }

    // Histogram totals: total samples per channel must match pixel count.
    func test_histogram_totalCounts() {
        var pixels: [SIMD3<Float>] = []
        for i in 0..<100 {
            let v = Float(i) / 99.0
            pixels.append(SIMD3<Float>(v, v, v))
        }
        let hist = HistogramAnalyzer.compute(pixels, bins: 64)
        XCTAssertEqual(hist.bins, 64)
        XCTAssertEqual(hist.red.reduce(0, +),   UInt32(pixels.count))
        XCTAssertEqual(hist.green.reduce(0, +), UInt32(pixels.count))
        XCTAssertEqual(hist.blue.reduce(0, +),  UInt32(pixels.count))
        XCTAssertEqual(hist.luma.reduce(0, +),  UInt32(pixels.count))
    }

    // Pure red image → all R energy in last bin, all G/B in first bin.
    func test_histogram_pureRed() {
        let pixels = Array(repeating: SIMD3<Float>(1, 0, 0), count: 256)
        let hist = HistogramAnalyzer.compute(pixels, bins: 256)
        XCTAssertEqual(hist.red[255], 256)
        XCTAssertEqual(hist.green[0], 256)
        XCTAssertEqual(hist.blue[0],  256)
    }

    // channel(_:) must round-trip to the right array.
    func test_histogram_channelLookup() {
        let pixels = [SIMD3<Float>(0.1, 0.2, 0.3)]
        let hist = HistogramAnalyzer.compute(pixels, bins: 16)
        XCTAssertEqual(hist.channel(.red),   hist.red)
        XCTAssertEqual(hist.channel(.green), hist.green)
        XCTAssertEqual(hist.channel(.blue),  hist.blue)
        XCTAssertEqual(hist.channel(.luma),  hist.luma)
    }

    // Vectorscope: total counts == pixel count.
    func test_vectorscope_totalCounts() {
        let pixels = (0..<400).map { _ in
            SIMD3<Float>(Float.random(in: 0...1),
                          Float.random(in: 0...1),
                          Float.random(in: 0...1))
        }
        let vs = VectorscopeAnalyzer.compute(pixels, bins: 32)
        XCTAssertEqual(vs.bins, 32)
        XCTAssertEqual(vs.counts.count, 32 * 32)
        XCTAssertEqual(vs.counts.reduce(UInt32(0), &+), UInt32(pixels.count))
    }

    // Neutral grey lands at the centre of the vectorscope grid (Cb=Cr=0).
    func test_vectorscope_neutralAtCenter() {
        let pixels = Array(repeating: SIMD3<Float>(0.5, 0.5, 0.5), count: 100)
        let vs = VectorscopeAnalyzer.compute(pixels, bins: 64)
        let centerX = 32, centerY = 32   // bins/2
        XCTAssertEqual(vs.counts[centerY * 64 + centerX], 100)
    }
}
