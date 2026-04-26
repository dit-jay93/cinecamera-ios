import XCTest
import simd
@testable import CinePipeline

final class WhiteBalanceTests: XCTestCase {

    // 6500K (D65) gain ratio against itself must be ~1.0 on every channel.
    func test_d65_isIdentity() {
        let gains = WhiteBalance.gains(targetKelvin: 6500, referenceKelvin: 6500, tint: 0)
        XCTAssertEqual(gains.x, 1.0, accuracy: 0.02)
        XCTAssertEqual(gains.y, 1.0, accuracy: 0.02)
        XCTAssertEqual(gains.z, 1.0, accuracy: 0.02)
    }

    // Tungsten target (3200K) is warm → camera must boost blue / drop red.
    func test_warmTarget_boostsBlue() {
        let gains = WhiteBalance.gains(targetKelvin: 3200)
        XCTAssertGreaterThan(gains.z, gains.x, "blue gain should outpace red for tungsten")
        XCTAssertGreaterThan(gains.z, 1.5)
    }

    // Cool target (8500K) → camera must boost red / drop blue.
    func test_coolTarget_boostsRed() {
        let gains = WhiteBalance.gains(targetKelvin: 8500)
        XCTAssertGreaterThan(gains.x, gains.z, "red gain should outpace blue for cool light")
    }

    // Negative tint pushes green channel up (compensating for green light).
    func test_negativeTint_boostsGreen() {
        let neutral = WhiteBalance.gains(targetKelvin: 6500, tint: 0)
        let green = WhiteBalance.gains(targetKelvin: 6500, tint: -150)
        XCTAssertGreaterThan(green.y, neutral.y)
    }

    // Positive tint pushes red+blue up (compensating for magenta light).
    func test_positiveTint_boostsMagenta() {
        let neutral = WhiteBalance.gains(targetKelvin: 6500, tint: 0)
        let magenta = WhiteBalance.gains(targetKelvin: 6500, tint: 150)
        XCTAssertGreaterThan(magenta.x, neutral.x)
        XCTAssertGreaterThan(magenta.z, neutral.z)
    }

    // apply() == multiply by gains.
    func test_apply_multipliesByGains() {
        let pixel = SIMD3<Float>(0.4, 0.5, 0.6)
        let gains = WhiteBalance.gains(targetKelvin: 4300)
        let direct = pixel * gains
        let applied = WhiteBalance.apply(pixel, targetKelvin: 4300)
        XCTAssertEqual(applied.x, direct.x, accuracy: 1e-5)
        XCTAssertEqual(applied.y, direct.y, accuracy: 1e-5)
        XCTAssertEqual(applied.z, direct.z, accuracy: 1e-5)
    }

    // Kelvin output is well-formed: warm light has more red than blue.
    func test_kelvinToRGB_warmIsRed() {
        let warm = WhiteBalance.kelvinToRGB(2700)
        XCTAssertGreaterThan(warm.x, warm.z)
    }

    func test_kelvinToRGB_coolIsBlue() {
        let cool = WhiteBalance.kelvinToRGB(10000)
        XCTAssertGreaterThan(cool.z, cool.x)
    }

    // Out-of-range kelvin is clamped (no NaN/Inf).
    func test_kelvinClamping() {
        let lo = WhiteBalance.kelvinToRGB(100)
        let hi = WhiteBalance.kelvinToRGB(99999)
        for v in [lo.x, lo.y, lo.z, hi.x, hi.y, hi.z] {
            XCTAssertFalse(v.isNaN)
            XCTAssertFalse(v.isInfinite)
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
        }
    }
}
