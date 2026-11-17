import SwiftUI
import AVKit
import ImageIO

struct ContentView: View {
    @StateObject private var model = TransferModel()
    @StateObject private var camera = CameraCapture()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false
    @State private var reviewing = false
    @State private var reviewIndex = 0
    @State private var showDevices = false
    @State private var showLibrary = false
    @State private var showScreenTools = false
    @State private var showScanner = false
    @State private var scannerPending = false
    @State private var libraryPending = false
    @State private var libraryKind: LibraryPicker.Kind = .all
    @State private var pairingText = ""
    @State private var pendingPairingText: String?
    @State private var invitation: Invitation?
    @State private var confirmPair = false
    @State private var confirmUpload = false
    @State private var confirmDiscard = false
    @State private var captureFlash = false
    private var locked: Bool { model.busy || camera.capturing || camera.recording || camera.finishing }
    private var group: Bool { model.source == .burst || model.source == .library }
    private var cameraVisible: Bool { scenePhase == .active && !reviewing && !showDevices && !showScanner && !scannerPending && !showLibrary && !showScreenTools && !testCamera }
    private var testCamera: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--ui-camera")
        #else
        return false
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            viewfinder
            if !model.savedDrafts.isEmpty { savedShelf }
            if !model.items.isEmpty && (group || burst) { thumbnailStrip }
            if reviewing { reviewFooter } else { captureFooter }
        }
        .background(Color(red: 0.02, green: 0.02, blue: 0.02).ignoresSafeArea())
        .foregroundColor(.white).preferredColorScheme(.dark).tint(cameraAccent)
        .sheet(isPresented: $showDevices, onDismiss: afterDevices) { deviceSheet }
        .sheet(isPresented: $showScanner, onDismiss: completePairingPresentation) {
            NavigationView { QRScanner { queuePairing($0) }.navigationTitle("扫描电脑配对二维码").toolbar { Button("取消") { showScanner = false } } }
        }
        .sheet(isPresented: $showLibrary) {
            LibraryPicker(limit: 10, kind: libraryKind) { providers in
                showLibrary = false
                guard !providers.isEmpty else { return }
                Task {
                    await model.importProviders(providers, separately: true, autoSend: true)
                    syncDraftPresentation()
                }
            }
        }
        .sheet(isPresented: $showScreenTools, onDismiss: {
            if libraryPending { libraryPending = false; showLibrary = true }
        }) { screenTools }
        .alert("配对电脑", isPresented: $confirmPair) {
            Button("取消", role: .cancel) {}
            Button("确认配对") { if let invitation { Task { await model.pair(invitation) } } }
        } message: { Text("允许向「\(invitation?.name ?? "")」发送素材？") }
        .alert("发送到电脑", isPresented: $confirmUpload) {
            Button("取消", role: .cancel) {}
            Button("确认上传") { sendCurrent() }
        } message: { Text("将这\(model.items.first?.mime == "video/mp4" ? "段视频" : "张照片")发送到「\(model.target?.name ?? "未配置电脑")」？") }
        .alert("放弃这组素材？", isPresented: $confirmDiscard) {
            Button("继续查看", role: .cancel) {}
            Button("放弃", role: .destructive) { model.clear(); model.restoreLastDraft(); syncDraftPresentation() }
        } message: { Text("只清理待发副本，相册原件保留。") }
        .onOpenURL { url in
            if url.scheme == "imagebridge", url.host == "screen" { showScreenTools = true }
            else { queuePairing(url.absoluteString) }
        }
        .onAppear {
            model.switchCapture(burst: false)
            camera.captured = { file, video in importCapture(file, video: video) }
            model.startDiscovery()
            if !testCamera { camera.start() }
        }
        .onDisappear { camera.stop(); camera.captured = nil; model.stopDiscovery() }
        .onChange(of: burst) { value in model.switchCapture(burst: value) }
        .onChange(of: cameraVisible) { value in
            if value { camera.start() } else { camera.stop() }
        }
        .onChange(of: camera.error) { value in if !value.isEmpty { model.report(BridgeError.message(value)) } }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                do { try model.reload(); model.startDiscovery() } catch { model.report(error) }
                if cameraVisible { camera.start() }
            } else { camera.stop(); model.stopDiscovery() }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            if reviewing {
                Button(action: leaveReview) { Image(systemName: "xmark").font(.system(size: 24, weight: .light)).frame(width: 48, height: 48) }
                    .accessibilityLabel(group ? "返回取景" : "重新拍摄").disabled(locked)
                Spacer()
                Button {
                    if model.target == nil { showDevices = true }
                    else if group { sendCurrent() } else { confirmUpload = true }
                } label: {
                    if group { Text("确认并发送").font(.system(size: 14, weight: .semibold)).padding(.horizontal, 16).frame(height: 44).background(cameraAccent.opacity(0.13)).clipShape(Capsule()) }
                    else { Image(systemName: "checkmark").font(.system(size: 29, weight: .semibold)).frame(width: 48, height: 48) }
                }.foregroundColor(cameraAccent).accessibilityLabel(group ? "确认并发送" : "确认上传").disabled(locked || model.items.isEmpty)
            } else {
                Button { showDevices = true } label: {
                    HStack(spacing: 10) {
                        Circle().fill(model.target == nil ? Color.gray : cameraAccent).frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.target?.name ?? "未配置电脑").font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(model.target?.addresses.first ?? "扫码连接 Windows CtrlV").font(.system(size: 10)).foregroundColor(.gray).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }.frame(minHeight: 48)
                }.buttonStyle(.plain).accessibilityLabel("连接电脑").disabled(locked)
                if !model.items.isEmpty {
                    Button("查看 \(model.items.count) 张") { reviewIndex = 0; reviewing = true }
                        .font(.system(size: 13, weight: .medium)).foregroundColor(cameraAccent).frame(minHeight: 44).disabled(locked)
                }
                Button { showDevices = true } label: { Image(systemName: "qrcode.viewfinder").font(.system(size: 23)).frame(width: 44, height: 48) }
                    .accessibilityLabel("配对电脑").disabled(locked)
            }
        }.padding(.horizontal, 18).frame(height: 60)
    }

    private var viewfinder: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.03, green: 0.03, blue: 0.03)
                if reviewing && !model.items.isEmpty {
                    TabView(selection: $reviewIndex) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                            Group {
                                if item.mime == "video/mp4" { VideoReview(url: item.url) }
                                else { MediaThumbnail(item: item).scaledToFit() }
                            }.tag(index).accessibilityLabel("预览第 \(index + 1) 张")
                        }
                    }.tabViewStyle(.page(indexDisplayMode: .never))
                } else {
                    if camera.authorized && !testCamera { CameraPreview(session: camera.session) }
                    if camera.authorized || testCamera { CameraGrid() }
                    else { permissionView }
                    Color.white.opacity(captureFlash ? 0.55 : 0).allowsHitTesting(false)
                }
                if camera.recording {
                    VStack {
                        HStack(spacing: 8) { Circle().fill(Color.red).frame(width: 7, height: 7); Text(String(format: "00:%02d", camera.seconds)).monospacedDigit(); Button("停止") { camera.stopRecording() }.foregroundColor(.white) }
                            .font(.system(size: 13)).padding(.horizontal, 14).frame(height: 44).background(Color.black.opacity(0.65)).clipShape(Capsule())
                        Spacer()
                    }.padding(.top, 14)
                }
                if model.busy || camera.finishing {
                    VStack(spacing: 12) { ProgressView().tint(.white); Text("正在处理…").font(.footnote) }
                        .padding(22).background(Color.black.opacity(0.75)).cornerRadius(16)
                }
                if !model.message.isEmpty && !model.busy {
                    VStack { Spacer(); Button { model.message = ""; camera.error = "" } label: {
                        Text(model.message).font(.system(size: 13)).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(14)
                            .background(model.failure ? Color(red: 0.32, green: 0.17, blue: 0.14) : Color(red: 0.14, green: 0.19, blue: 0.15)).cornerRadius(14)
                    }.buttonStyle(.plain).accessibilityIdentifier("transferStatus") }.padding(16)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                .contentShape(Rectangle()).accessibilityIdentifier("viewfinder")
                .gesture(DragGesture(minimumDistance: 35).onEnded { value in
                    guard !reviewing, !locked, abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { burst = value.translation.width < 0 }
                }, including: reviewing ? .subviews : .all)
        }
    }
    private var permissionView: some View {
        VStack(spacing: 18) {
            Text("让眼前，即刻到电脑").font(.system(size: 20, weight: .medium))
            Text("允许使用相机后即可拍摄").font(.system(size: 13)).foregroundColor(.gray)
            Button("开启相机") { Task { await camera.authorize() } }
                .font(.system(size: 14)).padding(.horizontal, 28).frame(height: 48).overlay(Capsule().stroke(Color.gray.opacity(0.6)))
            Button("系统权限设置", action: openSettings).font(.system(size: 12)).foregroundColor(.gray).frame(minHeight: 44)
        }.padding(24)
    }
    private var captureFooter: some View {
        VStack(spacing: 9) {
            CaptureModeTabs(burst: $burst, locked: locked)
            Text(camera.recording ? "松手完成 · 最长 30 秒" : burst ? "连续点按拍照 · 最多 10 张" : "轻触拍照，按住录像").font(.system(size: 12)).foregroundColor(.gray)
            HStack {
                Button { libraryKind = .all; showLibrary = true } label: { Image(systemName: "photo.on.rectangle.angled").font(.system(size: 27)).frame(width: 64, height: 64) }
                    .accessibilityLabel("相册").disabled(locked)
                Spacer()
                ShutterButton(burst: burst, recording: camera.recording, enabled: (camera.ready || testCamera) && !model.busy && !camera.capturing && !camera.finishing && (!burst || model.items.count < 10), photo: takePhoto, beginVideo: camera.startRecording, endVideo: camera.stopRecording)
                Spacer()
                Button { showScreenTools = true } label: {
                    VStack(spacing: 5) { Image(systemName: "rectangle.dashed.badge.record").font(.system(size: 25)); Text("截屏 / 录屏").font(.system(size: 10)) }.frame(width: 72, height: 64)
                }.accessibilityLabel("截屏 / 录屏").disabled(locked)
            }.padding(.horizontal, 34)
            Text(model.items.isEmpty ? "左滑连拍 · 右滑拍摄" : "可切换相册或截屏 · 这组照片会保留").font(.system(size: 10)).foregroundColor(.gray)
        }.padding(.top, 14).padding(.bottom, 10)
    }
    private var reviewFooter: some View {
        VStack(spacing: 12) {
            Text(group ? "点缩略图查看 · 右上角确认并发送" : "右上角确认上传 · 左上角重新拍摄").font(.system(size: 12)).foregroundColor(.gray)
            Text(group ? "预览 \(min(reviewIndex + 1, model.items.count)) / \(model.items.count)" : model.items.first?.mime == "video/mp4" ? "视频" : "照片").font(.system(size: 18))
            Text("发送到：\(model.target?.name ?? "未配置电脑")").font(.system(size: 12)).foregroundColor(.gray)
            Text("CommandV · 仅局域网传输").font(.system(size: 10)).foregroundColor(.gray)
        }.padding(.vertical, 20).frame(maxWidth: .infinity)
    }
    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    ZStack(alignment: .topTrailing) {
                        Button { reviewIndex = index; reviewing = true } label: {
                            MediaThumbnail(item: item, maxPixelSize: 200).scaledToFill().frame(width: 62, height: 62).clipped().cornerRadius(8)
                                .overlay(alignment: .bottomLeading) { Text("\(index + 1)").font(.system(size: 10)).padding(4).background(Color.black.opacity(0.7)).cornerRadius(4) }
                        }.accessibilityLabel("查看第 \(index + 1) 张")
                        Button {
                            model.removeItem(item.id); reviewIndex = max(0, min(reviewIndex, model.items.count - 1))
                            if model.items.isEmpty { reviewing = false; model.restoreLastDraft(); syncDraftPresentation() }
                        } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 21)).symbolRenderingMode(.palette).foregroundStyle(.white, .black).frame(width: 44, height: 44) }
                            .accessibilityLabel("移除第 \(index + 1) 张").offset(x: 8, y: -8)
                    }
                }
            }.padding(.horizontal, 12).padding(.vertical, 10)
        }.frame(height: 82).background(Color.white.opacity(0.04)).disabled(locked)
    }
    private var savedShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.savedDrafts) { draft in
                    Button("\(draft.title) · 查看") { model.selectDraft(draft.id); syncDraftPresentation(review: true) }
                        .font(.system(size: 12)).padding(.horizontal, 14).frame(height: 40).background(cameraAccent.opacity(0.12)).clipShape(Capsule()).foregroundColor(cameraAccent)
                }
            }.padding(.horizontal, 12)
        }.frame(height: 48).disabled(locked)
    }

    private var deviceSheet: some View {
        NavigationView {
            List {
                Section("已配对电脑") {
                    ForEach(model.devices) { device in Button { model.select(device.id); showDevices = false } label: { HStack { Text(device.name); Spacer(); if device.id == model.selectedId { Image(systemName: "checkmark") } } } }
                        .onDelete { offsets in
                            let ids = offsets.map { model.devices[$0].id }
                            ids.forEach(model.removeDevice)
                        }
                    if model.devices.isEmpty { Text("两端连接同一 Wi-Fi 后，扫描电脑上的二维码。").foregroundColor(.secondary) }
                }
                Section {
                    Button("扫描配对二维码") {
                        Task { do { try await requestCamera(video: false); scannerPending = true; showDevices = false } catch { model.report(error); showDevices = false } }
                    }
                    TextField("或粘贴电脑端配对链接", text: $pairingText).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("使用配对链接") { queuePairing(pairingText) }.disabled(pairingText.isEmpty)
                }
                Section { Button("打开系统权限设置", action: openSettings) }
            }.navigationTitle("连接电脑").toolbar { Button("完成") { showDevices = false } }.disabled(model.busy)
        }.preferredColorScheme(.dark)
    }
    private var screenTools: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if #available(iOS 27.0, *) {
                        NativeScreenTools { files in
                            try await model.importScreenFiles(files)
                            showScreenTools = false
                            syncDraftPresentation(review: true)
                        }
                    } else {
                        Label("系统截图", systemImage: "rectangle.dashed").font(.title3.weight(.semibold))
                        Text("用 iPhone 系统截屏后，点分享 → CommandV → 确认发送。连续截好几张，也可以在下方选取后一起发送。").foregroundColor(.secondary)
                        Button("选择截图") { openScreenLibrary(.images) }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                        Divider()
                        Label("系统录屏", systemImage: "record.circle").font(.title3.weight(.semibold))
                        Text("在控制中心开始屏幕录制，结束后在「照片」中分享给 CommandV，或在下方选取。每段最多 30 秒。").foregroundColor(.secondary)
                        Button("选择录屏视频") { openScreenLibrary(.videos) }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                        Text("选择完成后会发送到当前电脑，原来的连拍组会保留。").font(.footnote).foregroundColor(.secondary)
                    }
                }.padding(24)
            }.navigationTitle("截屏 / 录屏").navigationBarTitleDisplayMode(.inline).toolbar { Button("完成") { showScreenTools = false } }
        }.preferredColorScheme(.dark)
    }
    private func openScreenLibrary(_ kind: LibraryPicker.Kind) { libraryKind = kind; libraryPending = true; showScreenTools = false }
    private func openSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
    private func afterDevices() { if scannerPending { scannerPending = false; showScanner = true }; completePairingPresentation() }
    private func queuePairing(_ text: String) {
        pendingPairingText = text
        if showDevices || showScanner { showDevices = false; showScanner = false }
        else { completePairingPresentation() }
    }
    private func completePairingPresentation() {
        guard let text = pendingPairingText else { return }; pendingPairingText = nil
        do { invitation = try Invitation.parse(text); confirmPair = true } catch { model.report(error) }
    }
    private func leaveReview() {
        if model.source == .burst { reviewing = false }
        else if model.source == .library { confirmDiscard = true }
        else { model.clear(); model.restoreLastDraft(); syncDraftPresentation() }
    }
    private func syncDraftPresentation(review: Bool = false) {
        reviewIndex = 0
        if model.source == .burst { burst = true; reviewing = review && !model.items.isEmpty }
        else { reviewing = !model.items.isEmpty }
        if model.items.isEmpty { reviewing = false; model.switchCapture(burst: burst) }
    }
    private func sendCurrent() {
        guard model.target != nil else { showDevices = true; return }
        Task { if await model.send() { model.restoreLastDraft(); syncDraftPresentation() } }
    }
    private func takePhoto() {
        guard !locked, !burst || model.items.count < 10 else { return }
        #if DEBUG
        if testCamera {
            guard let directory = model.directory else { return }
            do {
                let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 480)).image { context in
                    UIColor(red: 0.2, green: 0.3, blue: 0.15, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 480))
                    ("UI \(model.items.count + 1)" as NSString).draw(at: CGPoint(x: 30, y: 150), withAttributes: [.font: UIFont.systemFont(ofSize: 54), .foregroundColor: UIColor.white])
                }
                try model.appendCapture(MediaImporter.cameraImage(image, into: directory), burst: burst)
                if !burst { reviewing = true }
            } catch { model.report(error) }
            return
        }
        #endif
        camera.takePhoto()
        if !reduceMotion {
            captureFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { withAnimation(.easeOut(duration: 0.2)) { captureFlash = false } }
        }
    }
    private func importCapture(_ file: URL, video: Bool) {
        Task {
            defer { try? FileManager.default.removeItem(at: file) }
            guard let directory = model.directory, !model.busy else { return }
            model.busy = true
            defer { model.busy = false }
            do {
                let item: MediaItem
                if video { item = try await MediaImporter.video(file, into: directory) }
                else { item = try MediaImporter.image(file, into: directory) }
                do { try model.appendCapture(item, burst: burst) }
                catch { try? FileManager.default.removeItem(at: item.url); throw error }
                model.message = ""
                if video || !burst { reviewIndex = 0; reviewing = true }
            } catch { model.report(error) }
        }
    }
}

struct MediaThumbnail: View {
    let item: MediaItem
    var maxPixelSize = 2400
    @State private var thumbnail: UIImage?
    var body: some View {
        Group {
            if item.mime == "video/mp4" { ZStack { Color.white.opacity(0.08); Image(systemName: "play.rectangle.fill").font(.system(size: 52)) } }
            else if let thumbnail { Image(uiImage: thumbnail).resizable() }
            else { Color.white.opacity(0.04) }
        }.task(id: item.id) {
            let url = item.url, size = maxPixelSize
            thumbnail = await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: size] as CFDictionary) else { return nil as UIImage? }
                return UIImage(cgImage: image)
            }.value
        }
    }
}

private struct VideoReview: View {
    @State private var player: AVPlayer
    init(url: URL) { _player = State(initialValue: AVPlayer(url: url)) }
    var body: some View { VideoPlayer(player: player).onAppear { player.isMuted = true }.onDisappear { player.pause() } }
}
