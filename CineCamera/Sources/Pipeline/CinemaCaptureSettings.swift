import Foundation

public enum CaptureResolution: String, Codable, CaseIterable {
    case uhd4k     // 3840 × 2160
    case fhd1080   // 1920 × 1080
    case hd720     // 1280 × 720

    public var size: (width: Int, height: Int) {
        switch self {
        case .uhd4k:   return (3840, 2160)
        case .fhd1080: return (1920, 1080)
        case .hd720:   return (1280, 720)
        }
    }
}

public enum CaptureCodec: String, Codable, CaseIterable {
    case proRes4444XQ
    case proRes422HQ
    case hevc10bit
    case hevc8bit
}

public struct ExposureSettings: Codable, Equatable {
    /// ISO sensitivity. Real range depends on the AVCaptureDevice format.
    public var iso: Float
    /// Shutter angle in degrees, 45°–360°. 180° is the cinematic standard.
    public var shutterAngle: Float
    /// Frame rate in frames per second.
    public var frameRate: Float
    /// EV bias, ±3.0.
    public var exposureBiasEV: Float

    public init(iso: Float = 400,
                shutterAngle: Float = 180,
                frameRate: Float = 24,
                exposureBiasEV: Float = 0) {
        self.iso = iso
        self.shutterAngle = shutterAngle
        self.frameRate = frameRate
        self.exposureBiasEV = exposureBiasEV
    }

    /// Derived: actual shutter speed in seconds.
    public var shutterSpeed: Float {
        return ShutterAngleMath.shutterSpeed(angle: shutterAngle, frameRate: frameRate)
    }
}

public struct WhiteBalanceSettings: Codable, Equatable {
    public var kelvin: Float    // 2000K – 10000K
    public var tint: Float      // -150 (green) to +150 (magenta)

    public init(kelvin: Float = 5600, tint: Float = 0) {
        self.kelvin = kelvin
        self.tint = tint
    }
}

public struct FocusSettings: Codable, Equatable {
    /// 0.0 = closest focusable distance, 1.0 = infinity.
    public var normalizedDistance: Float
    public var continuousAutoFocus: Bool

    public init(normalizedDistance: Float = 0.5, continuousAutoFocus: Bool = true) {
        self.normalizedDistance = normalizedDistance
        self.continuousAutoFocus = continuousAutoFocus
    }
}

public struct FormatSettings: Codable, Equatable {
    public var resolution: CaptureResolution
    public var frameRate: Float
    public var codec: CaptureCodec

    public init(resolution: CaptureResolution = .uhd4k,
                frameRate: Float = 24,
                codec: CaptureCodec = .proRes422HQ) {
        self.resolution = resolution
        self.frameRate = frameRate
        self.codec = codec
    }
}

public struct CinemaCaptureSettings: Codable, Equatable {
    public var exposure: ExposureSettings
    public var whiteBalance: WhiteBalanceSettings
    public var focus: FocusSettings
    public var format: FormatSettings

    public init(exposure: ExposureSettings = ExposureSettings(),
                whiteBalance: WhiteBalanceSettings = WhiteBalanceSettings(),
                focus: FocusSettings = FocusSettings(),
                format: FormatSettings = FormatSettings()) {
        self.exposure = exposure
        self.whiteBalance = whiteBalance
        self.focus = focus
        self.format = format
    }
}

// MARK: - Math

public enum ShutterAngleMath {
    /// Shutter speed (seconds) for a given shutter angle and frame rate.
    /// Standard cinema relation: speed = 1 / (fps × (360 / angle)).
    public static func shutterSpeed(angle: Float, frameRate: Float) -> Float {
        let safeAngle = max(angle, 1)
        let safeFps = max(frameRate, 1)
        return 1.0 / (safeFps * (360.0 / safeAngle))
    }

    /// Inverse: angle (degrees) for a given shutter speed and frame rate.
    public static func angle(shutterSpeed seconds: Float, frameRate: Float) -> Float {
        let safeSeconds = max(seconds, 1e-9)
        return min(360.0, max(1.0, 360.0 * frameRate * safeSeconds))
    }
}

public enum ExposureMath {
    /// Exposure Value at ISO 100 reference.
    /// EV = log2(N² / t) - log2(ISO / 100)
    public static func ev(aperture: Float, shutter seconds: Float, iso: Float) -> Float {
        let n2 = aperture * aperture
        let safeShutter = max(seconds, 1e-9)
        let safeIso = max(iso, 1)
        return log2(n2 / safeShutter) - log2(safeIso / 100)
    }

    /// Stops difference between two exposures (positive if `b` is brighter).
    public static func stopsDifference(from a: Float, to b: Float) -> Float {
        return b - a
    }
}
