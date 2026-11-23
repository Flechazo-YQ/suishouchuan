import SwiftUI

let cameraAccent = Color(red: 217 / 255, green: 242 / 255, blue: 120 / 255)

struct ScreenLimitBar: View {
    @Binding var limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Screenshot limit").font(.subheadline.weight(.semibold))
                Spacer()
                Text(CaptureBatch.limit(limit).formatted()).monospacedDigit()
            }
            Slider(value: Binding(
                get: { Double(CaptureBatch.limit(limit)) },
                set: { limit = Int($0) }
            ), in: 1...Double(CaptureBatch.maximum), step: 1) {
                Text("Screenshot limit")
            }
            .accessibilityIdentifier("screenLimitSlider")
            .accessibilityValue(Text(CaptureBatch.limit(limit).formatted()))
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

struct BurstLimitDial: View {
    @Binding var limit: Int
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var dragStart: Int?
    @State private var collapse: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            if expanded {
                dial
                    .frame(maxWidth: 320).frame(height: 98)
                    .contentShape(Rectangle()).gesture(drag)
                    .accessibilityHidden(true)
            }
            Button {
                collapse?.cancel()
                setExpanded(!expanded)
            } label: {
                Text("\(count)/\(CaptureBatch.limit(limit))")
                    .font(.footnote.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 13).padding(.vertical, 6)
                    .background(Color.black.opacity(0.75), in: Capsule())
                    .frame(minWidth: 60, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundColor(cameraAccent)
            .simultaneousGesture(drag)
            .accessibilityLabel("Burst limit")
            .accessibilityIdentifier("burstLimitDial")
            .accessibilityValue(Text("\(count)/\(CaptureBatch.limit(limit))"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: limit = CaptureBatch.limit(limit + 1)
                case .decrement: limit = CaptureBatch.limit(limit - 1)
                @unknown default: break
                }
            }
        }
        .onDisappear { collapse?.cancel() }
    }

    private var dial: some View {
        Canvas { context, size in
            let value = CaptureBatch.limit(limit)
            let radius = Double(size.width) * 0.53
            let center = CGPoint(x: Double(size.width) / 2, y: radius + 4)
            let circle = CGRect(x: Double(center.x) - radius, y: 4, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: circle), with: .color(.black.opacity(0.77)))
            for offset in -16...16 where (1...CaptureBatch.maximum).contains(value + offset) {
                let angle = Double(offset) * 0.053
                let marked = (value + offset).isMultiple(of: 5) || offset == 0
                func point(_ length: Double) -> CGPoint {
                    CGPoint(x: Double(center.x) + sin(angle) * length, y: Double(center.y) - cos(angle) * length)
                }
                let tick = Path { path in
                    path.move(to: point(radius - 5))
                    path.addLine(to: point(radius - (marked ? 18 : 11)))
                }
                let color: Color = offset == 0 ? cameraAccent : .white.opacity(marked ? 0.8 : 0.35)
                context.stroke(tick, with: .color(color), lineWidth: offset == 0 ? 2 : 1)
                if marked {
                    context.draw(Text((value + offset).formatted()).font(.caption2.monospacedDigit()).foregroundColor(color),
                                 at: point(radius - 29))
                }
            }
        }
        .clipped()
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 7).onChanged { value in
            if dragStart == nil {
                collapse?.cancel()
                dragStart = CaptureBatch.limit(limit)
                setExpanded(true)
            }
            if let dragStart {
                limit = CaptureBatch.limit(dragStart - Int((value.translation.width / 6).rounded()))
            }
        }.onEnded { _ in
            dragStart = nil
            collapse = Task {
                do { try await Task.sleep(nanoseconds: 1_300_000_000) } catch { return }
                setExpanded(false)
            }
        }
    }

    private func setExpanded(_ value: Bool) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { expanded = value }
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
