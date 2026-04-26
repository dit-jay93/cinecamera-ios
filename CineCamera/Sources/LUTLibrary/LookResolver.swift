import Foundation

public enum LookResolverError: Error {
    case lutMissing(lookId: String, lutId: String)
}

/// Bridges the JSON-friendly `Look` (which references LUTs by id) and the
/// runtime `PipelineGraph` (which holds an actual `LUT3D` mesh). Resolves
/// against a `LUTLibrary` and returns a fully-populated graph that can be
/// applied directly.
public enum LookResolver {

    /// Returns a copy of `look.graph` with the LUT stage populated from the
    /// supplied library. If the look has no `lutReferenceId`, the graph is
    /// returned untouched. If the id is set but missing in the library and
    /// `strict` is true, the call throws; otherwise the LUT stage is left
    /// `nil`.
    public static func resolve(_ look: Look,
                               in library: LUTLibrary,
                               amount: Float? = nil,
                               interpolation: LUTInterpolation = .trilinear,
                               strict: Bool = true) throws -> PipelineGraph {
        var graph = look.graph
        guard let lutId = look.lutReferenceId else { return graph }

        guard let lut = library.lut(id: lutId) else {
            if strict {
                throw LookResolverError.lutMissing(lookId: look.id, lutId: lutId)
            }
            graph.lut = nil
            return graph
        }
        let mix = max(0, min(1, amount ?? 1.0))
        graph.lut = .init(lut: lut, amount: mix, interpolation: interpolation)
        return graph
    }

    /// Convenience: resolve a look and immediately apply to a single pixel.
    public static func applyPixel(_ rgb: SIMD3<Float>,
                                   look: Look,
                                   library: LUTLibrary,
                                   position: SIMD2<Int> = .zero,
                                   frame: Int = 0) throws -> SIMD3<Float> {
        let graph = try resolve(look, in: library)
        return graph.applyPixel(rgb, position: position, frame: frame)
    }
}
