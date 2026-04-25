import XCTest
@testable import CinePipeline

final class CineLogCurveTests: XCTestCase {

    // 18% gray must map to ~0.38–0.42 per spec.
    func test_v1_middleGrayMapping() {
        let y = CineLogV1.encode(0.18)
        XCTAssertGreaterThan(y, 0.38, "V1: 18% gray below lower bound (\(y))")
        XCTAssertLessThan(y, 0.42, "V1: 18% gray above upper bound (\(y))")
    }

    func test_v2_middleGrayMapping() {
        let y = CineLogV2.encode(0.18)
        XCTAssertGreaterThan(y, 0.38, "V2: 18% gray below lower bound (\(y))")
        XCTAssertLessThan(y, 0.42, "V2: 18% gray above upper bound (\(y))")
    }

    // encode/decode round-trip for representative scene values.
    func test_v1_roundTrip() {
        for x: Float in [0.0, 0.005, 0.018, 0.18, 0.45, 0.9] {
            let back = CineLogV1.decode(CineLogV1.encode(x))
            XCTAssertEqual(back, x, accuracy: 0.0005, "V1 round-trip failed at \(x): got \(back)")
        }
    }

    func test_v2_roundTrip() {
        for x: Float in [0.0, 0.005, 0.018, 0.18, 0.45, 0.9] {
            let back = CineLogV2.decode(CineLogV2.encode(x))
            XCTAssertEqual(back, x, accuracy: 0.001, "V2 round-trip failed at \(x): got \(back)")
        }
    }

    // 0.0 linear must remain bounded (no NaN/Inf).
    func test_v1_zeroIsFinite() {
        let y = CineLogV1.encode(0)
        XCTAssertTrue(y.isFinite)
        XCTAssertEqual(y, CineLogV1.f, accuracy: 1e-6)
    }

    func test_v2_zeroIsFinite() {
        let y = CineLogV2.encode(0)
        XCTAssertTrue(y.isFinite)
    }

    // V2 must compress highlights more than V1 (greater DR via knee).
    func test_v2_highlightCompression() {
        let highlightLinear: Float = 30.0
        let v1 = CineLogV1.encode(highlightLinear)
        let v2 = CineLogV2.encode(highlightLinear)
        XCTAssertLessThanOrEqual(v2, 1.0)
        XCTAssertGreaterThan(v2, 0.85, "V2 highlight should sit above the knee")
        XCTAssertGreaterThan(v1, 0.0)
    }

    // Monotonicity — encoding must be non-decreasing in linear input.
    func test_monotonic() {
        var lastV1: Float = -.infinity
        var lastV2: Float = -.infinity
        var x: Float = 0.0
        while x <= 5.0 {
            let v1 = CineLogV1.encode(x)
            let v2 = CineLogV2.encode(x)
            XCTAssertGreaterThanOrEqual(v1, lastV1)
            XCTAssertGreaterThanOrEqual(v2, lastV2)
            lastV1 = v1
            lastV2 = v2
            x += 0.05
        }
    }
}
