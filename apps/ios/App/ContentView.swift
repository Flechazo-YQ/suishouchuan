import SwiftUI
import AVKit
import ImageIO

struct ContentView: View {
    @StateObject private var model = TransferModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showDevices = false
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var cameraVideo = false
    @State private var showScanner = false
    @State private var pairingText = ""
    @State private var invitation: Invitation?
    @State private var confirmPair = false
    @State private var preview: MediaItem?
    private let accent = Color(red: 0.85, green: 0.95, blue: 0.47)

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Button { showDevices = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "desktopcomputer").font(.title2).foregroundColor(accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.target?.name ?? "连接你的电脑").font(.headline)
                                Text(model.target == nil ? "打开 Windows CtrlV，扫码配对" : "同一 Wi-Fi · 点此切换电脑").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer(); Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }.padding().background(Color.white.opacity(0.07)).cornerRadius(20)
                    }.buttonStyle(.plain).disabled(model.busy)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.items.isEmpty ? "随手拍，即刻粘贴" : "准备发送 \(model.items.count) 份素材").font(.title2.bold())
                        Text(model.items.isEmpty ? "照片和截图直接送到电脑剪贴板。" : "检查预览，确认后发送到已配对电脑。").font(.subheadline).foregroundColor(.secondary)
                    }
                    if model.items.isEmpty {
                        VStack(spacing: 18) {
                            Image(systemName: "camera.viewfinder").font(.system(size: 76, weight: .ultraLight)).foregroundColor(accent)
                            Text("拍照、选图，或从系统分享菜单发送").font(.footnote).foregroundColor(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 240).background(Color.white.opacity(0.035)).cornerRadius(24)
                    } else { mediaGrid }
                    HStack(spacing: 10) {
                        action("拍照", icon: "camera.fill") { camera(false) }
                        action("相册", icon: "photo.on.rectangle") { showLibrary = true }
                        action("录像", icon: "video.fill") { camera(true) }
                    }.disabled(model.busy)
                    if !model.items.isEmpty {
                        Button { Task { _ = await model.send() } } label: {
                            HStack { if model.busy { ProgressView().tint(.black) }; Text(model.busy ? "正在处理…" : "发送到电脑").font(.headline) }.frame(maxWidth: .infinity).padding(.vertical, 17)
                        }.foregroundColor(.black).background(accent).cornerRadius(24).disabled(model.busy)
                        Button("清空待发素材") { model.clear() }.font(.footnote).foregroundColor(.secondary).disabled(model.busy).frame(maxWidth: .infinity)
                    }
                    if !model.message.isEmpty {
                        Text(model.message).font(.subheadline).foregroundColor(model.failure ? .orange : accent).frame(maxWidth: .infinity, alignment: .leading).padding().background(Color.white.opacity(0.05)).cornerRadius(16).accessibilityIdentifier("transferStatus")
                    }
                    Text("素材通过局域网直传。发送成功后，手机临时副本自动清理；相册原件保留。").font(.caption).foregroundColor(.secondary)
                }.padding(20)
            }.background(Color(red: 0.055, green: 0.06, blue: 0.065)).navigationTitle("CommandV")
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { showDevices = true } label: { Image(systemName: "qrcode.viewfinder") }.accessibilityLabel("配对电脑") } }
        }.navigationViewStyle(.stack).preferredColorScheme(.dark).tint(accent)
            .sheet(isPresented: $showDevices) { deviceSheet }
            .sheet(isPresented: $showLibrary) { LibraryPicker(limit: 10 - model.items.count) { providers in showLibrary = false; if !providers.isEmpty { Task { await model.importProviders(providers) } } } }
            .fullScreenCover(isPresented: $showCamera) { CameraPicker(video: cameraVideo) { value in showCamera = false; if let value { importCamera(value) } }.ignoresSafeArea() }
            .sheet(isPresented: $showScanner) { NavigationView { QRScanner { text in showScanner = false; parsePairing(text) }.navigationTitle("扫描电脑配对二维码").toolbar { Button("取消") { showScanner = false } } } }
            .sheet(item: $preview) { item in NavigationView { Group { if item.mime == "video/mp4" { VideoPlayer(player: AVPlayer(url: item.url)) } else { MediaThumbnail(item: item).scaledToFit() } }.navigationTitle("发送预览").toolbar { Button("完成") { preview = nil } } } }
            .alert("配对电脑", isPresented: $confirmPair) { Button("取消", role: .cancel) {}; Button("确认配对") { if let invitation { Task { await model.pair(invitation) } } } } message: { Text("允许向「\(invitation?.name ?? "")」发送素材？") }
            .onOpenURL { parsePairing($0.absoluteString) }
            .onChange(of: scenePhase) { phase in if phase == .active { do { try model.reload(); model.startDiscovery() } catch { model.report(error) } } else { model.stopDiscovery() } }
            .onAppear { model.startDiscovery() }
    }
    private var mediaGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 12) {
            ForEach(model.items) { item in
                VStack(spacing: 8) {
                    Button { preview = item } label: { MediaThumbnail(item: item).frame(height: 150).clipped().cornerRadius(14) }.buttonStyle(.plain)
                    HStack { Text(item.mime == "video/mp4" ? "视频" : "图片").font(.caption); Spacer(); Button { model.removeItem(item.id) } label: { Image(systemName: "xmark.circle.fill").font(.title3) }.accessibilityLabel("移除素材").disabled(model.busy) }
                }
            }
        }
    }
    private var deviceSheet: some View {
        NavigationView {
            List {
                Section("已配对电脑") {
                    ForEach(model.devices) { device in Button { model.select(device.id); showDevices = false } label: { HStack { Text(device.name); Spacer(); if device.id == model.selectedId { Image(systemName: "checkmark") } } } }
                        .onDelete { offsets in for index in offsets { model.removeDevice(model.devices[index].id) } }
                    if model.devices.isEmpty { Text("两端连接同一 Wi-Fi 后，扫描电脑上的二维码。").foregroundColor(.secondary) }
                }
                Section {
                    Button("扫描配对二维码") {
                        Task { do { try await requestCamera(video: false); showDevices = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showScanner = true } } catch { model.report(error); showDevices = false } }
                    }
                    TextField("或粘贴电脑端配对链接", text: $pairingText).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("使用配对链接") { showDevices = false; parsePairing(pairingText) }.disabled(pairingText.isEmpty)
                }
                Section { Button("打开系统权限设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }
            }.navigationTitle("连接电脑").toolbar { Button("完成") { showDevices = false } }.disabled(model.busy)
        }.preferredColorScheme(.dark)
    }
    private func action(_ title: String, icon: String, run: @escaping () -> Void) -> some View {
        Button(action: run) { VStack(spacing: 8) { Image(systemName: icon).font(.title2); Text(title).font(.subheadline.weight(.medium)) }.frame(maxWidth: .infinity).padding(.vertical, 18).background(Color.white.opacity(0.08)).cornerRadius(18) }.buttonStyle(.plain)
    }
    private func parsePairing(_ text: String) { do { invitation = try Invitation.parse(text); confirmPair = true } catch { model.report(error) } }
    private func camera(_ video: Bool) { Task { do { try await requestCamera(video: video); cameraVideo = video; showCamera = true } catch { model.report(error) } } }
    private func importCamera(_ value: CameraResult) {
        Task {
            guard let directory = model.directory, !model.busy else { return }
            model.busy = true
            defer { model.busy = false }
            do {
                let item: MediaItem
                switch value { case .image(let image): item = try MediaImporter.cameraImage(image, into: directory); case .video(let url): item = try await MediaImporter.video(url, into: directory) }
                do { try model.append([item]); model.message = "预览后点发送到电脑" }
                catch { try? FileManager.default.removeItem(at: item.url); throw error }
            } catch { model.report(error) }
        }
    }
}

struct MediaThumbnail: View {
    let item: MediaItem
    var body: some View {
        Group {
            if item.mime == "video/mp4" { ZStack { Color.white.opacity(0.08); Image(systemName: "play.rectangle.fill").font(.system(size: 52)) } }
            else if let image = thumbnail { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo") }
        }
    }
    private var thumbnail: UIImage? {
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1200] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
