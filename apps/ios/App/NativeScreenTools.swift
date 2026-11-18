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
            if capture.starting { ProgressView("等待系统授权…") }
            else if capture.active {
                HStack {
                    Label(capture.recording ? "录屏中 \(capture.seconds) 秒" : "采集中 · \(capture.files.count)/10", systemImage: "circle.fill").foregroundColor(capture.recording ? .red : .green)
                    Spacer()
                    Button("停止采集") { Task { await capture.stop() } }.disabled(capture.finishing)
                }
            } else {
                Button("开始屏幕采集") { capture.presentPicker() }.buttonStyle(.borderedProminent).frame(minHeight: 44).disabled(capture.finishing)
            }
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
            captureGuide
        }
        .alert("清空本次屏幕素材？", isPresented: $discard) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { do { try capture.clearImported(); selected = nil } catch { capture.message = error.localizedDescription } }
        } message: { Text("只清理 CommandC 的待发副本。") }
    }

    private var captureGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("用灵动岛逐张截图").font(.headline)
                .accessibilityAddTraits(.isHeader)
            guideStep(1, "开始采集并授权", "点上方的「开始屏幕采集」，在系统面板允许共享整个屏幕。")
            guideStep(2, "长按屏幕顶部的灵动岛", "切到要截图的 App，长按灵动岛里的 CommandC 活动，直到控制面板展开。")
            guideStep(3, "点「截取」，向上轻扫收起", "约 1.5 秒后保存一张。灵动岛计数跳动表示已保存，再截下一张，最多 10 张。")
            guideStep(4, "查看并整组发送", "长按灵动岛后点「查看」。采集结束后，也可回 CommandC 点右下「截屏 / 录屏」。点「预览并发送」，再点右上「确认并发送」。")

            DisclosureGroup("用操作按钮截图") {
                Text("在配有操作按钮的 iPhone 上，打开「设置」→「操作按钮」，滑到「快捷指令」，点下方的选项，在 CommandC 下选「截取一张」。设置一次后，每次先在 CommandC 开始采集，再去目标 App 长按机身操作按钮，等约 1.5 秒即可截一张。")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.top, 6)
            }
            DisclosureGroup("用灵动岛录屏") {
                Text("开始采集后，切到要录制的 App。长按灵动岛，点「录屏」后收起面板。结束时再长按灵动岛，点「停止录屏」。每段最长 30 秒。回 CommandC 的「截屏 / 录屏」预览并发送。")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.top, 6)
            }
        }
    }

    private func guideStep(_ number: Int, _ title: String, _ instruction: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).").monospacedDigit().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(instruction).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("第 \(number) 步：\(title)。\(instruction)")
            .accessibilityIdentifier("screenCaptureGuideStep\(number)")
        }
        .font(.subheadline)
    }

}

private struct ScreenVideoPreview: View {
    @State private var player: AVPlayer
    init(url: URL) { _player = State(initialValue: AVPlayer(url: url)) }
    var body: some View { VideoPlayer(player: player).onDisappear { player.pause() } }
}
