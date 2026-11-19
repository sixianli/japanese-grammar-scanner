import AVFoundation
import CoreImage
import UIKit

/// 相机采集 + 实时日文 OCR + 实时语法识别。
/// 每隔一小段时间取一帧送进 Vision，识别结果用于在取景画面上实时高亮语法点。
final class CameraController: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle, running, denied, unavailable
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var liveResult: ScanResult = .empty
    /// 方向校正后（竖屏）的帧尺寸，用于把归一化坐标换算到屏幕。
    @Published private(set) var frameSize: CGSize = .zero
    /// 本次启动后是否已经收到新画面。没收到之前取景层保持隐藏，
    /// 避免显示上一次停留时残留的旧画面（切回扫描页时会「闪一下」）。
    @Published private(set) var hasLiveFrame = false
    @Published var torchOn = false {
        didSet { applyTorch() }
    }

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let analysisQueue = DispatchQueue(label: "camera.analysis", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var isConfigured = false

    private let matcher: GrammarMatcher
    private let frameOrientation: CGImagePropertyOrientation = .right // 竖屏后置摄像头
    private var isAnalyzing = false
    private var lastAnalysis = Date.distantPast
    private let analysisInterval: TimeInterval = 0.6
    private var latestBuffer: CVPixelBuffer?
    private var awaitingFirstFrame = false
    private let bufferLock = NSLock()
    private let ciContext = CIContext()

    init(matcher: GrammarMatcher) {
        self.matcher = matcher
        super.init()
    }

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
        liveResult = .empty
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
        DispatchQueue.main.async { self.torchOn = false }
    }

    /// 定格当前画面，返回一张已经转正的图片，交给结果页做高精度识别。
    func captureStill() -> UIImage? {
        bufferLock.lock()
        let buffer = latestBuffer
        bufferLock.unlock()
        guard let buffer else { return nil }
        let ci = CIImage(cvPixelBuffer: buffer).oriented(frameOrientation)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - Session

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
        videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)
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
            DispatchQueue.main.async {
                self.liveResult = .empty // 丢掉停止前还在路上的旧识别结果
                self.hasLiveFrame = true
            }
        }

        // 在 analysisQueue（串行）上执行，所以这里同步识别即可；按时间间隔节流。
        guard !isAnalyzing, Date().timeIntervalSince(lastAnalysis) >= analysisInterval else { return }
        isAnalyzing = true
        defer {
            isAnalyzing = false
            lastAnalysis = Date()
        }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let orientedSize = CGSize(width: height, height: width) // .right 旋转后宽高互换

        guard let ocr = try? TextRecognizer.recognize(pixelBuffer: buffer, orientation: frameOrientation) else { return }
        let result = ScanAnalyzer.analyze(text: ocr.text, lines: ocr.lines, matcher: matcher)
        DispatchQueue.main.async {
            self.frameSize = orientedSize
            self.liveResult = result
        }
    }
}
