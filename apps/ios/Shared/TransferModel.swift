import Foundation
import Combine
import UIKit

enum MaterialSource { case photo, burst, video, library, shared }

struct TransferDraft: Identifiable {
    let items: [MediaItem]
    let source: MaterialSource
    let requestId: UUID
    var id: UUID { requestId }
    var title: String { items.first?.mime == "video/mp4" ? "待发视频" : "待发 \(items.count) 张" }
}

@MainActor final class TransferModel: ObservableObject {
    @Published var devices: [PairedDevice] = []
    @Published var selectedId = ""
    @Published var items: [MediaItem] = []
    @Published var busy = false
    @Published var message = ""
    @Published var failure = false
    @Published private(set) var savedDrafts: [TransferDraft] = []
    @Published private(set) var source: MaterialSource = .shared
    private let store = DeviceStore()
    private let discovery = Discovery()
    private(set) var directory: URL?
    private(set) var requestId = UUID()
    private let upload: (PairedDevice, UploadPayload, UUID) async throws -> TransferResult
    var target: PairedDevice? { devices.first { $0.id == selectedId } }
    init(loadDevices: Bool = true, upload: @escaping (PairedDevice, UploadPayload, UUID) async throws -> TransferResult = { device, payload, id in
        try await PinnedClient(device: device).send(payload, requestId: id)
    }) {
        self.upload = upload
        do { directory = try MediaImporter.directory(); if loadDevices { try reload() } } catch { report(error) }
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
    func importProviders(_ providers: [NSItemProvider], separately: Bool = false, autoSend: Bool = false) async {
        guard !busy, let directory else { return }
        guard !providers.isEmpty, providers.count + (separately ? 0 : items.count) <= 10 else { report(BridgeError.message("每组最多 10 张图片")); return }
        busy = true; failure = false; message = "正在准备素材…"
        var imported: [MediaItem] = []
        do {
            for provider in providers { imported.append(try await MediaImporter.load(provider, into: directory)) }
            try validate(separately ? imported : items + imported)
            if separately { beginIndependent(.library) }
            try append(imported); message = "预览后点发送到电脑"
        } catch {
            imported.forEach { try? FileManager.default.removeItem(at: $0.url) }
            report(error); busy = false; return
        }
        busy = false
        if autoSend, await send() { restoreLastDraft() }
    }
    func append(_ values: [MediaItem]) throws {
        let all = items + values
        try validate(all)
        items = all; requestId = UUID(); failure = false
    }
    func importScreenFiles(_ files: [URL]) async throws {
        guard !busy, let directory, !files.isEmpty else { throw BridgeError.message("素材仍在处理中，请稍后再试") }
        busy = true
        defer { busy = false }
        var imported: [MediaItem] = []
        do {
            for file in files {
                if file.pathExtension.lowercased() == "mp4" { imported.append(try await MediaImporter.video(file, into: directory)) }
                else { imported.append(try MediaImporter.image(file, into: directory)) }
            }
            try validate(imported)
            beginIndependent(imported.first?.mime == "video/mp4" ? .video : .library)
            try append(imported); message = "预览后确认发送到电脑"; failure = false
        } catch {
            imported.forEach { try? FileManager.default.removeItem(at: $0.url) }
            throw error
        }
    }
    private func validate(_ all: [MediaItem]) throws {
        guard all.count <= 10, all.reduce(0, { $0 + $1.bytes }) <= 100_000_000 else { throw BridgeError.message("每组最多 10 张、100 MB，请先发送已有素材") }
        guard all.count <= 1 || all.allSatisfy({ $0.mime != "video/mp4" }) else { throw BridgeError.message("视频需单独发送，请先发送或清空当前素材") }
    }
    private var snapshot: TransferDraft { TransferDraft(items: items, source: source, requestId: requestId) }
    private func beginIndependent(_ next: MaterialSource) {
        if !items.isEmpty { savedDrafts.append(snapshot) }
        items = []; source = next; requestId = UUID()
    }
    func switchCapture(burst: Bool) {
        guard !busy else { return }
        let next: MaterialSource = burst ? .burst : .photo
        guard source != next else { return }
        if let saved = savedDrafts.first(where: { $0.source == next }) { selectDraft(saved.id) }
        else { beginIndependent(next) }
    }
    func appendCapture(_ item: MediaItem, burst: Bool) throws {
        let next: MaterialSource = item.mime == "video/mp4" ? .video : (burst ? .burst : .photo)
        try validate(next == .burst && source == .burst ? items + [item] : [item])
        if source != next || next != .burst { beginIndependent(next) }
        try append([item])
    }
    func selectDraft(_ id: UUID) {
        guard !busy, let index = savedDrafts.firstIndex(where: { $0.id == id }) else { return }
        let selected = savedDrafts.remove(at: index)
        if !items.isEmpty { savedDrafts.append(snapshot) }
        restore(selected)
    }
    private func restore(_ draft: TransferDraft) {
        items = draft.items; source = draft.source; requestId = draft.requestId
    }
    func restoreLastDraft() {
        guard !busy, items.isEmpty, let draft = savedDrafts.popLast() else { return }
        restore(draft)
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
            let payload = try UploadPayload.prepare(items, directory: directory, asBatch: source == .burst || source == .library)
            defer { if payload.temporary { try? FileManager.default.removeItem(at: payload.file) } }
            let result = try await upload(target, payload, requestId)
            guard result.status == "copied" else { throw BridgeError.message(result.error ?? "电脑尚未复制，请保留素材并重试") }
            items.forEach { try? FileManager.default.removeItem(at: $0.url) }; items = []; requestId = UUID()
            message = "已复制到电脑，按 Ctrl+V 粘贴"; return true
        } catch { report(error); return false }
    }
    func cleanup() { discovery.stop(); if let directory { try? FileManager.default.removeItem(at: directory) } }
}
