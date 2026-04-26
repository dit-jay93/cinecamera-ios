import Foundation
import simd

public enum CinemaFilters {

    // MARK: - Diffusion: Tiffen ProMist (highlight bloom only)

    public static let proMist1_8 = CinemaFilter(
        id: "tiffen_promist_1_8",
        name: "ProMist 1/8",
        manufacturer: "Tiffen",
        category: .diffusion,
        transmittance: SIMD3<Float>(0.99, 0.99, 0.99),
        spatial: SpatialEffect(bloomRadius: 6,  bloomGain: 0.10, bloomThreshold: 0.75,
                               saturationReduction: 0.02, blackLift: 0.000)
    )

    public static let proMist1_4 = CinemaFilter(
        id: "tiffen_promist_1_4",
        name: "ProMist 1/4",
        manufacturer: "Tiffen",
        category: .diffusion,
        transmittance: SIMD3<Float>(0.98, 0.98, 0.98),
        spatial: SpatialEffect(bloomRadius: 9,  bloomGain: 0.18, bloomThreshold: 0.70,
                               saturationReduction: 0.05, blackLift: 0.005)
    )

    public static let proMist1_2 = CinemaFilter(
        id: "tiffen_promist_1_2",
        name: "ProMist 1/2",
        manufacturer: "Tiffen",
        category: .diffusion,
        transmittance: SIMD3<Float>(0.97, 0.97, 0.97),
        spatial: SpatialEffect(bloomRadius: 14, bloomGain: 0.30, bloomThreshold: 0.65,
                               saturationReduction: 0.10, blackLift: 0.010)
    )

    public static let proMist1 = CinemaFilter(
        id: "tiffen_promist_1",
        name: "ProMist 1",
        manufacturer: "Tiffen",
        category: .diffusion,
        transmittance: SIMD3<Float>(0.95, 0.95, 0.95),
        spatial: SpatialEffect(bloomRadius: 22, bloomGain: 0.45, bloomThreshold: 0.55,
                               saturationReduction: 0.18, blackLift: 0.020)
    )

    // MARK: - Diffusion: Tiffen Black ProMist (whole-frame bloom)

    public static let blackProMist1_4 = CinemaFilter(
        id: "tiffen_black_promist_1_4",
        name: "Black ProMist 1/4",
        manufacturer: "Tiffen",
        category: .diffusion,
        transmittance: SIMD3<Float>(0.97, 0.97, 0.97),
        spatial: SpatialEffect(bloomRadius: 10, bloomGain: 0.22, bloomThreshold: 0.0,
                               saturationReduction: 0.06, blackLift: 0.012)
    )

    public static let blackProMist1 = CinemaFilter(
        id: "tiffen_black_promist_1",
        name: "Black ProMist 1",
        manufacturer: "Tiffen",
        category: .diffusion,
        transmittance: SIMD3<Float>(0.94, 0.94, 0.94),
        spatial: SpatialEffect(bloomRadius: 24, bloomGain: 0.50, bloomThreshold: 0.0,
                               saturationReduction: 0.20, blackLift: 0.030)
    )

    // MARK: - Diffusion: Schneider Hollywood Black Magic 1/4

    public static let hollywoodBlackMagic1_4 = CinemaFilter(
        id: "schneider_hbm_1_4",
        name: "Hollywood Black Magic 1/4",
        manufacturer: "Schneider",
        category: .diffusion,
        transmittance: SIMD3<Float>(0.97, 0.97, 0.97),
        spatial: SpatialEffect(bloomRadius: 12, bloomGain: 0.25, bloomThreshold: 0.50,
                               saturationReduction: 0.08, blackLift: 0.014)
    )

    // MARK: - Color Conversion: Wratten

    /// 85B — tungsten → daylight conversion. Strongly attenuates blue.
    public static let wratten85B = CinemaFilter(
        id: "wratten_85b",
        name: "Wratten 85B",
        manufacturer: "Kodak",
        category: .colorTemperature,
        transmittance: SIMD3<Float>(0.95, 0.85, 0.33)
    )

    /// 80A — daylight → tungsten conversion. Strongly attenuates red.
    public static let wratten80A = CinemaFilter(
        id: "wratten_80a",
        name: "Wratten 80A",
        manufacturer: "Kodak",
        category: .colorTemperature,
        transmittance: SIMD3<Float>(0.30, 0.55, 0.95)
    )

    // MARK: - Skin

    public static let coral3 = CinemaFilter(
        id: "tiffen_coral_3",
        name: "Coral 3",
        manufacturer: "Tiffen",
        category: .skin,
        transmittance: SIMD3<Float>(1.00, 0.94, 0.78)
    )

    // MARK: - Special Effects

    /// IRND 0.6 — 2-stop ND with IR cut. ND base 0.25× across all channels;
    /// IR cut very slightly favors green/blue to suppress red contamination.
    public static let irnd0_6 = CinemaFilter(
        id: "irnd_0_6",
        name: "IRND 0.6",
        manufacturer: "Generic",
        category: .neutralDensity,
        transmittance: SIMD3<Float>(0.235, 0.250, 0.245)
    )

    /// LowCon — global low-contrast / flare simulation: black lift +
    /// saturation reduction + mild whole-frame veil.
    public static let lowCon = CinemaFilter(
        id: "tiffen_lowcon",
        name: "LowCon 1",
        manufacturer: "Tiffen",
        category: .lowContrast,
        transmittance: SIMD3<Float>(0.96, 0.96, 0.96),
        spatial: SpatialEffect(bloomRadius: 18, bloomGain: 0.30, bloomThreshold: 0.0,
                               saturationReduction: 0.18, blackLift: 0.040)
    )

    public static let all: [CinemaFilter] = [
        proMist1_8, proMist1_4, proMist1_2, proMist1,
        blackProMist1_4, blackProMist1,
        hollywoodBlackMagic1_4,
        wratten85B, wratten80A, coral3,
        irnd0_6, lowCon
    ]

    public static func filter(id: String) -> CinemaFilter? {
        return all.first { $0.id == id }
    }
}
