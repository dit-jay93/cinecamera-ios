import Foundation
import simd

/// Declarative grading pipeline. Stages run in this order:
///   1. White balance     (per-channel gain)
///   2. CDL primary grade (slope / offset / power per zone)
///   3. 3D LUT            (creative look)
///   4. Film grain        (per-pixel)
///   5. Cinema filter     (per-tile — includes Gaussian bloom)
///
/// Any stage may be `nil` to bypass it. The graph itself is `Codable` so
/// looks can be saved as JSON presets and re-loaded by name.
public struct PipelineGraph: Equatable {

    // MARK: - Stage configurations

    public struct WhiteBalanceStage: Codable, Equatable {
        public var targetKelvin: Float
        public var referenceKelvin: Float
        public var tint: Float

        public init(targetKelvin: Float = 6500,
                    referenceKelvin: Float = 6500,
                    tint: Float = 0) {
            self.targetKelvin = targetKelvin
            self.referenceKelvin = referenceKelvin
            self.tint = tint
        }

        public var isIdentity: Bool {
            return abs(targetKelvin - referenceKelvin) < 0.5 && abs(tint) < 0.5
        }
    }

    public struct LUTStage: Equatable {
        public let lut: LUT3D
        public var amount: Float
        public var interpolation: LUTInterpolation

        public init(lut: LUT3D, amount: Float = 1.0, interpolation: LUTInterpolation = .trilinear) {
            self.lut = lut
            self.amount = max(0, min(1, amount))
            self.interpolation = interpolation
        }
    }

    public struct GrainStage: Equatable {
        public var profile: FilmGrainProfile
        public var iso: Float
        public var intensityMultiplier: Float
        public var seed: UInt32

        public init(profile: FilmGrainProfile,
                    iso: Float = 800,
                    intensityMultiplier: Float = 1.0,
                    seed: UInt32 = 0x9E3779B9) {
            self.profile = profile
            self.iso = iso
            self.intensityMultiplier = intensityMultiplier
            self.seed = seed
        }

        func parameters(frame: Int) -> FilmGrainParameters {
            return FilmGrainParameters(profile: profile,
                                       iso: iso,
                                       intensityMultiplier: intensityMultiplier,
                                       frame: frame,
                                       seed: seed)
        }
    }

    public struct FilterStage: Equatable {
        public var filter: CinemaFilter
        public var intensity: Float

        public init(filter: CinemaFilter, intensity: Float = 1.0) {
            self.filter = filter
            self.intensity = max(0, min(1, intensity))
        }
    }

    // MARK: - Stages

    public var whiteBalance: WhiteBalanceStage?
    public var cdl: CDLParameters?
    public var lut: LUTStage?
    public var grain: GrainStage?
    public var filter: FilterStage?

    public init(whiteBalance: WhiteBalanceStage? = nil,
                cdl: CDLParameters? = nil,
                lut: LUTStage? = nil,
                grain: GrainStage? = nil,
                filter: FilterStage? = nil) {
        self.whiteBalance = whiteBalance
        self.cdl = cdl
        self.lut = lut
        self.grain = grain
        self.filter = filter
    }

    public static let identity = PipelineGraph()

    public var isIdentity: Bool {
        if let wb = whiteBalance, !wb.isIdentity { return false }
        if let cdl = cdl, !cdl.isIdentity { return false }
        if let lut = lut, lut.amount > 0 { return false }
        if let grain = grain, grain.intensityMultiplier > 0,
           grain.profile.intensity > 0 { return false }
        if let f = filter, f.intensity > 0 { return false }
        return true
    }

    // MARK: - Per-pixel apply (no spatial stages — bloom is bypassed)

    /// Per-pixel application. Skips the cinema filter's spatial bloom; use
    /// `applyTile` when you need the full effect.
    public func applyPixel(_ rgb: SIMD3<Float>,
                            position: SIMD2<Int> = .zero,
                            frame: Int = 0) -> SIMD3<Float> {
        var c = rgb
        if let wb = whiteBalance {
            c = WhiteBalance.apply(c,
                                   targetKelvin: wb.targetKelvin,
                                   referenceKelvin: wb.referenceKelvin,
                                   tint: wb.tint)
        }
        if let cdl = cdl {
            c = CDLEngine.apply(c, params: cdl)
        }
        if let lut = lut {
            c = lut.lut.sampleMixed(c, mode: lut.interpolation, amount: lut.amount)
        }
        if let grain = grain {
            c = FilmGrainEngine.apply(c, at: position, params: grain.parameters(frame: frame))
        }
        if let f = filter {
            c = CinemaFilterEngine.applyPixel(c, filter: f.filter, intensity: f.intensity)
        }
        return c
    }

    // MARK: - Per-tile apply (full pipeline including bloom)

    public func applyTile(_ pixels: [SIMD3<Float>],
                           width: Int,
                           height: Int,
                           frame: Int = 0) -> [SIMD3<Float>] {
        precondition(pixels.count == width * height, "pixel count != width*height")
        var buf = pixels

        if let wb = whiteBalance {
            for i in 0..<buf.count {
                buf[i] = WhiteBalance.apply(buf[i],
                                            targetKelvin: wb.targetKelvin,
                                            referenceKelvin: wb.referenceKelvin,
                                            tint: wb.tint)
            }
        }
        if let cdl = cdl {
            for i in 0..<buf.count { buf[i] = CDLEngine.apply(buf[i], params: cdl) }
        }
        if let lut = lut {
            for i in 0..<buf.count {
                buf[i] = lut.lut.sampleMixed(buf[i], mode: lut.interpolation, amount: lut.amount)
            }
        }
        if let grain = grain {
            let params = grain.parameters(frame: frame)
            for y in 0..<height {
                for x in 0..<width {
                    buf[y * width + x] = FilmGrainEngine.apply(buf[y * width + x],
                                                                at: SIMD2<Int>(x, y),
                                                                params: params)
                }
            }
        }
        if let f = filter {
            buf = CinemaFilterEngine.applyTile(buf, width: width, height: height,
                                                filter: f.filter, intensity: f.intensity)
        }
        return buf
    }
}

// MARK: - Codable (LUT is intentionally excluded from JSON; it round-trips by id)

extension PipelineGraph: Codable {
    private enum CodingKeys: String, CodingKey {
        case whiteBalance, cdl, lutReference, grain, filter
    }

    /// JSON-friendly handle to the LUT — the actual binary mesh lives in
    /// the LUT library. The graph stores only the id + parameters; the
    /// loader is responsible for resolving the LUT from disk/memory.
    public struct LUTReference: Codable, Equatable {
        public var id: String
        public var amount: Float
        public var interpolation: LUTInterpolation

        public init(id: String, amount: Float, interpolation: LUTInterpolation) {
            self.id = id
            self.amount = amount
            self.interpolation = interpolation
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.whiteBalance = try c.decodeIfPresent(WhiteBalanceStage.self, forKey: .whiteBalance)
        self.cdl = try c.decodeIfPresent(CDLParameters.self, forKey: .cdl)
        self.lut = nil  // populated separately by the loader using lutReference
        self.grain = try c.decodeIfPresent(GrainStage.self, forKey: .grain)
        self.filter = try c.decodeIfPresent(FilterStage.self, forKey: .filter)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(whiteBalance, forKey: .whiteBalance)
        try c.encodeIfPresent(cdl, forKey: .cdl)
        try c.encodeIfPresent(grain, forKey: .grain)
        try c.encodeIfPresent(filter, forKey: .filter)
        // LUT mesh is not serialized into the look JSON. Callers needing
        // round-trip should attach a LUTReference via lutReference(_:).
    }

    public func lutReference(id: String) -> LUTReference? {
        guard let lut = lut else { return nil }
        return LUTReference(id: id, amount: lut.amount, interpolation: lut.interpolation)
    }
}

extension PipelineGraph.GrainStage: Codable {}
extension PipelineGraph.FilterStage: Codable {}
