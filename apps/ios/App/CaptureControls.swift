import SwiftUI

let cameraAccent = Color(red: 217 / 255, green: 242 / 255, blue: 120 / 255)

struct BatchLimitControl: View {
    @Binding var limit: Int
    let count: Int
    @State private var choosing = false

    private let ticks = [1, 5, 10, 20, 50, CaptureBatch.maximum]

    var body: some View {
        Button {
            choosing = true
        } label: {
            Label("\(count)/\(CaptureBatch.limit(limit))", systemImage: "slider.horizontal.3")
                .font(.footnote.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 12).frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Batch limit")
        .accessibilityValue(Text("\(count)/\(CaptureBatch.limit(limit))"))
        .sheet(isPresented: $choosing) {
            NavigationView {
                VStack(spacing: 12) {
                    Text(CaptureBatch.limit(limit).formatted())
                        .font(.system(size: 44, weight: .semibold, design: .monospaced))
                        .foregroundStyle(cameraAccent)
                        .accessibilityHidden(true)
                    Slider(value: sliderPosition, in: 0...Double(ticks.count - 1)) {
                        Text("Batch limit")
                    }.accessibilityValue(Text(CaptureBatch.limit(limit).formatted()))
                    HStack(spacing: 0) {
                        ForEach(ticks, id: \.self) { tick in
                            Button {
                                limit = tick
                            } label: {
                                Text(tick.formatted()).font(.caption.monospacedDigit())
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    Text("Up to 100 MB per batch.").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(24).navigationTitle("Batch limit").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { choosing = false } }
            }.navigationViewStyle(.stack).preferredColorScheme(.dark).tint(cameraAccent)
        }
    }

    private var sliderPosition: Binding<Double> {
        Binding {
            let value = CaptureBatch.limit(limit)
            guard let end = ticks.firstIndex(where: { $0 > value }) else { return Double(ticks.count - 1) }
            return Double(end - 1) + Double(value - ticks[end - 1]) / Double(ticks[end] - ticks[end - 1])
        } set: { position in
            let start = min(Int(position), ticks.count - 2)
            let value = Double(ticks[start]) + (position - Double(start)) * Double(ticks[start + 1] - ticks[start])
            limit = CaptureBatch.limit(Int(value.rounded()))
        }
    }
}

struct CameraGrid: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                for fraction in [1.0 / 3, 2.0 / 3] {
                    let x = geometry.size.width * fraction, y = geometry.size.height * fraction
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }.stroke(Color.white.opacity(0.25), lineWidth: 0.5)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct CaptureModeTabs: View {
    @Binding var burst: Bool
    let locked: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    var body: some View {
        HStack(spacing: 0) {
            mode("Camera", selected: !burst, value: false)
            mode("Burst", selected: burst, value: true)
        }
            .padding(3).background(Color.white.opacity(0.06)).clipShape(Capsule())
            .disabled(locked)
    }
    private func mode(_ title: LocalizedStringKey, selected: Bool, value: Bool) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { burst = value }
        } label: {
            Text(title).font(.subheadline.weight(.semibold)).foregroundColor(selected ? cameraAccent : .gray)
                .padding(.horizontal, 16).frame(minWidth: 82, minHeight: 44)
                .background(Group { if selected { Capsule().fill(cameraAccent.opacity(0.12)).matchedGeometryEffect(id: "mode", in: selection) } })
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ShutterButton: View {
    let burst: Bool
    let recording: Bool
    let enabled: Bool
    let photo: () -> Void
    let beginVideo: () -> Void
    let endVideo: () -> Void
    var body: some View {
        ZStack {
            Circle().stroke(recording ? Color.red : .white, lineWidth: 2).frame(width: 82, height: 82)
            RoundedRectangle(cornerRadius: recording ? 9 : 33)
                .fill(recording ? Color.red : .white).frame(width: recording ? 34 : 66, height: recording ? 34 : 66)
            TouchSurface(burst: burst, recording: recording, enabled: enabled, photo: photo, beginVideo: beginVideo, endVideo: endVideo)
                .frame(width: 88, height: 88)
        }.opacity(enabled ? 1 : 0.35)
    }
}

private struct TouchSurface: UIViewRepresentable {
    let burst: Bool
    let recording: Bool
    let enabled: Bool
    let photo: () -> Void
    let beginVideo: () -> Void
    let endVideo: () -> Void
    func makeUIView(context: Context) -> ShutterTouch { let view = ShutterTouch(); updateUIView(view, context: context); return view }
    func updateUIView(_ view: ShutterTouch, context: Context) {
        view.burst = burst; view.recording = recording
        view.photo = photo; view.beginVideo = beginVideo; view.endVideo = endVideo
        view.isUserInteractionEnabled = enabled
        view.accessibilityLabel = burst ? String(localized: "Burst shutter") : String(localized: "Camera shutter. Tap for a photo or hold for video.")
        view.accessibilityTraits = enabled ? .button : [.button, .notEnabled]
    }
}

private final class ShutterTouch: UIView {
    var burst = false
    var recording = false
    var photo: (() -> Void)?
    var beginVideo: (() -> Void)?
    var endVideo: (() -> Void)?
    private var timer: Timer?
    private var longPress = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: String(localized: "Start or Stop Camera Recording"), target: self, selector: #selector(accessibleVideo))]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        timer?.invalidate(); longPress = false
        if recording { longPress = true; endVideo?(); return }
        guard !burst else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.longPress = true; self?.beginVideo?()
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        timer?.invalidate(); timer = nil
        if longPress { endVideo?() } else { photo?() }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        timer?.invalidate(); timer = nil
        if longPress { endVideo?() }
    }
    override func accessibilityActivate() -> Bool { if isUserInteractionEnabled { photo?(); return true }; return false }
    @objc private func accessibleVideo() -> Bool {
        guard isUserInteractionEnabled, !burst else { return false }
        if recording { endVideo?() } else { beginVideo?() }
        return true
    }
    deinit { timer?.invalidate() }
}
