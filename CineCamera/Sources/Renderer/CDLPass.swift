import Foundation
import simd

#if canImport(Metal)
import Metal

/// GPU CDL pass — wraps `cdlApplyKernel` from CDL.metal.
///
/// The pass owns nothing input-specific; you hand it source/destination
/// textures and a `CDLParameters`, and it dispatches a single-grid compute
/// pass. The pipeline state is fetched from `MetalContext` (cached there),
/// so constructing a `CDLPass` is essentially free after the first use.
public final class CDLPass {

    public let context: MetalContext
    private let pipeline: MTLComputePipelineState

    public init(context: MetalContext) throws {
        self.context = context
        self.pipeline = try context.computePipeline(named: "cdlApplyKernel")
    }

    /// Encodes the CDL kernel into `commandBuffer`. Caller is responsible
    /// for committing the buffer (so multiple passes can be chained).
    public func encode(commandBuffer: MTLCommandBuffer,
                       input: MTLTexture,
                       output: MTLTexture,
                       parameters: CDLParameters) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)

        let floats = CDLUniformBuffer(parameters).floats
        let byteLength = floats.count * MemoryLayout<Float>.size
        floats.withUnsafeBytes { raw in
            encoder.setBytes(raw.baseAddress!, length: byteLength, index: 0)
        }

        let w = pipeline.threadExecutionWidth
        let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
        let threadsPerGroup = MTLSize(width: w, height: h, depth: 1)
        let gridSize = MTLSize(width: output.width, height: output.height, depth: 1)

        if context.device.supportsFamily(.apple4) || context.device.supportsFamily(.mac2) {
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
        } else {
            let groups = MTLSize(
                width:  (output.width  + w - 1) / w,
                height: (output.height + h - 1) / h,
                depth:  1
            )
            encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)
        }

        encoder.endEncoding()
    }

    /// Synchronous convenience: takes CPU pixels, runs the GPU pass, returns
    /// CPU pixels. Useful for tests and one-off processing; production code
    /// should prefer the `encode(...)` form to keep the GPU pipelined.
    public func apply(pixels: [SIMD3<Float>],
                      width: Int,
                      height: Int,
                      parameters: CDLParameters) throws -> [SIMD3<Float>] {
        let input  = try MetalImageBuffer.makeTexture(device: context.device,
                                                      pixels: pixels,
                                                      width: width,
                                                      height: height)
        let output = try MetalImageBuffer.makeTexture(device: context.device,
                                                      width: width,
                                                      height: height)
        guard let cmd = context.commandQueue.makeCommandBuffer() else { return pixels }
        encode(commandBuffer: cmd, input: input, output: output, parameters: parameters)
        cmd.commit()
        cmd.waitUntilCompleted()
        return MetalImageBuffer.download(output)
    }
}

#endif
