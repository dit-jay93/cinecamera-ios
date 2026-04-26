import Foundation
import simd

public struct FilmGrainProfile: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let basedOn: String

    /// Per-channel grain gain (R, G, B). Models relative dye-layer noise.
    public let channelGain: SIMD3<Float>

    /// Cluster size in pixels. 1.0 = single-pixel grain; 2.5 = ~2.5px clumps.
    public let size: Float

    /// Base intensity at the profile's native ISO. Multiplied by ISO scaling at apply time.
    public let intensity: Float

    /// Shadow bias exponent (Hurter-Driffield). 0 = uniform; higher pushes grain into shadows.
    public let shadowBias: Float

    /// True for B&W films — all channels share the same noise sample.
    public let monochrome: Bool

    /// ISO at which `intensity` is calibrated. Real ISO scales relative to this.
    public let nativeISO: Float

    public init(id: String,
                name: String,
                basedOn: String,
                channelGain: SIMD3<Float>,
                size: Float,
                intensity: Float,
                shadowBias: Float,
                monochrome: Bool,
                nativeISO: Float) {
        self.id = id
        self.name = name
        self.basedOn = basedOn
        self.channelGain = channelGain
        self.size = size
        self.intensity = intensity
        self.shadowBias = shadowBias
        self.monochrome = monochrome
        self.nativeISO = nativeISO
    }
}

public enum FilmGrainProfiles {

    public static let visionPrime = FilmGrainProfile(
        id: "vision_prime",
        name: "VisionPrime",
        basedOn: "Kodak Vision3 250D",
        channelGain: SIMD3<Float>(0.85, 0.95, 1.10),
        size: 1.2,
        intensity: 0.025,
        shadowBias: 1.6,
        monochrome: false,
        nativeISO: 250
    )

    public static let visionNight = FilmGrainProfile(
        id: "vision_night",
        name: "VisionNight",
        basedOn: "Kodak Vision3 500T",
        channelGain: SIMD3<Float>(0.95, 1.05, 1.30),
        size: 1.5,
        intensity: 0.045,
        shadowBias: 1.4,
        monochrome: false,
        nativeISO: 500
    )

    public static let classicNegative = FilmGrainProfile(
        id: "classic_negative",
        name: "ClassicNegative",
        basedOn: "Fuji Eterna 500",
        channelGain: SIMD3<Float>(1.10, 1.00, 1.20),
        size: 1.8,
        intensity: 0.060,
        shadowBias: 1.2,
        monochrome: false,
        nativeISO: 500
    )

    public static let reversalChrome = FilmGrainProfile(
        id: "reversal_chrome",
        name: "ReversalChrome",
        basedOn: "Fuji Velvia 50",
        channelGain: SIMD3<Float>(0.70, 0.75, 0.85),
        size: 0.9,
        intensity: 0.015,
        shadowBias: 1.8,
        monochrome: false,
        nativeISO: 50
    )

    public static let bw400 = FilmGrainProfile(
        id: "bw_400",
        name: "BW400",
        basedOn: "Kodak T-Max 400",
        channelGain: SIMD3<Float>(1.0, 1.0, 1.0),
        size: 1.4,
        intensity: 0.045,
        shadowBias: 1.3,
        monochrome: true,
        nativeISO: 400
    )

    public static let bw3200 = FilmGrainProfile(
        id: "bw_3200",
        name: "BW3200",
        basedOn: "Kodak P3200",
        channelGain: SIMD3<Float>(1.0, 1.0, 1.0),
        size: 2.6,
        intensity: 0.110,
        shadowBias: 1.0,
        monochrome: true,
        nativeISO: 3200
    )

    public static let ecn2Look = FilmGrainProfile(
        id: "ecn2_look",
        name: "ECN2Look",
        basedOn: "Cinema ECN-2 negative process",
        channelGain: SIMD3<Float>(0.95, 1.00, 1.15),
        size: 1.6,
        intensity: 0.050,
        shadowBias: 1.3,
        monochrome: false,
        nativeISO: 500
    )

    public static let silentEra = FilmGrainProfile(
        id: "silent_era",
        name: "SilentEra",
        basedOn: "Early orthochromatic",
        channelGain: SIMD3<Float>(1.0, 1.0, 1.0),
        size: 3.2,
        intensity: 0.180,
        shadowBias: 0.8,
        monochrome: true,
        nativeISO: 32
    )

    public static let all: [FilmGrainProfile] = [
        visionPrime, visionNight,
        classicNegative, reversalChrome, ecn2Look,
        bw400, bw3200,
        silentEra
    ]

    public static func profile(id: String) -> FilmGrainProfile? {
        return all.first { $0.id == id }
    }
}
