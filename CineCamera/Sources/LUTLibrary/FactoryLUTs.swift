import Foundation
import simd

/// Procedurally-baked LUTs that ship with the app — no asset bundle needed.
/// Built by feeding sampled grid points through a known transform (CDL,
/// log curve, or a hand-tuned closure).
public enum FactoryLUTs {

    private static let defaultSize = 33

    // MARK: - CDL bakes

    public static let kodakVision = LUTCatalogEntry(
        id: "factory.kodak_vision",
        name: "Kodak Vision (baked CDL)",
        category: .filmEmulation,
        sourceFormat: .procedural,
        lut: LUTBaker.bake(cdl: CDLPresets.kodakVision.parameters,
                            size: defaultSize, title: "Kodak Vision (baked CDL)")
    )

    public static let fujiSlide = LUTCatalogEntry(
        id: "factory.fuji_slide",
        name: "Fuji Slide (baked CDL)",
        category: .filmEmulation,
        sourceFormat: .procedural,
        lut: LUTBaker.bake(cdl: CDLPresets.fujiSlide.parameters,
                            size: defaultSize, title: "Fuji Slide (baked CDL)")
    )

    public static let bleachBypass = LUTCatalogEntry(
        id: "factory.bleach_bypass",
        name: "Bleach Bypass (baked CDL)",
        category: .stylized,
        sourceFormat: .procedural,
        lut: LUTBaker.bake(cdl: CDLPresets.bleachBypass.parameters,
                            size: defaultSize, title: "Bleach Bypass (baked CDL)")
    )

    public static let tealAndOrange = LUTCatalogEntry(
        id: "factory.teal_and_orange",
        name: "Teal & Orange (baked CDL)",
        category: .stylized,
        sourceFormat: .procedural,
        lut: LUTBaker.bake(cdl: CDLPresets.tealAndOrange.parameters,
                            size: defaultSize, title: "Teal & Orange (baked CDL)")
    )

    public static let sepia = LUTCatalogEntry(
        id: "factory.sepia",
        name: "Sepia (baked CDL)",
        category: .stylized,
        sourceFormat: .procedural,
        lut: LUTBaker.bake(cdl: CDLPresets.sepia.parameters,
                            size: defaultSize, title: "Sepia (baked CDL)")
    )

    // MARK: - Procedural display transforms

    public static let identity = LUTCatalogEntry(
        id: "factory.identity",
        name: "Identity",
        category: .neutral,
        sourceFormat: .procedural,
        lut: LUT3D.identity(size: defaultSize)
    )

    /// sRGB encode (linear → ~2.2 gamma). Useful as a final display
    /// transform when the pipeline operates in linear space.
    public static let srgbEncode = LUTCatalogEntry(
        id: "factory.srgb_encode",
        name: "sRGB Encode",
        category: .displayTransform,
        sourceFormat: .procedural,
        lut: LUTBaker.bake(size: defaultSize, title: "sRGB Encode") { rgb in
            return SIMD3<Float>(srgb(rgb.x), srgb(rgb.y), srgb(rgb.z))
        }
    )

    /// Rec.709 OETF — broadcast camera curve. Steeper toe than sRGB.
    public static let rec709Encode = LUTCatalogEntry(
        id: "factory.rec709_encode",
        name: "Rec.709 Encode",
        category: .displayTransform,
        sourceFormat: .procedural,
        lut: LUTBaker.bake(size: defaultSize, title: "Rec.709 Encode") { rgb in
            return SIMD3<Float>(rec709(rgb.x), rec709(rgb.y), rec709(rgb.z))
        }
    )

    // MARK: - Catalog

    public static let all: [LUTCatalogEntry] = [
        identity,
        kodakVision, fujiSlide,
        bleachBypass, tealAndOrange, sepia,
        srgbEncode, rec709Encode
    ]

    public static func defaultLibrary() -> LUTLibrary {
        return try! LUTLibrary(entries: all)
    }

    // MARK: - Encoding curves

    @inline(__always)
    private static func srgb(_ v: Float) -> Float {
        let x = max(0, min(1, v))
        if x <= 0.0031308 { return 12.92 * x }
        return 1.055 * pow(x, 1.0 / 2.4) - 0.055
    }

    @inline(__always)
    private static func rec709(_ v: Float) -> Float {
        let x = max(0, min(1, v))
        if x < 0.018 { return 4.5 * x }
        return 1.099 * pow(x, 0.45) - 0.099
    }
}
