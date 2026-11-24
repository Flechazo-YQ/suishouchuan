#if canImport(CommandV)
import ActivityKit
import XCTest
@testable import CommandV

final class ScreenCaptureLiveActivityTests: XCTestCase {
    @MainActor func testEverySavedScreenshotCollectsBeforeIncreasingTheCount() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Screen capture requires iOS 27") }
        XCTAssertNotNil(Bundle.main.url(forResource: "ScreenCaptureSaved", withExtension: "caf"))
        let liveActivity = ScreenCaptureLiveActivity()
        func state(_ count: Int) -> ScreenCaptureAttributes.ContentState {
            .init(count: count, recording: false, pending: false, message: "Capture active")
        }
        let existingIds = Set(Activity<ScreenCaptureAttributes>.activities.map(\.id))
        try liveActivity.start(state(0))
        defer { liveActivity.dismissCurrent() }
        let activity = try XCTUnwrap(Activity<ScreenCaptureAttributes>.activities.first { !existingIds.contains($0.id) })
        let delivered = expectation(description: "Three receipt and count updates")
        let recorder = Task { @MainActor in
            var recorded: [String] = []
            for await update in activity.contentUpdates where update.state.count > 0 {
                let kind = update.state.collectingShot == true ? "paper" : "count"
                recorded.append("\(kind):\(update.state.displayedCount)")
                if recorded.count == 6 { delivered.fulfill(); break }
            }
            return recorded
        }
        await Task.yield()

        for count in 1...3 {
            await liveActivity.acknowledgeShot(showResult: true) { state(count) }
            try await Task.sleep(for: .milliseconds(600))
        }

        await fulfillment(of: [delivered], timeout: 5)
        recorder.cancel()
        let recorded = await recorder.value
        XCTAssertEqual(recorded, ["paper:0", "count:1", "paper:1", "count:2", "paper:2", "count:3"])
    }
}
#endif
