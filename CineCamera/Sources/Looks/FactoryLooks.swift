import Foundation

/// Curated catalog of ready-to-use looks. Each one is a pure-Swift
/// `PipelineGraph` made by composing the catalogs we already ship
/// (CDLPresets / FilmGrainProfiles / CinemaFilters), so no external assets
/// are needed to render them.
public enum FactoryLooks {

    // MARK: - Cinematic

    public static let kodakVisionDay = Look(
        id: "factory.kodak_vision_day",
        name: "Kodak Vision — Daylight",
        subtitle: "Modern color negative, daylight balanced",
        category: .cinematic,
        graph: PipelineGraph(
            whiteBalance: .init(targetKelvin: 5600, tint: 0),
            cdl: CDLPresets.kodakVision.parameters,
            grain: .init(profile: FilmGrainProfiles.classicNegative,
                         iso: 800, intensityMultiplier: 0.6),
            filter: .init(filter: CinemaFilters.proMist1_4, intensity: 0.7)
        ),
        creditedTo: "Kodak Vision3 250D"
    )

    public static let sicarioSunset = Look(
        id: "factory.sicario_sunset",
        name: "Sicario Sunset",
        subtitle: "Warm orange / teal contrast",
        category: .cinematic,
        graph: PipelineGraph(
            whiteBalance: .init(targetKelvin: 4800, tint: 6),
            cdl: CDLPresets.tealAndOrange.parameters,
            grain: .init(profile: FilmGrainProfiles.visionPrime,
                         iso: 800, intensityMultiplier: 0.4),
            filter: .init(filter: CinemaFilters.coral3, intensity: 0.5)
        ),
        creditedTo: "Inspired by Roger Deakins"
    )

    public static let netflixDrama = Look(
        id: "factory.netflix_drama",
        name: "Netflix Drama",
        subtitle: "Subtle teal shadows, neutral mids, lifted blacks",
        category: .cinematic,
        graph: PipelineGraph(
            whiteBalance: .init(targetKelvin: 5600, tint: 0),
            cdl: CDLPresets.cinematicDay.parameters,
            grain: .init(profile: FilmGrainProfiles.visionPrime,
                         iso: 800, intensityMultiplier: 0.3),
            filter: .init(filter: CinemaFilters.blackProMist1_4, intensity: 0.5)
        )
    )

    // MARK: - Period

    public static let westernSilverHalide = Look(
        id: "factory.western_silver_halide",
        name: "Western — Silver Halide",
        subtitle: "1950s warm color negative",
        category: .period,
        graph: PipelineGraph(
            whiteBalance: .init(targetKelvin: 4500, tint: -8),
            cdl: CDLPresets.vintageFilm.parameters,
            grain: .init(profile: FilmGrainProfiles.classicNegative,
                         iso: 1600, intensityMultiplier: 0.9),
            filter: .init(filter: CinemaFilters.coral3, intensity: 0.6)
        )
    )

    public static let reversalSlideMemory = Look(
        id: "factory.reversal_slide_memory",
        name: "Reversal Slide Memory",
        subtitle: "Saturated chrome reversal stock, fine grain",
        category: .period,
        graph: PipelineGraph(
            whiteBalance: .init(targetKelvin: 5800, tint: 0),
            cdl: CDLPresets.fujiSlide.parameters,
            grain: .init(profile: FilmGrainProfiles.reversalChrome,
                         iso: 100, intensityMultiplier: 0.8),
            filter: .init(filter: CinemaFilters.proMist1_8, intensity: 0.4)
        )
    )

    public static let silentEra = Look(
        id: "factory.silent_era",
        name: "Silent Era B&W",
        subtitle: "Heavy grain, sepia desaturation, lifted blacks",
        category: .period,
        graph: PipelineGraph(
            whiteBalance: .init(targetKelvin: 5000, tint: 0),
            cdl: CDLPresets.sepia.parameters,
            grain: .init(profile: FilmGrainProfiles.silentEra,
                         iso: 200, intensityMultiplier: 1.0)
        )
    )

    // MARK: - Stylized

    public static let bleachBypass = Look(
        id: "factory.bleach_bypass",
        name: "Bleach Bypass",
        subtitle: "Crushed contrast, desaturated, silver-retention look",
        category: .stylized,
        graph: PipelineGraph(
            whiteBalance: .init(targetKelvin: 5600),
            cdl: CDLPresets.bleachBypass.parameters,
            grain: .init(profile: FilmGrainProfiles.classicNegative,
                         iso: 1250, intensityMultiplier: 0.7),
            filter: .init(filter: CinemaFilters.lowCon, intensity: 0.3)
        )
    )

    public static let neon80s = Look(
        id: "factory.neon_80s",
        name: "Neon 80s",
        subtitle: "Cross-process highlights, magenta tint, soft bloom",
        category: .stylized,
        graph: PipelineGraph(
            whiteBalance: .init(targetKelvin: 4200, tint: 35),
            cdl: CDLPresets.crossProcess.parameters,
            grain: .init(profile: FilmGrainProfiles.classicNegative,
                         iso: 1600, intensityMultiplier: 0.8),
            filter: .init(filter: CinemaFilters.blackProMist1, intensity: 0.7)
        )
    )

    public static let fadedDream = Look(
        id: "factory.faded_dream",
        name: "Faded Dream",
        subtitle: "Pastel midtones, soft highlight bloom",
        category: .stylized,
        graph: PipelineGraph(
            whiteBalance: .init(targetKelvin: 6200, tint: 8),
            cdl: CDLPresets.fadedPastel.parameters,
            grain: .init(profile: FilmGrainProfiles.visionPrime,
                         iso: 1600, intensityMultiplier: 0.5),
            filter: .init(filter: CinemaFilters.hollywoodBlackMagic1_4, intensity: 0.6)
        )
    )

    // MARK: - Broadcast

    public static let broadcastDoc = Look(
        id: "factory.broadcast_doc",
        name: "Broadcast Doc",
        subtitle: "Neutral, faithful skin tones, no diffusion",
        category: .broadcast,
        graph: PipelineGraph(
            whiteBalance: .init(targetKelvin: 5600),
            cdl: CDLPresets.skinGlow.parameters
        )
    )

    public static let newsroom = Look(
        id: "factory.newsroom",
        name: "Newsroom",
        subtitle: "High-key, slight punch, broadcast-safe",
        category: .broadcast,
        graph: PipelineGraph(
            whiteBalance: .init(targetKelvin: 5600),
            cdl: CDLPresets.punchy.parameters
        )
    )

    // MARK: - Night & Low Light

    public static let nightInTheCity = Look(
        id: "factory.night_in_the_city",
        name: "Night in the City",
        subtitle: "Cool shadows, lifted blacks, soft halation on practicals",
        category: .nightAndLowLight,
        graph: PipelineGraph(
            whiteBalance: .init(targetKelvin: 4200),
            cdl: CDLPresets.cinematicNight.parameters,
            grain: .init(profile: FilmGrainProfiles.visionNight,
                         iso: 3200, intensityMultiplier: 0.8),
            filter: .init(filter: CinemaFilters.blackProMist1, intensity: 0.6)
        )
    )

    public static let dayForNight = Look(
        id: "factory.day_for_night",
        name: "Day for Night",
        subtitle: "Cool blue cast, crushed shadows, simulated moonlight",
        category: .nightAndLowLight,
        graph: PipelineGraph(
            whiteBalance: .init(targetKelvin: 7200, tint: -12),
            cdl: CDLPresets.cool.parameters,
            grain: .init(profile: FilmGrainProfiles.bw3200,
                         iso: 3200, intensityMultiplier: 0.5),
            filter: .init(filter: CinemaFilters.blackProMist1_4, intensity: 0.4)
        )
    )

    // MARK: - Catalog

    public static let all: [Look] = [
        kodakVisionDay, sicarioSunset, netflixDrama,
        westernSilverHalide, reversalSlideMemory, silentEra,
        bleachBypass, neon80s, fadedDream,
        broadcastDoc, newsroom,
        nightInTheCity, dayForNight
    ]

    /// A library populated with every factory look — useful as the default
    /// "looks" tab on first launch.
    public static func defaultLibrary() -> LookLibrary {
        // Force-try is safe: ids are author-controlled and unique by construction.
        return try! LookLibrary(looks: all)
    }
}
