import SwiftUI
import WidgetKit
import ActivityKit

@main struct CommandVCaptureWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScreenCaptureAttributes.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("CommandV · \(context.state.message)").font(.headline); Spacer(); Text("\(context.state.count)/10") }
                captureButtons(context.state)
            }.padding().activityBackgroundTint(.black).activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("CommandV").font(.headline) }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.count)/10").monospacedDigit() }
                DynamicIslandExpandedRegion(.center) {
                    if context.state.recording, let start = context.state.startedAt { Text(start, style: .timer).monospacedDigit() }
                    else { Text(context.state.pending ? "1.5 秒后截取 · 请收起面板" : "点一次，截取一张").font(.caption) }
                }
                DynamicIslandExpandedRegion(.bottom) { captureButtons(context.state) }
            } compactLeading: { Image(systemName: context.state.recording ? "record.circle.fill" : "rectangle.dashed").foregroundColor(context.state.recording ? .red : .green) }
              compactTrailing: { Text(context.state.recording ? "录屏" : "\(context.state.count)/10").monospacedDigit() }
              minimal: { Image(systemName: context.state.recording ? "record.circle.fill" : "rectangle.dashed") }
              .widgetURL(URL(string: "imagebridge://screen"))
        }
    }
    @ViewBuilder private func captureButtons(_ state: ScreenCaptureAttributes.ContentState) -> some View {
        HStack(spacing: 14) {
            Button(intent: CaptureScreenFrameIntent()) { Label("截取", systemImage: "rectangle.dashed") }.disabled(state.pending || state.recording || state.count >= 10)
            Button(intent: ToggleScreenRecordingIntent()) { Label(state.recording ? "停止录屏" : "录屏", systemImage: state.recording ? "stop.fill" : "record.circle") }.disabled(state.pending || state.count > 0)
            Link("查看", destination: URL(string: "imagebridge://screen")!)
            Button(intent: StopScreenCaptureIntent()) { Image(systemName: "xmark.circle") }.accessibilityLabel("停止屏幕采集")
        }.font(.caption).tint(Color(red: 0.85, green: 0.95, blue: 0.47))
    }
}
