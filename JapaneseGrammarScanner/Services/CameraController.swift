import AVFoundation
import CoreImage
import UIKit

final class CameraController: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle, running, denied, unavailable
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var hasLiveFrame = false
    @Published var torchOn = false {
        didSet { applyTorch() }
    }

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let frameQueue = DispatchQueue(label: "camera.frames", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var isConfigured = false

    private let frameOrientation: CGImagePropertyOrientation = .right
    private var latestBuffer: CVPixelBuffer?
    private var awaitingFirstFrame = false
    private let bufferLock = NSLock()
    private let ciContext = CIContext()

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.startSession()
                } else {
                    self?.setStatus(.denied)
                }
            }
        default:
            setStatus(.denied)
        }
    }

    func stop() {
        hasLiveFrame = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
        DispatchQueue.main.async { self.torchOn = false }
    }

    func captureStill() -> UIImage? {
        bufferLock.lock()
        let buffer = latestBuffer
        bufferLock.unlock()
        guard let buffer else { return nil }
        let ci = CIImage(cvPixelBuffer: buffer).oriented(frameOrientation)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                guard self.configure() else {
                    self.setStatus(.unavailable)
                    return
                }
            }
            if !self.session.isRunning {
                self.bufferLock.lock()
                self.latestBuffer = nil
                self.awaitingFirstFrame = true
                self.bufferLock.unlock()
                self.session.startRunning()
            }
            self.setStatus(.running)
        }
    }

    private func configure() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1920x1080

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        self.device = device

        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            device.unlockForConfiguration()
        }

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(videoOutput) else { return false }
        session.addOutput(videoOutput)
        isConfigured = true
        return true
    }

    private func applyTorch() {
        let on = torchOn
        sessionQueue.async { [weak self] in
            guard let device = self?.device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    private func setStatus(_ s: Status) {
        DispatchQueue.main.async { self.status = s }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        bufferLock.lock()
        latestBuffer = buffer
        let isFirstFrame = awaitingFirstFrame
        awaitingFirstFrame = false
        bufferLock.unlock()
        if isFirstFrame {
            DispatchQueue.main.async { self.hasLiveFrame = true }
        }
    }
}
