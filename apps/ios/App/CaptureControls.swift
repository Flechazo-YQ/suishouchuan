import SwiftUI

let cameraAccent = Color(red: 217 / 255, green: 242 / 255, blue: 120 / 255)

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
        HStack(spacing: 0) { mode("拍摄", selected: !burst, value: false); mode("连拍", selected: burst, value: true) }
            .padding(3).background(Color.white.opacity(0.06)).clipShape(Capsule())
            .disabled(locked)
    }
    private func mode(_ title: String, selected: Bool, value: Bool) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { burst = value }
        } label: {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(selected ? cameraAccent : .gray)
                .frame(width: 76, height: 42)
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
        view.accessibilityLabel = burst ? "连拍：拍摄一张并继续取景" : "拍摄：轻触拍照，长按录像"
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
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: "开始或停止录像", target: self, selector: #selector(accessibleVideo))]
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
