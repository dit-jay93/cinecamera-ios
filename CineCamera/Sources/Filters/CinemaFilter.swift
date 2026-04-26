import Foundation
import simd

public enum FilterCategory: String, Codable, CaseIterable {
    case diffusion
    case colorTemperature
    case skin
    case neutralDensity
    case lowContrast
}

/// Spatial (image-level) effect parameters. The actual blur happens on GPU
/// or via `CinemaFilterEngine.applySeparableGaussian`. Reference radii
/// assume a 1080p source — engines can scale to native resolution.
public struct SpatialEffect: Codable, Equatable {
    /// Gaussian blur radius in pixels (sigma ~= radius / 3).
    public var bloomRadius: Float
    /// Bloom mix amount (0 = blur unused, 1 = full blur replacement).
    public var bloomGain: Float
    /// Highlight cutoff for bloom: 0 = bloom everywhere (Black ProMist),
    /// > 0 = only blur pixels above this luma (ProMist behavior).
    public var bloomThreshold: Float
    /// Multiplicative saturation reduction applied to entire frame.
    public var saturationReduction: Float
    /// Black-lift amount (added uniformly to RGB to flatten contrast).
    public var blackLift: Float

    public init(bloomRadius: Float = 0,
                bloomGain: Float = 0,
                bloomThreshold: Float = 0,
                saturationReduction: Float = 0,
                blackLift: Float = 0) {
        self.bloomRadius = bloomRadius
        self.bloomGain = bloomGain
        self.bloomThreshold = bloomThreshold
        self.saturationReduction = saturationReduction
        self.blackLift = blackLift
    }

    public static let none = SpatialEffect()
}

/// Cinema filter — combines a per-pixel 3x3 color matrix (with luminance
/// passthrough) and an optional spatial effect.
public struct CinemaFilter: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let manufacturer: String
    public let category: FilterCategory

    /// Diagonal RGB transmittance — derived from the published spectral
    /// transmittance integrated against approximate camera RGB sensitivities.
    public let transmittance: SIMD3<Float>

    public let spatial: SpatialEffect

    public init(id: String,
                name: String,
                manufacturer: String,
                category: FilterCategory,
                transmittance: SIMD3<Float> = SIMD3(1, 1, 1),
                spatial: SpatialEffect = .none) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.category = category
        self.transmittance = transmittance
        self.spatial = spatial
    }
}

public extension CinemaFilter {
    /// Apply the per-pixel transmittance, blended by `intensity` ∈ [0,1].
    /// intensity = 0 returns the input unchanged.
    func applyPixel(_ rgb: SIMD3<Float>, intensity: Float) -> SIMD3<Float> {
        let t = max(0, min(1, intensity))
        let mix = SIMD3<Float>(repeating: 1) * (1 - t) + transmittance * t
        return rgb * mix
    }
}
