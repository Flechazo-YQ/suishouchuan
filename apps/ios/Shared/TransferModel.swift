import Foundation
import Combine
import UIKit

enum MaterialSource { case photo, burst, video, library, shared }

enum ComputerConnection: Equatable {
    case checking, connected, disconnected

    var title: String {
        switch self {
        case .checking: return String(localized: "Checking connection…")
        case .connected: return String(localized: "Connected")
        case .disconnected: return String(localized: "Disconnected")
        }
    }
}

struct TransferDraft: Identifiable {
    let items: [MediaItem]
    let source: MaterialSource
    let requestId: UUID
    let originalScreenRecording: URL?
    var id: UUID { requestId }
    var title: String { items.first?.mime == "video/mp4" ? String(localized: "Video ready") : String(localized: "Photos ready: \(items.count)") }
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
    @Published private var connections: [String: ComputerConnection] = [:]
    private let store = DeviceStore()
    private let discovery = Discovery()
    private var connectionTasks: [String: Task<Void, Never>] = [:]
    private var connectionPoll: Task<Void, Never>?
    private(set) var directory: URL?
    private(set) var requestId = UUID()
    private(set) var originalScreenRecording: URL?
    private let upload: (PairedDevice, UploadPayload, UUID) async throws -> TransferResult
    var target: PairedDevice? { devices.first { $0.id == selectedId } }
    init(loadDevices: Bool = true, upload: @escaping (PairedDevice, UploadPayload, UUID) async throws -> TransferResult = { device, payload, id in
        try await PinnedClient(device: device).send(payload, requestId: id)
    }) {
        self.upload = upload
        do { directory = try MediaImporter.directory(); if loadDevices { try reload() } } catch { report(error) }
        discovery.resolved = { [weak self] id, addresses, port in
            guard let self, let index = self.devices.firstIndex(where: { $0.id == id }) else { return }
            let previous = self.devices[index]
            if Set(previous.addresses) != Set(addresses) || previous.port != port {
                self.devices[index].addresses = addresses; self.devices[index].port = port
            }
            if self.connectionPoll != nil { self.checkConnection(self.devices[index]) }
        }
        discovery.removed = { [weak self] id in
            guard let self, self.connectionPoll != nil, let device = self.devices.first(where: { $0.id == id }) else { return }
            self.checkConnection(device)
        }
    }
    func reload() throws {
        let stored = try store.devices()
        devices = stored.map { device in
            devices.first { $0.id == device.id && $0.token == device.token } ?? device
        }
        selectedId = store.selectedId
    }
    func startDiscovery() { discovery.start() }
    func stopDiscovery() { discovery.stop() }
    func connection(for id: String) -> ComputerConnection { connections[id] ?? .checking }
    func startConnectionMonitoring() {
        stopConnectionMonitoring()
        for device in devices { checkConnection(device, entering: true) }
        connectionPoll = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 900_000_000_000) } catch { return }
                guard let self else { return }
                for device in self.devices { self.checkConnection(device) }
            }
        }
    }
    func stopConnectionMonitoring() {
        connectionPoll?.cancel()
        connectionPoll = nil
        connectionTasks.values.forEach { $0.cancel() }
        connectionTasks.removeAll()
    }
    private func checkConnection(_ device: PairedDevice, entering: Bool = false) {
        connectionTasks[device.id]?.cancel()
        if entering, connection(for: device.id) != .checking { connections[device.id] = .checking }
        connectionTasks[device.id] = Task { [weak self] in
            let connected = await PinnedClient(device: device).checkConnection()
            guard let self, !Task.isCancelled, self.devices.contains(device) else { return }
            self.connectionTasks[device.id] = nil
            let status: ComputerConnection = connected ? .connected : .disconnected
            if self.connection(for: device.id) != status { self.connections[device.id] = status }
        }
    }
    func select(_ id: String) { do { try store.select(id); selectedId = id } catch { report(error) } }
    func removeDevice(_ id: String) {
        do {
            try store.remove(id); try reload()
            connectionTasks.removeValue(forKey: id)?.cancel()
            connections.removeValue(forKey: id)
        } catch { report(error) }
    }
    func report(_ error: Error) { failure = true; message = error.localizedDescription }
    func pair(_ invitation: Invitation) async {
        guard !busy else { return }; busy = true; message = String(localized: "Pairing…"); failure = false
        defer { busy = false }
        do {
            let device = try await PinnedClient(invitation: invitation).pair(invitation, clientId: store.clientId(), name: "CommandC iPhone")
            try store.save(device); try reload(); discovery.start(); message = String(localized: "Paired with “\(device.name)”")
            connections[device.id] = .connected
        } catch { report(error) }
    }
    func importProviders(_ providers: [NSItemProvider], separately: Bool = false, autoSend: Bool = false, limit: Int = CaptureBatch.defaultLimit) async {
        guard !busy, let directory else { return }
        guard !providers.isEmpty, providers.count + (separately ? 0 : items.count) <= limit else {
            report(BridgeError.message(String(localized: "This batch can hold up to \(limit) images.")))
            return
        }
        busy = true; failure = false; message = String(localized: "Preparing items…")
        var imported: [MediaItem] = []
        do {
            for provider in providers { imported.append(try await MediaImporter.load(provider, into: directory)) }
            try validate(separately ? imported : items + imported)
            if separately { beginIndependent(.library) }
            try append(imported); message = String(localized: "Review and send your items to the computer.")
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
        guard !busy, let directory, !files.isEmpty else { throw BridgeError.message(String(localized: "Your items are still being prepared. Try again shortly.")) }
        busy = true
        defer { busy = false }
        var imported: [MediaItem] = []
        do {
            for file in files {
                try Task.checkCancellation()
                if file.pathExtension.lowercased() == "mp4" { imported.append(try await MediaImporter.video(file, into: directory)) }
                else { imported.append(try MediaImporter.image(file, into: directory)) }
            }
            try Task.checkCancellation()
            try validate(imported)
            beginIndependent(imported.first?.mime == "video/mp4" ? .video : .library)
            try append(imported)
            originalScreenRecording = imported.first?.mime == "video/mp4" ? files.first : nil
            message = String(localized: "Review your captures, then tap Send.")
            failure = false
        } catch {
            imported.forEach { try? FileManager.default.removeItem(at: $0.url) }
            throw error
        }
    }
    private func validate(_ all: [MediaItem]) throws {
        guard all.count <= CaptureBatch.maximum, all.reduce(0, { $0 + $1.bytes }) <= 100_000_000 else {
            throw BridgeError.message(String(localized: "Send your current batch first. Each batch holds up to 99 images and 100 MB."))
        }
        guard all.count <= 1 || all.allSatisfy({ $0.mime != "video/mp4" }) else { throw BridgeError.message(String(localized: "Send or clear the current items first. Videos must be sent individually.")) }
    }
    private var snapshot: TransferDraft {
        TransferDraft(items: items, source: source, requestId: requestId, originalScreenRecording: originalScreenRecording)
    }
    private func beginIndependent(_ next: MaterialSource) {
        if !items.isEmpty { savedDrafts.append(snapshot) }
        items = []; source = next; requestId = UUID(); originalScreenRecording = nil
    }
    func switchCapture(burst: Bool) {
        guard !busy else { return }
        let next: MaterialSource = burst ? .burst : .photo
        guard source != next else { return }
        if let saved = savedDrafts.first(where: { $0.source == next }) { selectDraft(saved.id) }
        else { beginIndependent(next) }
    }
    func appendCapture(_ item: MediaItem, burst: Bool, limit: Int = CaptureBatch.defaultLimit) throws {
        let next: MaterialSource = item.mime == "video/mp4" ? .video : (burst ? .burst : .photo)
        let limit = CaptureBatch.limit(limit)
        if next == .burst && source == .burst && items.count >= limit {
            throw BridgeError.message(String(localized: "This batch can hold up to \(limit) images."))
        }
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
        originalScreenRecording = draft.originalScreenRecording
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
    func clear() {
        guard !busy else { return }
        items.forEach { try? FileManager.default.removeItem(at: $0.url) }
        items = []; requestId = UUID(); originalScreenRecording = nil
    }
    func send() async -> Bool {
        guard !busy, let directory else { return false }
        guard let target else { report(BridgeError.message(String(localized: "Open CommandC and scan a QR code to pair a computer first."))); return false }
        busy = true; failure = false; message = String(localized: "Sending to “\(target.name)”…")
        defer { busy = false }
        do {
            let payload = try UploadPayload.prepare(items, directory: directory, asBatch: source == .burst || source == .library)
            defer { if payload.temporary { try? FileManager.default.removeItem(at: payload.file) } }
            let result = try await upload(target, payload, requestId)
            guard result.status == "copied" else {
                let receiverDetail = Bundle.main.preferredLocalizations.first == "zh-Hans" ? result.error : nil
                throw BridgeError.message(receiverDetail ?? String(localized: "The computer hasn’t copied the items. Keep them and try again."))
            }
            items.forEach { try? FileManager.default.removeItem(at: $0.url) }
            items = []; requestId = UUID(); originalScreenRecording = nil
            message = String(localized: "Copied. Paste with Ctrl+V on Windows or ⌘V on Mac."); return true
        } catch {
            if Task.isCancelled { message = String(localized: "Sending canceled. Your items are ready to retry.") }
            else { report(error) }
            return false
        }
    }
    func cleanup() { discovery.stop(); if let directory { try? FileManager.default.removeItem(at: directory) } }
}
