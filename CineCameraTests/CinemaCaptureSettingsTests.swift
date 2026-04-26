import XCTest
@testable import CinePipeline

final class CinemaCaptureSettingsTests: XCTestCase {

    // 180° at 24 fps must equal 1/48 s.
    func test_shutterSpeed_180At24fps() {
        let s = ShutterAngleMath.shutterSpeed(angle: 180, frameRate: 24)
        XCTAssertEqual(s, 1.0 / 48.0, accuracy: 1e-6)
    }

    // 90° at 24 fps must equal 1/96 s.
    func test_shutterSpeed_90At24fps() {
        let s = ShutterAngleMath.shutterSpeed(angle: 90, frameRate: 24)
        XCTAssertEqual(s, 1.0 / 96.0, accuracy: 1e-6)
    }

    // 360° at 30 fps must equal 1/30 s.
    func test_shutterSpeed_360At30fps() {
        let s = ShutterAngleMath.shutterSpeed(angle: 360, frameRate: 30)
        XCTAssertEqual(s, 1.0 / 30.0, accuracy: 1e-6)
    }

    // angle ↔ shutterSpeed must round-trip.
    func test_angleRoundTrip() {
        for fps in [Float(24), 25, 30, 48, 60] {
            for angle in [Float(45), 90, 144, 180, 270, 360] {
                let s = ShutterAngleMath.shutterSpeed(angle: angle, frameRate: fps)
                let back = ShutterAngleMath.angle(shutterSpeed: s, frameRate: fps)
                XCTAssertEqual(back, angle, accuracy: 1e-3, "fps=\(fps) angle=\(angle)")
            }
        }
    }

    // EV at f/1.8, 1/50s, ISO 100 → ~ EV(box) ~ 5.45
    func test_evCalculation() {
        let ev = ExposureMath.ev(aperture: 1.8, shutter: 1.0 / 50.0, iso: 100)
        // EV = log2(1.8² / (1/50)) - log2(100/100)
        //    = log2(3.24 * 50) = log2(162) ≈ 7.34
        XCTAssertEqual(ev, log2(1.8 * 1.8 * 50), accuracy: 1e-4)
    }

    // ISO contribution: doubling ISO drops EV by 1 stop.
    func test_evIsoDelta() {
        let a = ExposureMath.ev(aperture: 2.8, shutter: 1.0 / 50.0, iso: 100)
        let b = ExposureMath.ev(aperture: 2.8, shutter: 1.0 / 50.0, iso: 200)
        XCTAssertEqual(a - b, 1.0, accuracy: 1e-4)
    }

    // Codable round-trip on the top-level settings struct.
    func test_codableRoundTrip() throws {
        let s = CinemaCaptureSettings(
            exposure: ExposureSettings(iso: 800, shutterAngle: 172.8, frameRate: 23.976, exposureBiasEV: -0.5),
            whiteBalance: WhiteBalanceSettings(kelvin: 4300, tint: 12),
            focus: FocusSettings(normalizedDistance: 0.27, continuousAutoFocus: false),
            format: FormatSettings(resolution: .uhd4k, frameRate: 23.976, codec: .proRes422HQ)
        )
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(CinemaCaptureSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }
}
