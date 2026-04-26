import Foundation

#if canImport(Metal)
import Metal

public enum MetalContextError: Error {
    case noDevice
    case sourceMissing(String)
    case libraryCompileFailed(Error)
    case kernelMissing(String)
    case pipelineCreateFailed(Error)
}

/// Holds the Metal device, command queue, and a runtime-compiled `MTLLibrary`
/// containing every `.metal` kernel that ships with the CinePipeline target.
///
/// The Swift Package Manager copies our `.metal` files into the resource
/// bundle as plain text rather than compiling them, so the library is
/// assembled here by reading the sources and calling
/// `MTLDevice.makeLibrary(source:options:)`. The result is cached on the
/// shared instance — first use pays the compile cost, every later use is
/// essentially free.
public final class MetalContext {

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue

    /// Per-file Metal libraries, keyed by file basename (without `.metal`).
    /// We compile separately because some files declare `constant`s with
    /// the same name (e.g. `kLumaWeights`), which would collide if we
    /// concatenated them into a single translation unit.
    public let libraries: [String: MTLLibrary]

    private var pipelineCache: [String: MTLComputePipelineState] = [:]
    private let cacheLock = NSLock()

    /// Names of every `.metal` source file we ship — used to assemble the
    /// runtime libraries. Kept here so additions are obvious in one place.
    public static let kernelSources: [String] = [
        "CineLogCurve",
        "CDL",
        "LUT3D",
        "FilmGrain",
        "CinemaFilter"
    ]

    /// Best-effort init. Returns `nil` on machines without a usable GPU
    /// (CI environments, headless macOS) so callers can fall back to CPU.
    public static func makeDefault() -> MetalContext? {
        return try? MetalContext()
    }

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalContextError.noDevice
        }
        guard let queue = device.makeCommandQueue() else {
            throw MetalContextError.noDevice
        }
        self.device = device
        self.commandQueue = queue
        self.libraries = try MetalContext.compileShippedLibraries(device: device)
    }

    // MARK: - Pipeline lookup (cached)

    public func computePipeline(named name: String) throws -> MTLComputePipelineState {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = pipelineCache[name] { return cached }

        var function: MTLFunction?
        for library in libraries.values {
            if let f = library.makeFunction(name: name) { function = f; break }
        }
        guard let f = function else { throw MetalContextError.kernelMissing(name) }
        do {
            let pipeline = try device.makeComputePipelineState(function: f)
            pipelineCache[name] = pipeline
            return pipeline
        } catch {
            throw MetalContextError.pipelineCreateFailed(error)
        }
    }

    // MARK: - Library assembly

    private static func compileShippedLibraries(device: MTLDevice) throws -> [String: MTLLibrary] {
        let bundle = Bundle.module
        var libs: [String: MTLLibrary] = [:]
        for name in kernelSources {
            guard let url = bundle.url(forResource: name, withExtension: "metal") else {
                throw MetalContextError.sourceMissing(name)
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            do {
                libs[name] = try device.makeLibrary(source: text, options: nil)
            } catch {
                throw MetalContextError.libraryCompileFailed(error)
            }
        }
        return libs
    }
}

#endif
