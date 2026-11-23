import SwiftUI
import WidgetKit
import ActivityKit

@main struct CommandVCaptureWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScreenCaptureAttributes.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(context.state.message).font(.headline)
                    Spacer()
                    Text("\(context.state.count)/10").monospacedDigit().contentTransition(.numericText())
                }
                captureButtons(context.state)
            }.padding().activityBackgroundTint(.black).activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("CommandC").font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.count)/10").font(.caption.monospacedDigit()).lineLimit(1).contentTransition(.numericText())
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.state.recording, let start = context.state.startedAt { Text(start, style: .timer).monospacedDigit() }
                    else {
                        Text(context.state.pending ? "Saving…" : context.state.shotFailed == true ? "Not saved" : "Ready")
                            .font(.caption).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) { captureButtons(context.state) }
            } compactLeading: {
                if context.state.recording { Image(systemName: "record.circle.fill").foregroundStyle(.red) }
                else { Image(systemName: "rectangle.dashed").foregroundStyle(.green) }
            } compactTrailing: {
                if context.state.recording { Text("REC").font(.caption2).lineLimit(1) }
                else { captureFeedback(context.state) }
            } minimal: {
                if context.state.recording { Image(systemName: "record.circle.fill").foregroundStyle(.red) }
                else { captureFeedback(context.state) }
            }
            .widgetURL(URL(string: "imagebridge://screen"))
        }
    }

    private func captureFeedback(_ state: ScreenCaptureAttributes.ContentState) -> some View {
        ZStack {
            Text("\(state.count)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
                .opacity(state.shotFailed == true ? 0 : 1)
            if state.shotFailed == true {
                Image(systemName: "exclamationmark.circle.fill").font(.caption2).foregroundStyle(.orange)
            }
        }
        .frame(width: 20)
        .accessibilityLabel(state.shotFailed == true ? "Not saved" : "Screenshots saved: \(state.count)")
    }
    @ViewBuilder private func captureButtons(_ state: ScreenCaptureAttributes.ContentState) -> some View {
        HStack(spacing: 10) {
            Button(intent: CaptureScreenFrameIntent()) { Label("Capture", systemImage: "rectangle.dashed") }.disabled(state.pending || state.recording || state.count >= 10)
            Button(intent: ToggleScreenRecordingIntent()) { Label(state.recording ? "Stop Recording" : "Record", systemImage: state.recording ? "stop.fill" : "record.circle") }.disabled(state.pending || state.count > 0)
            Link(destination: URL(string: "imagebridge://screen")!) {
                Text("Review").fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(.black)
            if state.confirmingStop == true {
                Button(intent: StopScreenCaptureIntent()) {
                    Image(systemName: "xmark.circle.fill")
                }
                .tint(.red)
                .accessibilityLabel("Confirm End Screen Capture")
            } else {
                Button(intent: RequestStopScreenCaptureIntent()) {
                    Image(systemName: "xmark.circle")
                }
                .tint(Color(white: 0.76))
                .accessibilityLabel("End Screen Capture")
            }
        }.font(.caption).lineLimit(1).minimumScaleFactor(0.85).tint(Color(red: 0.85, green: 0.95, blue: 0.47))
    }
}
