import Foundation

#if os(iOS)
import AVFoundation
import CoreMedia

/// Errors raised by the AVFoundation-backed cinema capture session.
public enum CinemaCaptureError: Error {
    case noVideoDevice
    case formatUnavailable(reason: String)
    case configurationFailed(Error)
    case notRunning
}

/// AVFoundation wrapper that drives the iOS back camera for cinematic
/// capture. All on-device tweaks (ISO, shutter, WB, focus) are exposed as
/// async-style methods that lock the device for the duration of the change.
///
/// This object does *not* own any rendering; it just produces sample
/// buffers via the supplied delegate. Pipeline grading and previewing are
/// handled elsewhere.
public final class CinemaCaptureSession: NSObject {

    public typealias SampleHandler = (CMSampleBuffer) -> Void

    public private(set) var settings: CinemaCaptureSettings
    public weak var sampleHandler: AnyObject?
    public var onSample: SampleHandler?

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "cinecamera.capture", qos: .userInitiated)
    private var device: AVCaptureDevice?

    public init(initial: CinemaCaptureSettings = CinemaCaptureSettings()) {
        self.settings = initial
        super.init()
    }

    // MARK: - Lifecycle

    public func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video,
                                                    position: .back) else {
            throw CinemaCaptureError.noVideoDevice
        }
        self.device = device

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.hd4K3840x2160) {
            session.sessionPreset = .hd4K3840x2160
        } else if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            throw CinemaCaptureError.configurationFailed(error)
        }

        videoOutput.setSampleBufferDelegate(self, queue: queue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        ]
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        try selectBestFormat(for: device)
    }

    public func start() {
        if !session.isRunning { session.startRunning() }
    }

    public func stop() {
        if session.isRunning { session.stopRunning() }
    }

    // MARK: - Manual controls

    public func setExposure(iso: Float, shutterAngle: Float) throws {
        guard let device = device else { throw CinemaCaptureError.notRunning }
        let shutterSeconds = ShutterAngleMath.shutterSpeed(angle: shutterAngle,
                                                            frameRate: settings.exposure.frameRate)
        let duration = CMTime(seconds: Double(shutterSeconds), preferredTimescale: 1_000_000)
        try lock(device) {
            let clampedISO = max(device.activeFormat.minISO, min(device.activeFormat.maxISO, iso))
            let minDur = device.activeFormat.minExposureDuration
            let maxDur = device.activeFormat.maxExposureDuration
            let clampedDur = CMTimeMaximum(minDur, CMTimeMinimum(maxDur, duration))
            device.setExposureModeCustom(duration: clampedDur, iso: clampedISO, completionHandler: nil)
            settings.exposure.iso = clampedISO
            settings.exposure.shutterAngle = shutterAngle
        }
    }

    public func setExposureBias(_ ev: Float) throws {
        guard let device = device else { throw CinemaCaptureError.notRunning }
        try lock(device) {
            let clamped = max(device.minExposureTargetBias, min(device.maxExposureTargetBias, ev))
            device.setExposureTargetBias(clamped, completionHandler: nil)
            settings.exposure.exposureBiasEV = clamped
        }
    }

    public func setWhiteBalance(kelvin: Float, tint: Float) throws {
        guard let device = device else { throw CinemaCaptureError.notRunning }
        let temperatureAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
            temperature: kelvin, tint: tint
        )
        let gains = device.deviceWhiteBalanceGains(for: temperatureAndTint)
        let normalized = clampGains(gains, to: device.maxWhiteBalanceGain)
        try lock(device) {
            device.setWhiteBalanceModeLocked(with: normalized, completionHandler: nil)
            settings.whiteBalance.kelvin = kelvin
            settings.whiteBalance.tint = tint
        }
    }

    public func setFocus(normalized: Float, continuous: Bool) throws {
        guard let device = device else { throw CinemaCaptureError.notRunning }
        try lock(device) {
            if continuous, device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            } else if device.isFocusModeSupported(.locked) {
                let clamped = max(0, min(1, normalized))
                device.setFocusModeLocked(lensPosition: clamped, completionHandler: nil)
            }
            settings.focus.normalizedDistance = normalized
            settings.focus.continuousAutoFocus = continuous
        }
    }

    public func setFrameRate(_ fps: Float) throws {
        guard let device = device else { throw CinemaCaptureError.notRunning }
        try lock(device) {
            let dur = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMinFrameDuration = dur
            device.activeVideoMaxFrameDuration = dur
            settings.exposure.frameRate = fps
            settings.format.frameRate = fps
        }
    }

    // MARK: - Helpers

    private func lock(_ device: AVCaptureDevice, _ body: () throws -> Void) throws {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            try body()
        } catch {
            throw CinemaCaptureError.configurationFailed(error)
        }
    }

    private func clampGains(_ gains: AVCaptureDevice.WhiteBalanceGains,
                             to maxGain: Float) -> AVCaptureDevice.WhiteBalanceGains {
        let lo: Float = 1.0
        return AVCaptureDevice.WhiteBalanceGains(
            redGain:   max(lo, min(maxGain, gains.redGain)),
            greenGain: max(lo, min(maxGain, gains.greenGain)),
            blueGain:  max(lo, min(maxGain, gains.blueGain))
        )
    }

    private func selectBestFormat(for device: AVCaptureDevice) throws {
        let target = settings.format.resolution.size
        let fps = settings.format.frameRate
        let candidates = device.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return Int(dims.width) == target.width && Int(dims.height) == target.height
        }
        guard let chosen = candidates.first(where: { format in
            format.videoSupportedFrameRateRanges.contains { range in
                Float(range.minFrameRate) <= fps && Float(range.maxFrameRate) >= fps
            }
        }) ?? candidates.first else {
            throw CinemaCaptureError.formatUnavailable(reason: "no \(target.width)x\(target.height) @ \(fps)fps")
        }
        try lock(device) {
            device.activeFormat = chosen
            let dur = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMinFrameDuration = dur
            device.activeVideoMaxFrameDuration = dur
        }
    }
}

extension CinemaCaptureSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        onSample?(sampleBuffer)
    }
}

#endif
