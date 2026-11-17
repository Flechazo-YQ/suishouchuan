import SwiftUI
import AVKit

@available(iOS 27.0, *)
struct NativeScreenTools: View {
    @ObservedObject private var capture = ScreenCaptureSession.shared
    @State private var importing = false
    @State private var discard = false
    @State private var selected: URL?
    let review: ([URL]) async throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("跨 App 屏幕采集", systemImage: "rectangle.dashed.badge.record").font(.title3.weight(.semibold))
            Text("先允许共享整个屏幕，再切换到要截取的 App。展开灵动岛，点“截取”后收起面板，1.5 秒后保存画面。每组最多 10 张。").foregroundColor(.secondary)
            if capture.starting { ProgressView("等待系统授权…") }
            else if capture.active {
                HStack {
                    Label(capture.recording ? "录屏中 \(capture.seconds) 秒" : "采集中 · \(capture.files.count)/10", systemImage: "circle.fill").foregroundColor(capture.recording ? .red : .green)
                    Spacer()
                    Button("停止采集") { Task { await capture.stop() } }.disabled(capture.finishing)
                }
                HStack {
                    Button("1.5 秒后截取") { run { try await capture.captureFrame() } }.disabled(!capture.canCapture)
                    Button(capture.recording ? "停止录屏" : "开始录屏") { run { try await capture.toggleRecording() } }.disabled(capture.pendingShot || capture.finishing || !capture.files.isEmpty)
                }.buttonStyle(.bordered)
            } else {
                Button("开始屏幕采集") { capture.presentPicker() }.buttonStyle(.borderedProminent).frame(minHeight: 44).disabled(capture.finishing)
            }
            Text("操作按钮：设置 → 操作按钮 → 快捷指令 → CommandV“截取一张”。先开始采集，再在目标页面按下操作按钮；也可选择“开始或停止录屏”。").font(.footnote).foregroundColor(.secondary)
            if !capture.message.isEmpty { Text(capture.message).font(.footnote).foregroundColor(.secondary).accessibilityIdentifier("screenCaptureStatus") }
            if capture.pendingShot || capture.finishing { ProgressView(capture.pendingShot ? "请收起控制面板，正在准备截图…" : "正在保存录屏…") }
            if !capture.files.isEmpty {
                Divider()
                Text(capture.isVideo ? "待发录屏" : "本次截图 · \(capture.files.count) 张").font(.headline)
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(capture.files, id: \.self) { file in
                            VStack(spacing: 4) {
                                Button { selected = file } label: {
                                    MediaThumbnail(item: MediaItem(url: file, mime: capture.isVideo ? "video/mp4" : "image/jpeg"), maxPixelSize: 240).scaledToFit().frame(width: 85, height: 110)
                                }.accessibilityLabel("查看屏幕素材")
                                Button("移除") { do { try capture.remove(file); if selected == file { selected = nil } } catch { capture.message = error.localizedDescription } }
                            }
                        }
                    }
                }
                if let selected, capture.files.contains(selected) {
                    if capture.isVideo { ScreenVideoPreview(url: selected).frame(height: 240) }
                    else { MediaThumbnail(item: MediaItem(url: selected, mime: "image/jpeg")).scaledToFit().frame(maxHeight: 320) }
                }
                HStack {
                    Button(importing ? "正在准备…" : "预览并发送") {
                        importing = true
                        Task {
                            await capture.stop()
                            do { try await review(capture.files); try capture.clearImported() }
                            catch { capture.message = error.localizedDescription }
                            importing = false
                        }
                    }.buttonStyle(.borderedProminent).disabled(importing || capture.pendingShot || capture.recording || capture.finishing)
                    Button("清空", role: .destructive) { discard = true }.disabled(importing || capture.pendingShot || capture.recording || capture.finishing)
                }
                Text("只有在预览页确认后才发送；原来的相机连拍组会保留。").font(.footnote).foregroundColor(.secondary)
            }
        }
        .alert("清空本次屏幕素材？", isPresented: $discard) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { do { try capture.clearImported(); selected = nil } catch { capture.message = error.localizedDescription } }
        } message: { Text("只清理 CommandV 的待发副本。") }
    }
    private func run(_ action: @escaping () async throws -> Void) { Task { do { try await action() } catch { capture.message = error.localizedDescription } } }
}

private struct ScreenVideoPreview: View {
    @State private var player: AVPlayer
    init(url: URL) { _player = State(initialValue: AVPlayer(url: url)) }
    var body: some View { VideoPlayer(player: player).onDisappear { player.pause() } }
}
