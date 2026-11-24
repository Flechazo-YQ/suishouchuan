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
                    captureCounter(context.state, font: .body)
                }
                captureButtons(context.state)
            }.padding().activityBackgroundTint(.black).activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("CommandC").font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        CaptureReceipt(collecting: context.state.collectingShot == true)
                        captureCounter(context.state, font: .caption)
                    }
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
                if context.state.recording, let start = context.state.startedAt {
                    Text(start, style: .timer).font(.caption2.monospacedDigit()).lineLimit(1)
                } else {
                    captureFeedback(context.state)
                }
            } compactTrailing: {
                if context.state.recording {
                    Text("REC").font(.caption2).lineLimit(1).foregroundStyle(.red)
                } else {
                    ZStack {
                        Image(systemName: "record.circle").foregroundStyle(.secondary)
                            .opacity(context.state.collectingShot == true ? 0 : 1)
                            .accessibilityLabel("Record")
                        CaptureReceipt(collecting: context.state.collectingShot == true)
                    }
                }
            } minimal: {
                if context.state.recording { Image(systemName: "record.circle.fill").foregroundStyle(.red) }
                else {
                    ZStack {
                        captureFeedback(context.state, hidden: context.state.collectingShot == true)
                        CaptureReceipt(collecting: context.state.collectingShot == true)
                    }
                }
            }
            .widgetURL(URL(string: "imagebridge://screen"))
        }
    }

    private func captureCounter(_ state: ScreenCaptureAttributes.ContentState, font: Font) -> some View {
        HStack(spacing: 0) {
            CaptureRollingCount(count: state.displayedCount, font: font)
            Text("/\(state.batchLimit ?? 10)").font(font.monospacedDigit())
        }.lineLimit(1)
    }

    private func captureFeedback(_ state: ScreenCaptureAttributes.ContentState, hidden: Bool = false) -> some View {
        ZStack {
            CaptureRollingCount(count: state.displayedCount, font: .caption2.weight(.semibold))
                .opacity(state.shotFailed == true || hidden ? 0 : 1)
            if state.shotFailed == true {
                Image(systemName: "exclamationmark.circle.fill").font(.caption2).foregroundStyle(.orange)
            }
        }
        .frame(width: 20)
        .accessibilityLabel(state.shotFailed == true ? "Not saved" : "Screenshots saved: \(state.displayedCount)")
    }
    @ViewBuilder private func captureButtons(_ state: ScreenCaptureAttributes.ContentState) -> some View {
        HStack(spacing: 10) {
            if state.pending {
                Text("Saving…").foregroundStyle(.secondary)
            } else if state.readyToReview != true {
                Button(intent: CaptureIslandFrameIntent()) { Label("Capture", systemImage: "rectangle.dashed") }
                    .disabled(state.recording || state.collectingShot == true || state.count >= (state.batchLimit ?? 10))
                Button(intent: ToggleScreenRecordingIntent()) { Label(state.recording ? "Stop Recording" : "Record", systemImage: state.recording ? "stop.fill" : "record.circle") }.disabled(state.count > 0)
            }
            Link(destination: URL(string: "imagebridge://screen/review")!) {
                Text("Review").fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(.black)
            if state.confirmingStop == true {
                Button(intent: StopScreenCaptureIntent()) {
                    Image(systemName: "xmark.circle.fill")
                }
                .tint(.red)
                .accessibilityLabel(state.pending ? "Confirm Cancel Saving" : "Confirm End Screen Capture")
            } else if state.pending {
                Button(intent: RequestStopScreenCaptureIntent()) { Text("Cancel Saving") }.tint(.orange)
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

private struct CaptureRollingCount: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let count: Int
    let font: Font

    var body: some View {
        Text(count.formatted())
            .font(font.monospacedDigit())
            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: false))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25).delay(0.30), value: count)
    }
}

private struct CaptureReceipt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let collecting: Bool

    var body: some View {
        ZStack {
            if collecting {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white)
                    .frame(width: 13, height: 16)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color(red: 0.65, green: 0.79, blue: 0.50))
                            .frame(width: 9, height: 9)
                            .padding(.top, 2)
                    }
                    .transition(paperMotion)
            }
        }
        .frame(width: 20, height: 18)
        .clipped()
        .accessibilityHidden(true)
    }

    private var paperMotion: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity).animation(.easeOut(duration: 0.16)),
            removal: .move(edge: .top).combined(with: .scale(scale: 0.35, anchor: .top))
                .combined(with: .opacity).animation(.easeIn(duration: 0.29))
        )
    }
}
