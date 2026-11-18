import Foundation
import Combine
import UIKit
import CoreImage
import ActivityKit
#if targetEnvironment(simulator)
// ScreenCaptureKit ships only in the device SDK; simulator tests cover the entry and transfer flow.
@available(iOS 27.0, *)
@MainActor final class ScreenCaptureSession: ObservableObject {
    static let shared = ScreenCaptureSession()
    @Published var message = ""
    @Published private(set) var active = false
    let starting = false, recording = false, finishing = false, pendingShot = false
    let files: [URL] = []
    let seconds = 0
    let isVideo = false
    func presentPicker() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-screen-capture-active") {
            active = true
            return
        }
        #endif
        message = "跨 App 屏幕采集需要在 iPhone 真机测试。"
    }
    func requestFrame() throws { throw BridgeError.message("屏幕采集需要 iPhone 真机。") }
    func toggleRecording() async throws { throw BridgeError.message("屏幕采集需要 iPhone 真机。") }
    func stop() async { active = false }
    func remove(_ file: URL) throws {}
    func clearImported() throws {}
}
#else
@preconcurrency import ScreenCaptureKit

@available(iOS 27.0, *)
@MainActor final class ScreenCaptureSession: NSObject, ObservableObject {
    static let shared = ScreenCaptureSession()
    @Published private(set) var active = false
    @Published private(set) var starting = false
    @Published private(set) var recording = false
    @Published private(set) var finishing = false
    @Published private(set) var pendingShot = false
    @Published private(set) var files: [URL] = []
    @Published private(set) var seconds = 0
    @Published var message = ""
    private var stream: SCStream?
    private var latestFrame: CVPixelBuffer?
    private var output: SCRecordingOutput?
    private var pendingVideo: URL?
    private var videoStart: Date?
    private var timer: Timer?
    private var activity: Activity<ScreenCaptureAttributes>?
    private var generation = UUID()
    private var shot: (id: UUID, task: Task<Void, Never>, background: UIBackgroundTaskIdentifier)?
    private var shotFailed = false
    private let context = CIContext()
    private lazy var observer = ScreenCaptureObserver(owner: self)
    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ScreenDraft", isDirectory: true)
    }
    var isVideo: Bool { files.first?.pathExtension == "mp4" }
    private var canCapture: Bool { active && !recording && !finishing && !isVideo && files.count < 10 }

    override init() {
        super.init()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let manifest = directory.appendingPathComponent("manifest.json")
            if let data = try? Data(contentsOf: manifest) {
                let names = try JSONDecoder().decode([String].self, from: data)
                files = names.filter { $0 == URL(fileURLWithPath: $0).lastPathComponent }.map { directory.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            }
        } catch { message = error.localizedDescription }
    }

    func presentPicker() {
        guard !starting, !active else { return }
        #if targetEnvironment(simulator)
        message = "跨 App 屏幕采集需要在 iPhone 真机测试。"
        return
        #else
        starting = true; message = "请在系统面板选择整个屏幕并允许共享。"
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        picker.defaultConfiguration = configuration
        picker.add(observer); picker.isActive = true; picker.present()
        #endif
    }

    fileprivate func begin(_ filter: SCContentFilter) async {
        guard !active else { return }
        starting = false
        let configuration = SCStreamConfiguration()
        do {
            let next = SCStream(filter: filter, configuration: configuration, delegate: observer)
            try next.addStreamOutput(observer, type: .screen, sampleHandlerQueue: .main)
            try await next.startCapture()
            stream = next; active = true; generation = UUID(); shotFailed = false
            message = "已开始采集。切到目标 App，再用灵动岛或操作按钮截取。"
            startActivity()
        } catch { fail(error); deactivatePicker() }
    }

    fileprivate func receive(_ frame: CVPixelBuffer) { if active { latestFrame = frame } }
    fileprivate func fail(_ error: Error) { starting = false; message = error.localizedDescription }
    fileprivate func cancelled() { starting = false; message = "已取消屏幕采集"; deactivatePicker() }
    private func deactivatePicker() { SCContentSharingPicker.shared.remove(observer); SCContentSharingPicker.shared.isActive = false }

    func requestFrame() throws {
        guard !pendingShot else { return }
        guard canCapture else { throw BridgeError.message(active ? "请先处理当前素材；每组最多 10 张，录像时不能截图。" : "请先在 CommandC 开始屏幕采集。") }
        pendingShot = true
        let id = UUID()
        let current = generation
        // End the intent response before sampling so the system can dismiss the interaction.
        let background = UIApplication.shared.beginBackgroundTask(withName: "CommandV screenshot") { [weak self] in
            Task { @MainActor in
                guard let self, self.shot?.id == id else { return }
                self.shot?.task.cancel()
                self.endShotBackground(id)
            }
        }
        shot = (id, Task { await finishShot(id: id, generation: current) }, background)
    }

    private func finishShot(id: UUID, generation current: UUID) async {
        defer { clearShot(id) }
        do {
            try await Task.sleep(for: .milliseconds(1500))
            try saveFrame(generation: current)
        } catch {
            guard generation == current else { return }
            shotFailed = true
            message = error is CancellationError ? "截图未完成，请再试一次。" : error.localizedDescription
            await updateActivity()
            return
        }
        shotFailed = false
        message = ""
        await updateActivity()
        if generation == current, files.count == 10 {
            // Give the last saved count time to appear before the activity ends.
            try? await Task.sleep(for: .milliseconds(750))
            guard generation == current else { return }
            clearShot(id)
            await stop()
        }
    }

    private func clearShot(_ id: UUID) {
        guard shot?.id == id else { return }
        endShotBackground(id)
        shot = nil
        pendingShot = false
    }

    private func endShotBackground(_ id: UUID) {
        guard let shot, shot.id == id, shot.background != .invalid else { return }
        self.shot?.background = .invalid
        UIApplication.shared.endBackgroundTask(shot.background)
    }

    private func saveFrame(generation current: UUID) throws {
        guard active, current == generation, let latestFrame else { throw BridgeError.message("未取得屏幕画面，请重新开始采集。") }
        guard UIApplication.shared.applicationState != .active else { throw BridgeError.message("请先切到要截取的 App，再使用灵动岛或操作按钮。") }
        let image = CIImage(cvPixelBuffer: latestFrame)
        guard let cgImage = context.createCGImage(image, from: image.extent), let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.94) else { throw BridgeError.message("截图转换失败") }
        guard data.count <= 32 * 1024 * 1024, try totalBytes() + data.count <= 100_000_000 else { throw BridgeError.message("当前截图组已达 100 MB，请先发送。") }
        let file = directory.appendingPathComponent(UUID().uuidString + ".jpg")
        try data.write(to: file, options: .atomic)
        do { try persist(files + [file]); files.append(file) }
        catch { try? FileManager.default.removeItem(at: file); throw error }
    }

    func toggleRecording() async throws {
        guard active, let stream, !finishing, !pendingShot else { throw BridgeError.message("请先在 CommandC 开始屏幕采集。") }
        if recording { try endRecording(); return }
        guard files.isEmpty else { throw BridgeError.message("请先发送或清空当前截图组，再开始录屏。") }
        let file = directory.appendingPathComponent(UUID().uuidString + ".mp4")
        let configuration = SCRecordingOutputConfiguration(); configuration.outputURL = file
        let next = SCRecordingOutput(configuration: configuration, delegate: observer)
        try stream.addRecordingOutput(next)
        output = next; pendingVideo = file; recording = true; seconds = 0; videoStart = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.videoStart, self.recording else { return }
                self.seconds = Int(Date().timeIntervalSince(start))
                if Date().timeIntervalSince(start) >= 29.5 { do { try self.endRecording() } catch { self.fail(error) } }
            }
        }
        await updateActivity()
    }

    private func endRecording() throws {
        guard let output, let stream, !finishing else { return }
        try stream.removeRecordingOutput(output)
        self.output = nil; recording = false; finishing = true; timer?.invalidate(); timer = nil
        Task { await updateActivity() }
    }

    fileprivate func recordingFinished(_ error: Error? = nil) {
        timer?.invalidate(); timer = nil; output = nil; recording = false; finishing = false
        if let error { fail(error); if let pendingVideo { try? FileManager.default.removeItem(at: pendingVideo) } }
        else if let file = pendingVideo {
            do { try persist([file]); files = [file]; message = "录屏已保存，点查看后确认发送。" }
            catch { fail(error) }
        }
        pendingVideo = nil
        Task { await stop() }
    }

    func stop() async {
        guard !finishing else { return }
        if recording { do { try endRecording() } catch { fail(error) }; return }
        generation = UUID()
        if let shot { shot.task.cancel(); clearShot(shot.id) }
        pendingShot = false; starting = false; active = false; latestFrame = nil
        if let stream { try? await stream.stopCapture() }
        stream = nil; deactivatePicker()
        if let activity { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate) }
        activity = nil
    }

    fileprivate func streamStopped(_ error: Error) {
        active = false; starting = false; latestFrame = nil; generation = UUID(); fail(error)
        if !recording && !finishing { Task { await stop() } }
    }

    func remove(_ file: URL) throws {
        guard !recording, !finishing, !pendingShot else { return }
        let remaining = files.filter { $0 != file }
        try persist(remaining); files = remaining
        try? FileManager.default.removeItem(at: file)
        Task { await updateActivity() }
    }

    func clearImported() throws {
        guard !recording, !finishing, !pendingShot else { throw BridgeError.message("请等待采集完成") }
        try persist([])
        files.forEach { try? FileManager.default.removeItem(at: $0) }; files = []
    }

    private func persist(_ values: [URL]) throws { try JSONEncoder().encode(values.map(\.lastPathComponent)).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic) }
    private func totalBytes() throws -> Int { try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) } }
    private var state: ScreenCaptureAttributes.ContentState {
        .init(count: files.count, recording: recording, pending: finishing, startedAt: videoStart,
              message: recording ? "录屏中 · 最长 30 秒" : shotFailed ? "截图未保存" : "屏幕采集",
              shotFailed: shotFailed)
    }
    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { message = "采集已开始；请开启实时活动，或使用操作按钮的 CommandC 快捷指令。"; return }
        do { activity = try Activity.request(attributes: ScreenCaptureAttributes(), content: ActivityContent(state: state, staleDate: nil), pushType: nil) }
        catch { message = "采集已开始，但实时活动无法显示：\(error.localizedDescription)" }
    }
    private func updateActivity() async { if let activity { await activity.update(ActivityContent(state: state, staleDate: nil)) } }
}

@available(iOS 27.0, *)
private final class ScreenCaptureObserver: NSObject, SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate, SCRecordingOutputDelegate {
    private weak var owner: ScreenCaptureSession?
    init(owner: ScreenCaptureSession) { self.owner = owner }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) { Task { @MainActor in await owner?.begin(filter) } }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) { Task { @MainActor in owner?.cancelled() } }
    func contentSharingPickerStartDidFailWithError(_ error: Error) { Task { @MainActor in owner?.fail(error) } }
    func stream(_ stream: SCStream, didStopWithError error: Error) { Task { @MainActor in owner?.streamStopped(error) } }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let buffer = sampleBuffer.imageBuffer else { return }
        Task { @MainActor in owner?.receive(buffer) }
    }
    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {}
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { Task { @MainActor in owner?.recordingFinished() } }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) { Task { @MainActor in owner?.recordingFinished(error) } }
}
#endif
