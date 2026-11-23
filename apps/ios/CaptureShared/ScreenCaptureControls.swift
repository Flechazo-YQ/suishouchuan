import ActivityKit
import AppIntents

private struct CaptureRoutingError: LocalizedError {
    var errorDescription: String? { String(localized: "Reopen CommandC and start screen capture to use this shortcut.") }
}

@available(iOS 17.0, *)
struct ScreenCaptureAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var count: Int
        var recording: Bool
        var pending: Bool
        var startedAt: Date?
        var message: String
        var shotFailed: Bool?
        var confirmingStop: Bool?
    }
}

@available(iOS 27.0, *)
struct CaptureScreenFrameIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Capture a Screenshot with CommandC"
    static var description = IntentDescription("After screen capture starts, save the current screen to your batch after 1.5 seconds.")
    static var openAppWhenRun = false
    static var supportedModes: IntentModes { .background }
    func perform() async throws -> some IntentResult {
        #if COMMANDV_APP
        try await ScreenCaptureSession.shared.requestFrame()
        #else
        throw CaptureRoutingError()
        #endif
        return .result()
    }
}

@available(iOS 27.0, *)
struct ToggleScreenRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start or Stop Screen Recording with CommandC"
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
struct RequestStopScreenCaptureIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Request to End CommandC Screen Capture"
    static var openAppWhenRun = false
    static var supportedModes: IntentModes { .background }
    func perform() async throws -> some IntentResult {
        #if COMMANDV_APP
        await ScreenCaptureSession.shared.requestStopConfirmation()
        #else
        throw CaptureRoutingError()
        #endif
        return .result()
    }
}

@available(iOS 27.0, *)
struct StopScreenCaptureIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End CommandC Screen Capture"
    static var openAppWhenRun = false
    static var supportedModes: IntentModes { .background }
    func perform() async throws -> some IntentResult {
        #if COMMANDV_APP
        await ScreenCaptureSession.shared.confirmStop()
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
        AppShortcut(intent: CaptureScreenFrameIntent(), phrases: ["Take a screenshot with \(.applicationName)"], shortTitle: "Capture Screenshot", systemImageName: "rectangle.dashed")
        AppShortcut(intent: ToggleScreenRecordingIntent(), phrases: ["Record the screen with \(.applicationName)"], shortTitle: "Toggle Screen Recording", systemImageName: "record.circle")
    }
}
#endif
