import SwiftUI
import AVKit

@available(iOS 27.0, *)
struct NativeScreenTools: View {
    @ObservedObject private var capture = ScreenCaptureSession.shared
    @AppStorage("captureBatchLimit") private var captureBatchLimit = CaptureBatch.defaultLimit
    @State private var preparation: Task<Void, Never>?
    @State private var discard = false
    @State private var selected: URL?
    let review: ([URL]) async throws -> Void
    private var importing: Bool { preparation != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Capture Across Apps", systemImage: "rectangle.dashed.badge.record")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if capture.starting {
                ProgressView("Waiting for screen access…")
                Button("Cancel", role: .cancel) { Task { await capture.stop() } }
            }
            else if capture.active {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { activeStatus; Spacer(minLength: 0); stopButton }
                    VStack(alignment: .leading, spacing: 4) { activeStatus; stopButton }
                }
            } else {
                Button { capture.presentPicker(limit: captureBatchLimit) } label: {
                    Text("Start Screen Capture")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).disabled(capture.finishing)
                BatchLimitControl(limit: $captureBatchLimit, count: capture.files.count)
                    .disabled(capture.finishing || capture.isVideo)
            }
            if !capture.message.isEmpty { Text(capture.message).font(.footnote).foregroundColor(.secondary).accessibilityIdentifier("screenCaptureStatus") }
            if capture.pendingShot || capture.finishing { ProgressView(capture.pendingShot ? "Swipe up on the Dynamic Island to collapse it…" : "Saving recording…") }
            if capture.finishing {
                Button("Cancel Saving", role: .destructive) { Task { await capture.stop() } }
                    .frame(minHeight: 44)
            }
            if !capture.files.isEmpty {
                Divider()
                Text(capture.isVideo ? "Recording Ready" : "Screenshots (\(capture.files.count))").font(.headline)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(capture.files, id: \.self) { file in
                            VStack(spacing: 4) {
                                Button { selected = file } label: {
                                    MediaThumbnail(item: MediaItem(url: file, mime: capture.isVideo ? "video/mp4" : "image/jpeg"), maxPixelSize: 240).scaledToFit().frame(width: 85, height: 110)
                                }.accessibilityLabel("Preview Capture")
                                Button("Remove") { do { try capture.remove(file); if selected == file { selected = nil } } catch { capture.message = error.localizedDescription } }
                                    .disabled(importing)
                            }
                        }
                    }
                }
                if let selected, capture.files.contains(selected) {
                    if capture.isVideo { ScreenVideoPreview(url: selected).frame(height: 240) }
                    else { MediaThumbnail(item: MediaItem(url: selected, mime: "image/jpeg")).scaledToFit().frame(maxHeight: 320) }
                }
                HStack {
                    Button(importing ? "Preparing…" : "Review and Send") {
                        let files = capture.files
                        let keepOriginal = capture.isVideo
                        preparation = Task {
                            defer { preparation = nil }
                            await capture.stop()
                            do {
                                try Task.checkCancellation()
                                try await review(files)
                                if !keepOriginal { try capture.clearImported() }
                            } catch is CancellationError {
                                capture.message = String(localized: "Preparation canceled. Your captures are ready to retry.")
                            } catch {
                                capture.message = error.localizedDescription
                            }
                        }
                    }.buttonStyle(.borderedProminent).disabled(importing || capture.pendingShot || capture.recording || capture.finishing)
                    Button("Clear", role: .destructive) { discard = true }.disabled(importing || capture.pendingShot || capture.recording || capture.finishing)
                }
                if let preparation { Button("Cancel Preparing", role: .cancel) { preparation.cancel() } }
                Text("Tap Send in the preview to transfer your captures. Your camera batch stays in CommandC.").font(.footnote).foregroundColor(.secondary)
            }
            captureGuide
        }
        .onDisappear { preparation?.cancel() }
        .alert("Clear these captures?", isPresented: $discard) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { do { try capture.clearImported(); selected = nil } catch { capture.message = error.localizedDescription } }
        } message: { Text("This removes the draft copies in CommandC.") }
    }

    private var activeStatus: some View {
        Label(capture.recording ? "Recording · \(capture.seconds) s" : "Capturing · \(capture.files.count)/\(capture.batchLimit)", systemImage: "circle.fill")
            .foregroundColor(capture.recording ? .red : .green)
    }

    private var stopButton: some View {
        Button("End Capture") { Task { await capture.stop() } }
            .frame(minHeight: 44).disabled(capture.finishing)
    }

    private var captureGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Take screenshots with the Dynamic Island").font(.headline)
                .accessibilityAddTraits(.isHeader)
            guideStep(1, "Share your entire screen", "Tap Start Screen Capture. In the system prompt, choose to share your entire screen and confirm.")
            guideStep(2, "Press and hold the Dynamic Island", "Open the app you want to capture. Press and hold the CommandC activity at the top of the screen until the controls expand.")
            guideStep(3, "Tap Capture, then swipe up to collapse", "Close the controls within three seconds. When the count increases, the screenshot is ready. Press and hold the Dynamic Island again for the next shot.")
            guideStep(4, "Review and send the batch", "Press and hold the Dynamic Island and tap Review, or reopen Screen Capture in CommandC. Tap Review and Send, then tap Send at the top right.")

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text("On an iPhone with an Action button, go to Settings → Action Button → Shortcut. Tap Choose a Shortcut and select Capture Screenshot under CommandC.")
                    Text("Start screen capture in CommandC and switch to the app you want to capture. Press and hold the Action button, then wait about 1.5 seconds for one screenshot.")
                }.font(.subheadline).foregroundStyle(.secondary).padding(.top, 6)
            } label: {
                Text("Use the Action Button").multilineTextAlignment(.leading)
            }
            DisclosureGroup("Record with the Dynamic Island") {
                Text("Start screen capture and switch to the app you want to record. Press and hold the Dynamic Island, tap Record, then collapse the controls. To finish, press and hold again and tap Stop Recording. Recordings stop after 30 seconds. Tap Review to return to CommandC.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.top, 6)
            }
        }.padding(16).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }

    private func guideStep(_ number: Int, _ title: LocalizedStringKey, _ instruction: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number.formatted()).monospacedDigit().fontWeight(.semibold).foregroundStyle(cameraAccent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(instruction).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("screenCaptureGuideStep\(number)")
    }

}

private struct ScreenVideoPreview: View {
    @State private var player: AVPlayer
    init(url: URL) { _player = State(initialValue: AVPlayer(url: url)) }
    var body: some View { VideoPlayer(player: player).onDisappear { player.pause() } }
}
