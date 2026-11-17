import AVFoundation
import Combine
import SwiftUI

final class CameraCapture: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    @Published private(set) var authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @Published private(set) var ready = false
    @Published private(set) var capturing = false
    @Published private(set) var recording = false
    @Published private(set) var finishing = false
    @Published private(set) var seconds = 0
    @Published var error = ""
    var captured: ((URL, Bool) -> Void)?
    private let queue = DispatchQueue(label: "CommandV.Camera")
    private let photos = AVCapturePhotoOutput()
    private let movies = AVCaptureMovieFileOutput()
    private var configured = false
    private var wantsRecording = false
    private var audioAdded = false
    private var timer: Timer?
    private var startedAt: Date?
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: .main) { [weak self] _ in
            self?.ready = false
            self?.stopRecording()
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: .main) { [weak self] _ in
            self?.start()
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver); timer?.invalidate() }

    func authorize() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
            self.authorized = granted
            if granted { self.start() }
            else { self.error = "请在系统设置中允许 CommandV 使用相机" }
        }
    }
    func start() {
        authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        guard authorized else { return }
        queue.async {
            do {
                if !self.configured { try self.configure() }
                if !self.session.isRunning { self.session.startRunning() }
                let running = self.session.isRunning
                DispatchQueue.main.async { self.ready = running }
            } catch { self.fail(error) }
        }
    }
    func stop() {
        ready = false
        stopRecording()
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }
    private func configure() throws {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw BridgeError.message("这台设备没有可用的后置相机")
        }
        let input = try AVCaptureDeviceInput(device: camera)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        guard session.canAddInput(input) else { throw BridgeError.message("无法启动相机，请稍后重试") }
        session.addInput(input)
        guard session.canAddOutput(photos), session.canAddOutput(movies) else {
            session.removeInput(input)
            throw BridgeError.message("这台设备暂不支持拍摄，请使用相册发送")
        }
        session.addOutput(photos); session.addOutput(movies)
        photos.isHighResolutionCaptureEnabled = true
        movies.maxRecordedDuration = CMTime(seconds: 30, preferredTimescale: 600)
        configured = true
    }
    func takePhoto() {
        guard ready, !capturing, !recording, !finishing else { return }
        capturing = true; error = ""
        queue.async {
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.flashMode = .off
            settings.isHighResolutionPhotoEnabled = true
            self.photos.connection(with: .video)?.videoOrientation = .portrait
            self.photos.capturePhoto(with: settings, delegate: self)
        }
    }
    func startRecording() {
        guard ready, !capturing, !recording, !finishing else { return }
        let permission = AVCaptureDevice.authorizationStatus(for: .audio)
        guard permission == .authorized else {
            if permission == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        self.error = granted ? "麦克风已开启，请再次按住快门录像" : "录像需要麦克风权限，请在系统设置中开启"
                    }
                }
            } else { error = "录像需要麦克风权限，请在系统设置中开启" }
            return
        }
        recording = true; seconds = 0; error = ""
        queue.async {
            do {
                try self.addAudio()
                self.wantsRecording = true
                self.movies.connection(with: .video)?.videoOrientation = .portrait
                let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                self.movies.startRecording(to: file, recordingDelegate: self)
            } catch { self.fail(error) }
        }
    }
    private func addAudio() throws {
        guard !audioAdded else { return }
        guard let device = AVCaptureDevice.default(for: .audio) else { throw BridgeError.message("没有可用的麦克风") }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { throw BridgeError.message("麦克风正在被其他应用使用") }
        session.addInput(input); audioAdded = true
    }
    func stopRecording() {
        if recording { finishing = true }
        queue.async {
            self.wantsRecording = false
            if self.movies.isRecording { self.movies.stopRecording() }
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        do {
            if let error { throw error }
            guard let data = photo.fileDataRepresentation() else { throw BridgeError.message("未取得照片，请重新拍摄") }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            try data.write(to: file, options: .atomic)
            deliver(file, video: false)
        } catch { fail(error) }
    }
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        queue.async { if !self.wantsRecording { self.movies.stopRecording() } }
        DispatchQueue.main.async {
            self.startedAt = Date()
            self.timer?.invalidate()
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                guard let self, let started = self.startedAt else { return }
                self.seconds = min(30, Int(Date().timeIntervalSince(started)))
            }
        }
    }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Reaching maxRecordedDuration can include an error while still producing a valid movie.
        let completed = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false
        if let error, !completed {
            try? FileManager.default.removeItem(at: outputFileURL)
            fail(error)
        } else { deliver(outputFileURL, video: true) }
    }
    private func deliver(_ file: URL, video: Bool) {
        DispatchQueue.main.async {
            self.resetCapture()
            if let handler = self.captured { handler(file, video) }
            else { try? FileManager.default.removeItem(at: file) }
        }
    }
    private func fail(_ failure: Error) {
        DispatchQueue.main.async { self.resetCapture(); self.error = failure.localizedDescription }
    }
    private func resetCapture() {
        timer?.invalidate(); timer = nil; startedAt = nil
        capturing = false; recording = false; finishing = false
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class Surface: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            preview.connection?.videoOrientation = .portrait
        }
    }
    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.preview.session = session; view.preview.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: Surface, context: Context) {}
}
