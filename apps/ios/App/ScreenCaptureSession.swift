import Foundation
import Combine
import UIKit
import CoreImage
import ActivityKit

@available(iOS 27.0, *)
@MainActor final class ScreenCaptureLiveActivity {
    private typealias CaptureActivity = Activity<ScreenCaptureAttributes>
    private var current: CaptureActivity?
    private var collectingShot = false
    private var dismissals: [String: (task: Task<Void, Never>, background: UIBackgroundTaskIdentifier)] = [:]
    var isShowing: Bool { current != nil }

    func start(_ state: ScreenCaptureAttributes.ContentState) throws {
        dismissCurrent()
        current = try CaptureActivity.request(attributes: ScreenCaptureAttributes(), content: ActivityContent(state: state, staleDate: nil), pushType: nil)
    }

    func update(_ state: ScreenCaptureAttributes.ContentState, alert: AlertConfiguration? = nil) async {
        var display = state
        display.collectingShot = collectingShot ? true : nil
        await current?.update(ActivityContent(state: display, staleDate: nil), alertConfiguration: alert)
    }

    func acknowledgeShot(showResult: Bool = false, state: () -> ScreenCaptureAttributes.ContentState) async {
        guard let activityId = current?.id else { return }
        collectingShot = true
        await update(state())
        try? await Task.sleep(for: .milliseconds(440))
        guard current?.id == activityId else { return }
        collectingShot = false
        let saved = state()
        let alert = showResult ? AlertConfiguration(title: "CommandC", body: "Screenshots saved: \(saved.count)", sound: .named("ScreenCaptureSaved.caf")) : nil
        await update(saved, alert: alert)
    }

    func dismissCurrent() {
        guard let current else { return }
        self.current = nil
        collectingShot = false
        dismiss(current)
    }

    func dismissOrphans() {
        for activity in CaptureActivity.activities where activity.id != current?.id { dismiss(activity) }
    }

    func dismissAll() -> [Task<Void, Never>] {
        dismissCurrent()
        dismissOrphans()
        return dismissals.values.map(\.task)
    }

    private func dismiss(_ activity: CaptureActivity) {
        let id = activity.id
        guard dismissals[id] == nil else { return }
        // Acquire time before suspending so a quick return to the Home Screen cannot interrupt the dismissal.
        let background = UIApplication.shared.beginBackgroundTask(withName: "CommandC dismiss capture activity") { [weak self] in
            Task { @MainActor in self?.releaseBackground(for: id) }
        }
        dismissals[id] = (Task { [weak self] in
            defer {
                self?.releaseBackground(for: id)
                self?.dismissals[id] = nil
            }
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }, background)
    }

    private func releaseBackground(for id: String) {
        guard let background = dismissals[id]?.background, background != .invalid else { return }
        dismissals[id]?.background = .invalid
        UIApplication.shared.endBackgroundTask(background)
    }
}

@available(iOS 27.0, *)
@MainActor private final class RecordingSaveWatchdog {
    private var task: Task<Void, Never>?

    func arm(after delay: Duration = .seconds(12), expire: @escaping @MainActor () -> Void) {
        cancel()
        task = Task {
            do { try await Task.sleep(for: delay) } catch { return }
            expire()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

#if targetEnvironment(simulator)
// ScreenCaptureKit ships only in the device SDK; simulator tests cover the entry and transfer flow.
@available(iOS 27.0, *)
@MainActor final class ScreenCaptureSession: ObservableObject {
    static let shared = ScreenCaptureSession()
    @Published var message = ""
    @Published private(set) var active = false
    @Published private(set) var batchLimit = CaptureBatch.defaultLimit
    @Published private(set) var finishing = false
    @Published private(set) var ending = false
    @Published private(set) var recording = false
    let starting = false, pendingShot = false
    let files: [URL] = []
    let seconds = 0
    let isVideo = false
    private let saveWatchdog = RecordingSaveWatchdog()
    private let liveActivity = ScreenCaptureLiveActivity()
    #if DEBUG
    private var simulateLiveActivity: Bool { ProcessInfo.processInfo.arguments.contains("--ui-screen-capture-activity") }
    private var simulatedStallCount = 0
    #endif
    func presentPicker(limit: Int) {
        batchLimit = CaptureBatch.limit(limit)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-stalled-recording") {
            active = true
            // The first attempt exercises the cancel button even when UI automation runs slowly.
            simulateSaving(after: simulatedStallCount == 0 ? .seconds(45) : .seconds(5))
            simulatedStallCount += 1
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-review-recording") {
            active = true
            recording = true
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-screen-capture-active") {
            active = true
            if simulateLiveActivity {
                do {
                    let state = ScreenCaptureAttributes.ContentState(count: 0, recording: false, pending: false, message: "Capture active")
                    try liveActivity.start(state)
                    message = "Capture Live Activity started."
                } catch { message = error.localizedDescription }
            }
            return
        }
        #endif
        message = String(localized: "Cross-app screen capture is available on an iPhone.")
    }
    func requestFrame(after delay: Duration = .milliseconds(1500), showResult: Bool = false) throws { throw BridgeError.message(String(localized: "Screen capture requires an iPhone.")) }
    func toggleRecording() async throws { throw BridgeError.message(String(localized: "Screen capture requires an iPhone.")) }
    func requestStopConfirmation() async {}
    func confirmStop() async {}
    func dismissOrphanedActivities() { liveActivity.dismissOrphans() }
    func updateBatchLimit(_ limit: Int) { batchLimit = CaptureBatch.limit(limit) }
    func prepareReview() {
        liveActivity.dismissCurrent()
        if recording { simulateSaving(after: .seconds(30)) }
        else if !finishing { active = false }
    }
    func stop() async {
        guard !ending else { return }
        ending = true
        defer { ending = false }
        let dismissals = liveActivity.dismissAll()
        if finishing { finishSaving(String(localized: "Recording save canceled.")) }
        else { active = false }
        for dismissal in dismissals { await dismissal.value }
        #if DEBUG
        if simulateLiveActivity {
            let stillVisible = Activity<ScreenCaptureAttributes>.activities.contains { $0.activityState == .active || $0.activityState == .stale }
            if !dismissals.isEmpty && !stillVisible { message = "Capture Live Activity dismissed." }
        }
        #endif
    }
    private func finishSaving(_ result: String) {
        saveWatchdog.cancel()
        finishing = false
        active = false
        message = result
    }
    private func simulateSaving(after delay: Duration = .seconds(5)) {
        recording = false
        finishing = true
        message = ""
        saveWatchdog.arm(after: delay) { [weak self] in
            self?.finishSaving(String(localized: "Saving the recording timed out. You can start a new capture."))
        }
    }
    func remove(_ file: URL) throws {}
    func clearImported() throws {}
}
#else
@preconcurrency import ScreenCaptureKit

@available(iOS 27.0, *)
@MainActor final class ScreenCaptureSession: NSObject, ObservableObject {
    static let shared = ScreenCaptureSession()
    @Published private(set) var active = false
    @Published private(set) var batchLimit = CaptureBatch.defaultLimit
    @Published private(set) var starting = false
    @Published private(set) var recording = false
    @Published private(set) var finishing = false
    @Published private(set) var ending = false
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
    private let saveWatchdog = RecordingSaveWatchdog()
    private var saveBackground = UIBackgroundTaskIdentifier.invalid
    private let liveActivity = ScreenCaptureLiveActivity()
    private var generation = UUID()
    private var shot: (id: UUID, task: Task<Void, Never>, background: UIBackgroundTaskIdentifier)?
    private var shotFailed = false
    private var stopConfirmationDeadline: Date?
    private var stopConfirmationTask: Task<Void, Never>?
    private let context = CIContext()
    private lazy var observer = ScreenCaptureObserver(owner: self)
    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ScreenDraft", isDirectory: true)
    }
    var isVideo: Bool { files.first?.pathExtension == "mp4" }
    private var canCapture: Bool { active && !recording && !finishing && !isVideo && files.count < batchLimit }

    func updateBatchLimit(_ limit: Int) {
        let next = CaptureBatch.limit(limit)
        guard batchLimit != next else { return }
        batchLimit = next
        if active, !recording, !finishing, !pendingShot, !isVideo, files.count >= next {
            resetCapture(keepingReview: true)
        } else {
            Task { await updateActivity() }
        }
    }

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

    func presentPicker(limit: Int) {
        guard !starting, !active, !finishing, !ending else { return }
        batchLimit = CaptureBatch.limit(limit)
        #if targetEnvironment(simulator)
        message = String(localized: "Cross-app screen capture is available on an iPhone.")
        return
        #else
        starting = true; message = String(localized: "Choose your entire screen and confirm sharing.")
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        picker.defaultConfiguration = configuration
        picker.add(observer); picker.isActive = true; picker.present()
        #endif
    }

    fileprivate func begin(_ filter: SCContentFilter) async {
        guard starting, !active, stream == nil else { return }
        let configuration = SCStreamConfiguration()
        let next = SCStream(filter: filter, configuration: configuration, delegate: observer)
        stream = next
        do {
            try next.addStreamOutput(observer, type: .screen, sampleHandlerQueue: .main)
            try await next.startCapture()
            guard stream === next else { try? await next.stopCapture(); return }
            starting = false; active = true; generation = UUID(); shotFailed = false
            message = String(localized: "Capture is ready. Switch apps, then press and hold the Dynamic Island or Action button.")
            startActivity()
        } catch {
            guard stream === next else { return }
            fail(error)
            resetCapture()
        }
    }

    fileprivate func receive(_ frame: CVPixelBuffer, from source: SCStream) {
        if active, stream === source { latestFrame = frame }
    }
    fileprivate func fail(_ error: Error) { starting = false; message = error.localizedDescription }
    fileprivate func cancelled() {
        guard starting else { return }
        message = String(localized: "Screen capture cancelled.")
        resetCapture()
    }
    private func deactivatePicker() { SCContentSharingPicker.shared.remove(observer); SCContentSharingPicker.shared.isActive = false }

    func requestFrame(after delay: Duration = .milliseconds(1500), showResult: Bool = false) throws {
        guard !pendingShot else { return }
        guard canCapture else { throw BridgeError.message(active ? String(localized: "Finish recording or review the current batch before taking another screenshot.") : String(localized: "Start screen capture in CommandC first.")) }
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
        shot = (id, Task { await finishShot(id: id, generation: current, after: delay, showResult: showResult) }, background)
    }

    private func finishShot(id: UUID, generation current: UUID, after delay: Duration, showResult: Bool) async {
        defer { clearShot(id) }
        do {
            try await Task.sleep(for: delay)
            try saveFrame(generation: current)
        } catch {
            guard generation == current else { return }
            shotFailed = true
            message = error is CancellationError ? String(localized: "Couldn’t capture the screen. Try again.") : error.localizedDescription
            await updateActivity()
            return
        }
        shotFailed = false
        message = ""
        await liveActivity.acknowledgeShot(showResult: showResult) { state }
        if generation == current, files.count >= batchLimit {
            clearShot(id)
            resetCapture(keepingReview: true)
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
        guard active, current == generation, let latestFrame else { throw BridgeError.message(String(localized: "No screen image was available. Restart screen capture.")) }
        guard UIApplication.shared.applicationState != .active else { throw BridgeError.message(String(localized: "Switch to the app you want to capture before using the Dynamic Island or Action button.")) }
        let image = CIImage(cvPixelBuffer: latestFrame)
        guard let cgImage = context.createCGImage(image, from: image.extent), let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.94) else { throw BridgeError.message(String(localized: "Couldn’t convert the screenshot.")) }
        guard data.count <= 32 * 1024 * 1024, try totalBytes() + data.count <= 100_000_000 else { throw BridgeError.message(String(localized: "Send the current batch first. It has reached 100 MB.")) }
        let file = directory.appendingPathComponent(UUID().uuidString + ".jpg")
        try data.write(to: file, options: .atomic)
        do { try persist(files + [file]); files.append(file) }
        catch { try? FileManager.default.removeItem(at: file); throw error }
    }

    func toggleRecording() async throws {
        guard active, let stream, !finishing, !pendingShot else { throw BridgeError.message(String(localized: "Start screen capture in CommandC first.")) }
        if recording { try endRecording(); return }
        guard files.isEmpty else { throw BridgeError.message(String(localized: "Send or clear your screenshots before recording.")) }
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
        guard let output, let stream, recording else { return }
        beginSaving(output)
        do { try stream.removeRecordingOutput(output) }
        catch { recordingFinished(output, error: error); throw error }
    }

    private func beginSaving(_ output: SCRecordingOutput) {
        recording = false
        finishing = true
        timer?.invalidate()
        timer = nil
        let timedOut = BridgeError.message(String(localized: "Saving the recording timed out. You can start a new capture."))
        saveBackground = UIApplication.shared.beginBackgroundTask(withName: "CommandC save recording") { [weak self, weak output] in
            Task { @MainActor in
                if let output { self?.recordingFinished(output, error: timedOut) }
            }
        }
        saveWatchdog.arm { [weak self, weak output] in
            if let output { self?.recordingFinished(output, error: timedOut) }
        }
        Task { await updateActivity() }
    }

    fileprivate func recordingFinished(_ finishedOutput: SCRecordingOutput, error: Error? = nil) {
        guard output === finishedOutput else { return }
        let file = pendingVideo
        var saved = false
        defer { resetCapture(keepingReview: saved) }
        if let error {
            if let file { try? FileManager.default.removeItem(at: file) }
            message = error.localizedDescription
        } else if let file {
            do {
                guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else {
                    throw BridgeError.message(String(localized: "No video was saved. You can start a new capture."))
                }
                files = [file]
                try persist(files)
                saved = true
                message = String(localized: "Recording saved. Tap Review, then send it from the preview.")
            } catch { fail(error) }
        }
    }

    func requestStopConfirmation() async {
        guard active || finishing || liveActivity.isShowing else { dismissOrphanedActivities(); return }
        stopConfirmationTask?.cancel()
        let deadline = Date().addingTimeInterval(8)
        stopConfirmationDeadline = deadline
        stopConfirmationTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) }
            catch { return }
            guard let self, self.stopConfirmationDeadline == deadline else { return }
            self.stopConfirmationDeadline = nil
            self.stopConfirmationTask = nil
            await self.updateActivity()
        }
        await updateActivity()
    }

    func confirmStop() async {
        guard let deadline = stopConfirmationDeadline, deadline > Date(), active || finishing || liveActivity.isShowing else {
            dismissOrphanedActivities()
            return
        }
        await stop()
    }

    func prepareReview() {
        liveActivity.dismissCurrent()
        if recording {
            do { try endRecording() } catch { fail(error) }
        } else if !finishing {
            resetCapture()
        }
    }

    func stop() async {
        guard !ending else { return }
        ending = true
        defer { ending = false }
        let dismissals = liveActivity.dismissAll()
        if finishing, let output {
            recordingFinished(output, error: BridgeError.message(String(localized: "Recording save canceled.")))
        } else if recording {
            do { try endRecording() } catch { fail(error) }
        } else {
            message = ""
            resetCapture()
        }
        for dismissal in dismissals { await dismissal.value }
    }

    func dismissOrphanedActivities() { liveActivity.dismissOrphans() }

    private func resetCapture(keepingReview: Bool = false) {
        if !keepingReview { liveActivity.dismissCurrent() }
        saveWatchdog.cancel()
        stopConfirmationTask?.cancel()
        stopConfirmationTask = nil
        stopConfirmationDeadline = nil
        timer?.invalidate()
        timer = nil
        videoStart = nil
        output = nil; pendingVideo = nil; recording = false; finishing = false
        generation = UUID()
        if let shot { shot.task.cancel(); clearShot(shot.id) }
        pendingShot = false; starting = false; active = false; latestFrame = nil
        let oldStream = stream
        stream = nil
        deactivatePicker()
        if let oldStream { Task { try? await oldStream.stopCapture() } }
        if saveBackground != .invalid {
            UIApplication.shared.endBackgroundTask(saveBackground)
            saveBackground = .invalid
        }
        if keepingReview { Task { await updateActivity() } }
    }

    fileprivate func streamStopped(_ source: SCStream, error: Error) {
        guard stream === source else { return }
        if let output {
            message = error.localizedDescription
            if !finishing { beginSaving(output) }
        }
        else { fail(error); resetCapture() }
    }

    func remove(_ file: URL) throws {
        guard !recording, !finishing, !pendingShot else { return }
        let remaining = files.filter { $0 != file }
        try persist(remaining); files = remaining
        try? FileManager.default.removeItem(at: file)
        Task { await updateActivity() }
    }

    func clearImported() throws {
        guard !recording, !finishing, !pendingShot else { throw BridgeError.message(String(localized: "Wait for the capture to finish.")) }
        try persist([])
        files.forEach { try? FileManager.default.removeItem(at: $0) }; files = []
    }

    private func persist(_ values: [URL]) throws { try JSONEncoder().encode(values.map(\.lastPathComponent)).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic) }
    private func totalBytes() throws -> Int { try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) } }
    private var state: ScreenCaptureAttributes.ContentState {
        .init(count: files.count, recording: recording, pending: finishing, startedAt: videoStart,
              message: !active ? String(localized: "Ready to Review") : recording ? String(localized: "Recording · Up to 30 seconds") : shotFailed ? String(localized: "Not saved") : String(localized: "Capture active"),
              shotFailed: shotFailed, confirmingStop: stopConfirmationDeadline.map { $0 > Date() }, batchLimit: batchLimit, readyToReview: !active)
    }
    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { message = String(localized: "Capture is ready. Enable Live Activities or use the CommandC shortcut with the Action button."); return }
        do { try liveActivity.start(state) }
        catch { message = String(localized: "Capture is ready, but the Live Activity is unavailable: \(error.localizedDescription)") }
    }
    private func updateActivity() async { await liveActivity.update(state) }
}

@available(iOS 27.0, *)
private final class ScreenCaptureObserver: NSObject, SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate, SCRecordingOutputDelegate {
    private weak var owner: ScreenCaptureSession?
    init(owner: ScreenCaptureSession) { self.owner = owner }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) { Task { @MainActor in await owner?.begin(filter) } }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) { Task { @MainActor in owner?.cancelled() } }
    func contentSharingPickerStartDidFailWithError(_ error: Error) { Task { @MainActor in owner?.fail(error) } }
    func stream(_ stream: SCStream, didStopWithError error: Error) { Task { @MainActor in owner?.streamStopped(stream, error: error) } }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let buffer = sampleBuffer.imageBuffer else { return }
        Task { @MainActor in owner?.receive(buffer, from: stream) }
    }
    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {}
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { Task { @MainActor in owner?.recordingFinished(recordingOutput) } }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) { Task { @MainActor in owner?.recordingFinished(recordingOutput, error: error) } }
}
#endif
