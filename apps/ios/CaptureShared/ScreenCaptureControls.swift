import ActivityKit
import AppIntents

private struct CaptureRoutingError: LocalizedError {
    var errorDescription: String? { "系统未将操作交给 CommandV，请重新打开应用并开始屏幕采集。" }
}

@available(iOS 17.0, *)
struct ScreenCaptureAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var count: Int
        var recording: Bool
        var pending: Bool
        var startedAt: Date?
        var message: String
    }
}

@available(iOS 27.0, *)
struct CaptureScreenFrameIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "CommandV 截取一张"
    static var description = IntentDescription("已开始屏幕采集时，1.5 秒后截取当前画面并加入待发组。")
    static var openAppWhenRun = false
    static var supportedModes: IntentModes { .background }
    func perform() async throws -> some IntentResult {
        #if COMMANDV_APP
        try await ScreenCaptureSession.shared.captureFrame()
        #else
        throw CaptureRoutingError()
        #endif
        return .result()
    }
}

@available(iOS 27.0, *)
struct ToggleScreenRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "CommandV 开始或停止录屏"
    static var openAppWhenRun = false
    static var supportedModes: IntentModes { .background }
    func perform() async throws -> some IntentResult {
        #if COMMANDV_APP
        try await ScreenCaptureSession.shared.toggleRecording()
        #else
        throw CaptureRoutingError()
        #endif
        return .result()
    }
}

@available(iOS 27.0, *)
struct StopScreenCaptureIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "停止 CommandV 屏幕采集"
    static var openAppWhenRun = false
    static var supportedModes: IntentModes { .background }
    func perform() async throws -> some IntentResult {
        #if COMMANDV_APP
        await ScreenCaptureSession.shared.stop()
        #else
        throw CaptureRoutingError()
        #endif
        return .result()
    }
}

#if COMMANDV_APP
@available(iOS 27.0, *)
struct ScreenCaptureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CaptureScreenFrameIntent(), phrases: ["用\(.applicationName)截取一张"], shortTitle: "截取一张", systemImageName: "rectangle.dashed")
        AppShortcut(intent: ToggleScreenRecordingIntent(), phrases: ["用\(.applicationName)录屏"], shortTitle: "开始或停止录屏", systemImageName: "record.circle")
    }
}
#endif
