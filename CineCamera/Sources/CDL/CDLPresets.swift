import Foundation

public struct CDLPreset: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let category: Category
    public let parameters: CDLParameters

    public enum Category: String, Codable, CaseIterable {
        case neutral
        case warm
        case cool
        case cinematic
        case film
        case stylized
    }
}

public enum CDLPresets {

    private static func sop(_ s: Float = 1, _ o: Float = 0, _ p: Float = 1) -> CDLChannelSOP {
        return CDLChannelSOP(slope: s, offset: o, power: p)
    }

    public static let identity = CDLPreset(
        id: "identity",
        name: "Identity",
        category: .neutral,
        parameters: .identity
    )

    public static let warm = CDLPreset(
        id: "warm",
        name: "Warm",
        category: .warm,
        parameters: CDLParameters(
            shadows:    CDLZone(red: sop(1.02, 0.005), blue: sop(0.95, -0.005)),
            midtones:   CDLZone(red: sop(1.05),       green: sop(1.01), blue: sop(0.94), saturation: 1.05),
            highlights: CDLZone(red: sop(1.03, 0.01), blue: sop(0.93))
        )
    )

    public static let cool = CDLPreset(
        id: "cool",
        name: "Cool",
        category: .cool,
        parameters: CDLParameters(
            shadows:    CDLZone(red: sop(0.95, -0.005), blue: sop(1.05, 0.01)),
            midtones:   CDLZone(red: sop(0.97),         blue: sop(1.06), saturation: 0.98),
            highlights: CDLZone(red: sop(0.96),         blue: sop(1.04))
        )
    )

    public static let tealAndOrange = CDLPreset(
        id: "teal_and_orange",
        name: "Teal & Orange",
        category: .cinematic,
        parameters: CDLParameters(
            shadows:    CDLZone(red: sop(0.92), green: sop(1.03), blue: sop(1.10, 0.012), saturation: 1.10),
            midtones:   CDLZone(saturation: 1.05),
            highlights: CDLZone(red: sop(1.10, 0.015), green: sop(1.02), blue: sop(0.88), saturation: 1.10)
        )
    )

    public static let bleachBypass = CDLPreset(
        id: "bleach_bypass",
        name: "Bleach Bypass",
        category: .stylized,
        parameters: CDLParameters(
            shadows:    CDLZone(luma: sop(1.10, -0.02, 1.05), saturation: 0.55),
            midtones:   CDLZone(luma: sop(1.05, 0, 0.95),     saturation: 0.45),
            highlights: CDLZone(luma: sop(1.02, 0.02, 0.92),  saturation: 0.50)
        )
    )

    public static let crossProcess = CDLPreset(
        id: "cross_process",
        name: "Cross Process",
        category: .stylized,
        parameters: CDLParameters(
            shadows:    CDLZone(red: sop(0.85, -0.015), green: sop(1.05), blue: sop(1.15, 0.020)),
            midtones:   CDLZone(red: sop(1.10),         green: sop(0.95), blue: sop(0.90), saturation: 1.20),
            highlights: CDLZone(red: sop(1.08, 0.015),  green: sop(1.10), blue: sop(0.85))
        )
    )

    public static let cinematicDay = CDLPreset(
        id: "cinematic_day",
        name: "Cinematic Day",
        category: .cinematic,
        parameters: CDLParameters(
            shadows:    CDLZone(red: sop(0.96), blue: sop(1.04, 0.005), saturation: 0.95),
            midtones:   CDLZone(luma: sop(1.0, 0, 0.98), saturation: 1.05),
            highlights: CDLZone(red: sop(1.04, 0.008), blue: sop(0.95), saturation: 0.95)
        )
    )

    public static let cinematicNight = CDLPreset(
        id: "cinematic_night",
        name: "Cinematic Night",
        category: .cinematic,
        parameters: CDLParameters(
            shadows:    CDLZone(luma: sop(0.85, 0.020, 1.10), red: sop(0.90), blue: sop(1.20, 0.015), saturation: 0.85),
            midtones:   CDLZone(luma: sop(0.92, 0.01, 1.05),  blue: sop(1.10), saturation: 0.90),
            highlights: CDLZone(luma: sop(0.95, 0, 1.0),       blue: sop(1.05), saturation: 0.85)
        )
    )

    public static let vintageFilm = CDLPreset(
        id: "vintage_film",
        name: "Vintage Film",
        category: .film,
        parameters: CDLParameters(
            shadows:    CDLZone(luma: sop(0.92, 0.035, 0.95), red: sop(1.04), green: sop(1.02), blue: sop(0.92), saturation: 0.85),
            midtones:   CDLZone(luma: sop(0.97, 0.010, 0.98), red: sop(1.05), blue: sop(0.93), saturation: 0.90),
            highlights: CDLZone(luma: sop(0.95, 0, 0.96),     red: sop(1.02, 0.005), blue: sop(0.95), saturation: 0.85)
        )
    )

    public static let sepia = CDLPreset(
        id: "sepia",
        name: "Sepia",
        category: .film,
        parameters: CDLParameters(
            shadows:    CDLZone(red: sop(1.10, 0.020), green: sop(0.95), blue: sop(0.70), saturation: 0.30),
            midtones:   CDLZone(red: sop(1.20, 0.010), green: sop(1.00), blue: sop(0.75), saturation: 0.20),
            highlights: CDLZone(red: sop(1.12, 0.020), green: sop(1.05), blue: sop(0.80), saturation: 0.15)
        )
    )

    public static let noir = CDLPreset(
        id: "noir",
        name: "Noir",
        category: .stylized,
        parameters: CDLParameters(
            shadows:    CDLZone(luma: sop(0.85, -0.015, 1.20), saturation: 0.05),
            midtones:   CDLZone(luma: sop(1.05, 0, 1.05),       saturation: 0.05),
            highlights: CDLZone(luma: sop(1.08, 0.015, 0.95),   saturation: 0.05)
        )
    )

    public static let fadedPastel = CDLPreset(
        id: "faded_pastel",
        name: "Faded Pastel",
        category: .stylized,
        parameters: CDLParameters(
            shadows:    CDLZone(luma: sop(0.85, 0.060, 0.85), saturation: 0.70),
            midtones:   CDLZone(luma: sop(0.92, 0.020, 0.92), saturation: 0.75),
            highlights: CDLZone(luma: sop(0.95, 0, 0.95),      saturation: 0.70)
        )
    )

    public static let punchy = CDLPreset(
        id: "punchy",
        name: "Punchy",
        category: .stylized,
        parameters: CDLParameters(
            shadows:    CDLZone(luma: sop(1.00, -0.010, 1.10), saturation: 1.20),
            midtones:   CDLZone(luma: sop(1.05, 0, 1.02),       saturation: 1.25),
            highlights: CDLZone(luma: sop(1.05, 0.005, 0.95),   saturation: 1.20)
        )
    )

    public static let kodakVision = CDLPreset(
        id: "kodak_vision",
        name: "Kodak Vision",
        category: .film,
        parameters: CDLParameters(
            shadows:    CDLZone(red: sop(0.97), green: sop(1.01), blue: sop(1.04, 0.006), saturation: 1.00),
            midtones:   CDLZone(red: sop(1.04), green: sop(1.00), blue: sop(0.97), saturation: 1.05),
            highlights: CDLZone(red: sop(1.05, 0.008), green: sop(1.02), blue: sop(0.94), saturation: 1.00)
        )
    )

    public static let fujiSlide = CDLPreset(
        id: "fuji_slide",
        name: "Fuji Slide",
        category: .film,
        parameters: CDLParameters(
            shadows:    CDLZone(luma: sop(1.0, -0.005, 1.05), green: sop(1.03), blue: sop(1.05), saturation: 1.20),
            midtones:   CDLZone(luma: sop(1.02, 0, 1.0),      green: sop(1.04), blue: sop(1.02), saturation: 1.25),
            highlights: CDLZone(luma: sop(1.0, 0, 0.98),       saturation: 1.15)
        )
    )

    public static let skinGlow = CDLPreset(
        id: "skin_glow",
        name: "Skin Glow",
        category: .warm,
        parameters: CDLParameters(
            shadows:    CDLZone(red: sop(1.02, 0.005), blue: sop(0.97)),
            midtones:   CDLZone(luma: sop(1.0, 0.010, 0.98), red: sop(1.04), green: sop(1.01), blue: sop(0.96), saturation: 1.05),
            highlights: CDLZone(red: sop(1.03, 0.012), green: sop(1.01), blue: sop(0.95), saturation: 0.95)
        )
    )

    public static let sunset = CDLPreset(
        id: "sunset",
        name: "Sunset",
        category: .warm,
        parameters: CDLParameters(
            shadows:    CDLZone(red: sop(1.08, 0.010), green: sop(0.97), blue: sop(1.02), saturation: 1.10),
            midtones:   CDLZone(red: sop(1.12, 0.005), green: sop(0.95), blue: sop(0.92), saturation: 1.15),
            highlights: CDLZone(red: sop(1.10, 0.020), green: sop(0.95), blue: sop(0.78), saturation: 1.10)
        )
    )

    public static let underwater = CDLPreset(
        id: "underwater",
        name: "Underwater",
        category: .cool,
        parameters: CDLParameters(
            shadows:    CDLZone(red: sop(0.80), green: sop(1.05), blue: sop(1.08, 0.010), saturation: 0.90),
            midtones:   CDLZone(red: sop(0.85), green: sop(1.08), blue: sop(1.10), saturation: 0.95),
            highlights: CDLZone(red: sop(0.88), green: sop(1.06), blue: sop(1.06), saturation: 0.90)
        )
    )

    public static let forest = CDLPreset(
        id: "forest",
        name: "Forest",
        category: .stylized,
        parameters: CDLParameters(
            shadows:    CDLZone(red: sop(0.93), green: sop(1.05, 0.005), blue: sop(0.95), saturation: 1.00),
            midtones:   CDLZone(red: sop(0.95), green: sop(1.08),         blue: sop(0.92), saturation: 1.10),
            highlights: CDLZone(red: sop(0.96), green: sop(1.06),         blue: sop(0.93), saturation: 1.05)
        )
    )

    public static let desert = CDLPreset(
        id: "desert",
        name: "Desert",
        category: .warm,
        parameters: CDLParameters(
            shadows:    CDLZone(red: sop(1.06, 0.008), green: sop(1.02), blue: sop(0.88), saturation: 1.05),
            midtones:   CDLZone(red: sop(1.10),        green: sop(1.05), blue: sop(0.85), saturation: 1.10),
            highlights: CDLZone(red: sop(1.08, 0.015), green: sop(1.06), blue: sop(0.82), saturation: 1.05)
        )
    )

    public static let all: [CDLPreset] = [
        identity,
        warm, cool, skinGlow, sunset, desert,
        underwater,
        tealAndOrange, cinematicDay, cinematicNight,
        vintageFilm, sepia, kodakVision, fujiSlide,
        bleachBypass, crossProcess, noir, fadedPastel, punchy, forest
    ]
}
