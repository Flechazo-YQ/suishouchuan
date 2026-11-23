import XCTest
@testable import CommandVCore

final class TransportTests: XCTestCase {
    func testActualReceiverPairPinImageBatchAndRetry() async throws {
        guard let file = ProcessInfo.processInfo.environment["COMMANDV_TEST_FIXTURE"] else { throw XCTSkip("Integration receiver is not configured") }
        struct Fixture: Decodable { let uri: String; let image: String; let legacyPort: Int }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: file)))
        let invitation = try Invitation.parse(fixture.uri)
        let wrong = Invitation(v: invitation.v, deviceId: invitation.deviceId, name: invitation.name, addresses: invitation.addresses, port: invitation.port, fingerprint: String(repeating: "0", count: 64), code: invitation.code, expiresAt: invitation.expiresAt)
        do { _ = try await PinnedClient(invitation: wrong).pair(wrong, clientId: UUID().uuidString, name: "Rejected fingerprint"); XCTFail("Unpinned certificate accepted") }
        catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        let device = try await PinnedClient(invitation: invitation).pair(invitation, clientId: UUID().uuidString, name: "CommandV integration test")
        XCTAssertEqual(device.id, invitation.deviceId)
        let online = await PinnedClient(device: device).checkConnection()
        XCTAssertTrue(online)
        let expired = PairedDevice(id: device.id, name: device.name, addresses: device.addresses, port: device.port,
                                   fingerprint: device.fingerprint, token: "expired-pairing-token")
        let rejected = await PinnedClient(device: expired).checkConnection()
        XCTAssertFalse(rejected)
        var moved = device
        moved.port = fixture.legacyPort
        let legacyAddress = await PinnedClient(device: moved).verifiedAddress()
        XCTAssertTrue(moved.addresses.contains(legacyAddress ?? ""))
        var expiredOnLegacy = expired
        expiredOnLegacy.port = fixture.legacyPort
        let rejectedByLegacy = await PinnedClient(device: expiredOnLegacy).checkConnection()
        XCTAssertFalse(rejectedByLegacy)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("test.png")
        try XCTUnwrap(Data(base64Encoded: fixture.image)).write(to: image)
        let item = MediaItem(url: image, mime: "image/png")
        let payload = try UploadPayload.prepare([item], directory: directory)
        let id = UUID()
        let first = try await PinnedClient(device: device).send(payload, requestId: id)
        XCTAssertEqual(first.status, "copied")
        let retry = try await PinnedClient(device: device).send(payload, requestId: id)
        XCTAssertEqual(retry.requestId, first.requestId)
        XCTAssertEqual(retry.status, "copied")
        let batch = try UploadPayload.prepare(Array(repeating: item, count: 99), directory: directory)
        XCTAssertThrowsError(try UploadPayload.prepare(Array(repeating: item, count: 100), directory: directory))
        let grouped = try await PinnedClient(device: device).send(batch, requestId: UUID())
        XCTAssertEqual(grouped.status, "copied")
        var corrupted = Data(try Data(contentsOf: image)); corrupted.append(0)
        try corrupted.write(to: image)
        do { _ = try await PinnedClient(device: device).send(payload, requestId: UUID()); XCTFail("Corrupted payload accepted") }
        catch let BridgeError.receiver(status, _) { XCTAssertEqual(status, 422) }
    }
}
