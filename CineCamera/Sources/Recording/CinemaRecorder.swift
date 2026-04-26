import Foundation

#if os(iOS)
import AVFoundation
import CoreVideo
import CoreMedia

public enum CinemaRecorderError: Error {
    case alreadyRecording
    case notRecording
    case writerSetupFailed(Error)
    case appendFailed(Error)
    case finishFailed(Error)
}

public enum CinemaRecorderState: Equatable {
    case idle
    case writing
    case finishing
    case finished(URL)
    case failed(String)
}

/// Wraps `AVAssetWriter` for clip-by-clip cinematic recording. The recorder
/// owns the file URL and timeline; pipe `CMSampleBuffer`s in via
/// `append(_:)` and call `finish()` to seal the clip.
///
/// File format is always `.mov`. Codec selection follows the
/// `CaptureCodec` choice from `FormatSettings`.
public final class CinemaRecorder {

    public private(set) var state: CinemaRecorderState = .idle
    public let outputURL: URL
    public let format: FormatSettings

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStartTime: CMTime = .invalid

    public init(outputURL: URL, format: FormatSettings) {
        self.outputURL = outputURL
        self.format = format
    }

    // MARK: - Lifecycle

    public func start(firstSampleTime: CMTime) throws {
        guard case .idle = state else { throw CinemaRecorderError.alreadyRecording }
        try? FileManager.default.removeItem(at: outputURL)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        } catch {
            state = .failed("writer init failed: \(error)")
            throw CinemaRecorderError.writerSetupFailed(error)
        }

        let settings = videoSettings(for: format)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true

        let pixelAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: format.resolution.size.width,
            kCVPixelBufferHeightKey as String: format.resolution.size.height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelAttrs
        )

        guard writer.canAdd(input) else {
            state = .failed("writer cannot add video input")
            throw CinemaRecorderError.writerSetupFailed(NSError(domain: "CinemaRecorder",
                                                                 code: 1,
                                                                 userInfo: nil))
        }
        writer.add(input)

        guard writer.startWriting() else {
            let err = writer.error ?? NSError(domain: "CinemaRecorder", code: 2, userInfo: nil)
            state = .failed("startWriting failed: \(err)")
            throw CinemaRecorderError.writerSetupFailed(err)
        }
        writer.startSession(atSourceTime: firstSampleTime)

        self.writer = writer
        self.videoInput = input
        self.pixelAdaptor = adaptor
        self.sessionStartTime = firstSampleTime
        self.state = .writing
    }

    public func append(_ sampleBuffer: CMSampleBuffer) throws {
        guard case .writing = state,
              let input = videoInput,
              input.isReadyForMoreMediaData else { return }
        if !input.append(sampleBuffer) {
            let err = writer?.error ?? NSError(domain: "CinemaRecorder", code: 3, userInfo: nil)
            state = .failed("append failed: \(err)")
            throw CinemaRecorderError.appendFailed(err)
        }
    }

    public func appendPixelBuffer(_ pixelBuffer: CVPixelBuffer,
                                   presentationTime: CMTime) throws {
        guard case .writing = state,
              let adaptor = pixelAdaptor,
              let input = videoInput,
              input.isReadyForMoreMediaData else { return }
        if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            let err = writer?.error ?? NSError(domain: "CinemaRecorder", code: 4, userInfo: nil)
            state = .failed("appendPixelBuffer failed: \(err)")
            throw CinemaRecorderError.appendFailed(err)
        }
    }

    public func finish(completion: @escaping (Result<URL, CinemaRecorderError>) -> Void) {
        guard case .writing = state, let writer = writer, let input = videoInput else {
            completion(.failure(.notRecording))
            return
        }
        state = .finishing
        input.markAsFinished()
        let url = outputURL
        writer.finishWriting { [weak self] in
            guard let self = self else { return }
            if writer.status == .completed {
                self.state = .finished(url)
                completion(.success(url))
            } else {
                let err = writer.error
                    ?? NSError(domain: "CinemaRecorder", code: 5, userInfo: nil)
                self.state = .failed("finish failed: \(err)")
                completion(.failure(.finishFailed(err)))
            }
        }
    }

    public func cancel() {
        guard let writer = writer else { return }
        videoInput?.markAsFinished()
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: outputURL)
        state = .idle
    }

    // MARK: - Codec mapping

    static func videoSettings(for format: FormatSettings) -> [String: Any] {
        let (w, h) = format.resolution.size
        let codec: AVVideoCodecType
        var compression: [String: Any] = [:]

        switch format.codec {
        case .proRes4444XQ:
            codec = .proRes4444
        case .proRes422HQ:
            codec = .proRes422HQ
        case .hevc10bit:
            codec = .hevc
            compression[AVVideoAverageBitRateKey] = bitrate(for: format, mbps: 100)
            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel as String
        case .hevc8bit:
            codec = .hevc
            compression[AVVideoAverageBitRateKey] = bitrate(for: format, mbps: 60)
            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel as String
        }

        var settings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h
        ]
        if !compression.isEmpty {
            settings[AVVideoCompressionPropertiesKey] = compression
        }
        return settings
    }

    private static func bitrate(for format: FormatSettings, mbps: Int) -> Int {
        let (w, h) = format.resolution.size
        let baselinePixels = 1920.0 * 1080.0
        let scale = Double(w * h) / baselinePixels
        let fpsScale = Double(format.frameRate) / 24.0
        return Int(Double(mbps) * 1_000_000 * scale * fpsScale)
    }
}

#endif
