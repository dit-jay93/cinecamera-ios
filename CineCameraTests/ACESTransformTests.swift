import XCTest
import simd
@testable import CinePipeline

final class ACESTransformTests: XCTestCase {

    private func approxEqual(_ a: SIMD3<Float>, _ b: SIMD3<Float>, accuracy: Float = 0.001) -> Bool {
        return abs(a.x - b.x) < accuracy && abs(a.y - b.y) < accuracy && abs(a.z - b.z) < accuracy
    }

    // AP0 ↔ AP1 round-trip on 18% gray.
    func test_ap0_ap1_roundTrip_neutralGray() {
        let gray = SIMD3<Float>(0.18, 0.18, 0.18)
        let ap1 = ACESTransform.aces2065ToACEScg(gray)
        let back = ACESTransform.acescgToACES2065(ap1)
        XCTAssertTrue(approxEqual(back, gray, accuracy: 0.0005),
                      "AP0↔AP1 round-trip drift: \(back) vs \(gray)")
    }

    // AP0 ↔ AP1 round-trip on saturated primaries.
    func test_ap0_ap1_roundTrip_primaries() {
        for color in [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1)] {
            let ap1 = ACESTransform.aces2065ToACEScg(color)
            let back = ACESTransform.acescgToACES2065(ap1)
            XCTAssertTrue(approxEqual(back, color, accuracy: 0.001),
                          "Primary round-trip drift: \(back) vs \(color)")
        }
    }

    // ACEScct round-trip across legal range.
    func test_acescct_roundTrip() {
        for x: Float in [0.0, 0.001, 0.0078125, 0.05, 0.18, 0.45, 1.0, 4.0, 16.0] {
            let encoded = ACESTransform.acescctEncode(x)
            let decoded = ACESTransform.acescctDecode(encoded)
            XCTAssertEqual(decoded, x, accuracy: 0.001, "ACEScct round-trip failed at \(x)")
        }
    }

    // ACEScc round-trip on positive scene values.
    func test_acescc_roundTrip() {
        for x: Float in [0.001, 0.018, 0.18, 1.0, 16.0, 1024.0] {
            let encoded = ACESTransform.acesccEncode(x)
            let decoded = ACESTransform.acesccDecode(encoded)
            XCTAssertEqual(decoded, x, accuracy: max(0.001, x * 0.005),
                           "ACEScc round-trip failed at \(x): got \(decoded)")
        }
    }

    // IDT must preserve neutral white roughly (Apple Log linear neutral → AP0 neutral after IDT).
    func test_idt_neutralPreserved() {
        let neutral = SIMD3<Float>(1, 1, 1)
        let ap0 = ACESTransform.appleLogLinearToACES2065(neutral)
        // Channels should remain reasonably balanced (chromatic adaptation may shift slightly).
        let avg = (ap0.x + ap0.y + ap0.z) / 3.0
        XCTAssertEqual(ap0.x, avg, accuracy: 0.05)
        XCTAssertEqual(ap0.y, avg, accuracy: 0.05)
        XCTAssertEqual(ap0.z, avg, accuracy: 0.05)
        XCTAssertGreaterThan(avg, 0.7)
    }

    // ODT outputs must stay within [0,1] for moderate input values.
    func test_odt_clampsOutput() {
        for target in OutputTarget.allCases {
            let mid = SIMD3<Float>(0.18, 0.18, 0.18)
            let out = ACESTransform.odt(mid, target: target)
            XCTAssertGreaterThanOrEqual(out.x, 0)
            XCTAssertGreaterThanOrEqual(out.y, 0)
            XCTAssertGreaterThanOrEqual(out.z, 0)
            XCTAssertLessThanOrEqual(out.x, 1)
            XCTAssertLessThanOrEqual(out.y, 1)
            XCTAssertLessThanOrEqual(out.z, 1)
        }
    }

    // Black input must produce black output across all ODTs.
    func test_odt_blackPoint() {
        for target in OutputTarget.allCases {
            let out = ACESTransform.odt(SIMD3<Float>(0, 0, 0), target: target)
            XCTAssertEqual(out.x, 0, accuracy: 0.001)
            XCTAssertEqual(out.y, 0, accuracy: 0.001)
            XCTAssertEqual(out.z, 0, accuracy: 0.001)
        }
    }
}
