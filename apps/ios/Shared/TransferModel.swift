import Foundation
import Combine
import UIKit

@MainActor final class TransferModel: ObservableObject {
    @Published var devices: [PairedDevice] = []
    @Published var selectedId = ""
    @Published var items: [MediaItem] = []
    @Published var busy = false
    @Published var message = ""
    @Published var failure = false
    private let store = DeviceStore()
    private let discovery = Discovery()
    private(set) var directory: URL?
    private var requestId = UUID()
    var target: PairedDevice? { devices.first { $0.id == selectedId } }
    init() {
        do { directory = try MediaImporter.directory(); try reload() } catch { report(error) }
        discovery.resolved = { [weak self] id, addresses, port in
            guard let self, let index = self.devices.firstIndex(where: { $0.id == id }) else { return }
            self.devices[index].addresses = addresses; self.devices[index].port = port
        }
    }
    func reload() throws { devices = try store.devices(); selectedId = store.selectedId }
    func startDiscovery() { discovery.start() }
    func stopDiscovery() { discovery.stop() }
    func select(_ id: String) { do { try store.select(id); selectedId = id } catch { report(error) } }
    func removeDevice(_ id: String) { do { try store.remove(id); try reload() } catch { report(error) } }
    func report(_ error: Error) { failure = true; message = error.localizedDescription }
    func pair(_ invitation: Invitation) async {
        guard !busy else { return }; busy = true; message = "正在配对…"; failure = false
        defer { busy = false }
        do {
            let device = try await PinnedClient(invitation: invitation).pair(invitation, clientId: store.clientId(), name: "CommandV iPhone")
            try store.save(device); try reload(); discovery.start(); message = "已连接「\(device.name)」"
        } catch { report(error) }
    }
    func importProviders(_ providers: [NSItemProvider]) async {
        guard !busy, let directory else { return }
        guard !providers.isEmpty, providers.count + items.count <= 10 else { report(BridgeError.message("每组最多 10 张图片")); return }
        busy = true; failure = false; message = "正在准备素材…"
        defer { busy = false }
        var imported: [MediaItem] = []
        do {
            for provider in providers { imported.append(try await MediaImporter.load(provider, into: directory)) }
            try append(imported); message = "预览后点发送到电脑"
        } catch { imported.forEach { try? FileManager.default.removeItem(at: $0.url) }; report(error) }
    }
    func append(_ values: [MediaItem]) throws {
        let all = items + values
        guard all.count <= 10, all.reduce(0, { $0 + $1.bytes }) <= 100_000_000 else { throw BridgeError.message("每组最多 10 张、100 MB，请先发送已有素材") }
        guard all.count <= 1 || all.allSatisfy({ $0.mime != "video/mp4" }) else { throw BridgeError.message("视频需单独发送，请先发送或清空当前素材") }
        items = all; requestId = UUID(); failure = false
    }
    func removeItem(_ id: UUID) {
        guard !busy else { return }
        if let item = items.first(where: { $0.id == id }) { try? FileManager.default.removeItem(at: item.url) }
        items.removeAll { $0.id == id }; requestId = UUID()
    }
    func clear() { guard !busy else { return }; items.forEach { try? FileManager.default.removeItem(at: $0.url) }; items = []; requestId = UUID() }
    func send() async -> Bool {
        guard !busy, let directory else { return false }
        guard let target else { report(BridgeError.message("请先打开 CommandV 扫码配对电脑")); return false }
        busy = true; failure = false; message = "正在发送到「\(target.name)」…"
        defer { busy = false }
        do {
            let payload = try UploadPayload.prepare(items, directory: directory)
            defer { if payload.temporary { try? FileManager.default.removeItem(at: payload.file) } }
            let result = try await PinnedClient(device: target).send(payload, requestId: requestId)
            guard result.status == "copied" else { throw BridgeError.message(result.error ?? "电脑尚未复制，请保留素材并重试") }
            items.forEach { try? FileManager.default.removeItem(at: $0.url) }; items = []; requestId = UUID()
            message = "已复制到电脑，按 Ctrl+V 粘贴"; return true
        } catch { report(error); return false }
    }
    func cleanup() { discovery.stop(); if let directory { try? FileManager.default.removeItem(at: directory) } }
}
