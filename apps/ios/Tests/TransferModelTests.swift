#if canImport(CommandV)
import XCTest
import UIKit
@testable import CommandV

@MainActor final class TransferModelTests: XCTestCase {
    private let device = PairedDevice(id: "test-pc", name: "Test PC", addresses: ["192.168.1.2"], port: 43821, fingerprint: String(repeating: "a", count: 64), token: "test-only")

    private func image(_ model: TransferModel) throws -> MediaItem {
        let canvas = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 32)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
        }
        return try MediaImporter.cameraImage(canvas, into: XCTUnwrap(model.directory))
    }
    private func configure(_ model: TransferModel) { model.devices = [device]; model.selectedId = device.id }

    func testAlbumAutoSendPreservesBurstFilesAndRequestId() async throws {
        var uploadedFiles: [URL] = []
        let model = TransferModel(loadDevices: false, upload: { _, payload, id in
            uploadedFiles.append(payload.file)
            return TransferResult(requestId: id.uuidString, status: "copied", error: nil)
        })
        defer { model.cleanup() }
        configure(model)
        let first = try image(model), second = try image(model), original = try image(model)
        try model.appendCapture(first, burst: true); try model.appendCapture(second, burst: true)
        let originalRequest = model.requestId
        let provider = try XCTUnwrap(NSItemProvider(contentsOf: original.url))
        await model.importProviders([provider], separately: true, autoSend: true)
        XCTAssertEqual(uploadedFiles.count, 1)
        XCTAssertFalse([first.url, second.url, original.url].contains(try XCTUnwrap(uploadedFiles.first)))
        XCTAssertEqual(model.items.map(\.id), [first.id, second.id])
        XCTAssertEqual(model.requestId, originalRequest)
        XCTAssertEqual(model.source, .burst)
        XCTAssertTrue(model.savedDrafts.isEmpty)
        XCTAssertTrue([first.url, second.url, original.url].allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertFalse(FileManager.default.fileExists(atPath: uploadedFiles[0].path))
    }

    func testFailedAlbumRetryAndDraftSwitchKeepIndependentIds() async throws {
        var attempts: [UUID] = []
        let model = TransferModel(loadDevices: false, upload: { _, _, id in
            attempts.append(id)
            if attempts.count == 1 { throw BridgeError.message("离线测试") }
            return TransferResult(requestId: id.uuidString, status: "copied", error: nil)
        })
        defer { model.cleanup() }
        configure(model)
        let burstImage = try image(model), original = try image(model)
        try model.appendCapture(burstImage, burst: true)
        let burstRequest = model.requestId
        await model.importProviders([try XCTUnwrap(NSItemProvider(contentsOf: original.url))], separately: true, autoSend: true)
        XCTAssertTrue(model.failure)
        XCTAssertEqual(model.source, .library)
        let albumRequest = model.requestId, imported = try XCTUnwrap(model.items.first)
        XCTAssertNotEqual(albumRequest, burstRequest)
        model.selectDraft(burstRequest)
        XCTAssertEqual(model.items.map(\.id), [burstImage.id])
        XCTAssertEqual(model.requestId, burstRequest)
        model.selectDraft(albumRequest)
        XCTAssertEqual(model.requestId, albumRequest)
        let sent = await model.send()
        XCTAssertTrue(sent)
        XCTAssertEqual(attempts, [albumRequest, albumRequest])
        model.restoreLastDraft()
        XCTAssertEqual(model.items.map(\.id), [burstImage.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: burstImage.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: imported.url.path))
    }

    func testCaptureSwitchAndLimitDoNotDiscardExistingGroup() throws {
        let model = TransferModel(loadDevices: false)
        defer { model.cleanup() }
        for _ in 0..<10 { try model.appendCapture(image(model), burst: true) }
        let originalIds = model.items.map(\.id), request = model.requestId
        XCTAssertThrowsError(try model.appendCapture(image(model), burst: true))
        XCTAssertEqual(model.items.map(\.id), originalIds)
        model.switchCapture(burst: false)
        try model.appendCapture(image(model), burst: false)
        model.clear(); model.restoreLastDraft()
        XCTAssertEqual(model.items.map(\.id), originalIds)
        XCTAssertEqual(model.requestId, request)
        XCTAssertTrue(model.items.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
    }
}
#endif
