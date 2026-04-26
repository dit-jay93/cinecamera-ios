import Foundation

public enum NDFilter: String, Codable, CaseIterable {
    case none
    case nd2     // 1 stop  (0.3 density)
    case nd4     // 2 stops (0.6 density)
    case nd8     // 3 stops (0.9 density)
    case nd16    // 4 stops (1.2 density)
    case nd32    // 5 stops (1.5 density)
    case nd64    // 6 stops (1.8 density)
    case nd128   // 7 stops (2.1 density)

    public var stops: Float {
        switch self {
        case .none:  return 0
        case .nd2:   return 1
        case .nd4:   return 2
        case .nd8:   return 3
        case .nd16:  return 4
        case .nd32:  return 5
        case .nd64:  return 6
        case .nd128: return 7
        }
    }

    public static let allOrdered: [NDFilter] = [.none, .nd2, .nd4, .nd8, .nd16, .nd32, .nd64, .nd128]
}

public struct NDRecommendation: Equatable {
    public let requiredStops: Float
    public let suggestedFilter: NDFilter
    /// Negative if the scene is too dark for cinematic shutter at native ISO
    /// (no ND can save it — open up exposure instead).
    public let isUnderExposed: Bool

    public init(requiredStops: Float, suggestedFilter: NDFilter, isUnderExposed: Bool) {
        self.requiredStops = requiredStops
        self.suggestedFilter = suggestedFilter
        self.isUnderExposed = isUnderExposed
    }
}

public enum NDRecommender {

    /// Recommend an ND filter to maintain a cinematic shutter angle at
    /// the given frame rate, when the camera's auto-exposure currently
    /// settles on `currentShutter` (seconds) at `currentISO`.
    ///
    /// Native iPhone aperture is fixed (`apertureF`), so the only variables
    /// are shutter time, ISO, and any ND glass. We assume the user has
    /// already locked ISO to the native low value.
    public static func recommend(currentShutter currentSeconds: Float,
                                 currentISO: Float,
                                 nativeISO: Float,
                                 targetFrameRate fps: Float,
                                 shutterAngle angle: Float = 180) -> NDRecommendation {
        let targetShutter = ShutterAngleMath.shutterSpeed(angle: angle, frameRate: fps)
        // For a fixed scene luminance L, sensor exposure ∝ L · t · ISO.
        // AE landed on (t_cur, ISO_cur) for correct exposure, so switching
        // to (t_tgt, ISO_native) without changing the scene gives:
        //     ratio = (t_tgt · ISO_native) / (t_cur · ISO_cur)
        // > 1 → too much light, ND helps; < 1 → too little, ND can't help.
        let safeCur = max(currentSeconds, 1e-9)
        let safeTgt = max(targetShutter, 1e-9)
        let safeIso = max(nativeISO, 1)
        let safeCurISO = max(currentISO, 1)

        let stops = log2((safeTgt * safeIso) / (safeCur * safeCurISO))

        if stops <= 0 {
            return NDRecommendation(requiredStops: stops,
                                    suggestedFilter: .none,
                                    isUnderExposed: stops < -0.5)
        }
        let chosen = pickFilter(forStops: stops)
        return NDRecommendation(requiredStops: stops,
                                suggestedFilter: chosen,
                                isUnderExposed: false)
    }

    /// Pick the largest ND that does not exceed `stops` (round down so we
    /// avoid under-exposing). If `stops < 1` return `.none`.
    public static func pickFilter(forStops stops: Float) -> NDFilter {
        guard stops >= 1 else { return .none }
        var chosen: NDFilter = .none
        for nd in NDFilter.allOrdered where nd.stops <= stops + 1e-3 {
            chosen = nd
        }
        return chosen
    }
}
