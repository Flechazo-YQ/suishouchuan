import XCTest
#if canImport(CommandVCore)
@testable import CommandVCore
#else
@testable import CommandV
#endif

final class ProtocolTests: XCTestCase {
    func testOnlyPrivateIPv4Accepted() {
        for value in ["10.0.0.1", "172.16.0.2", "172.31.255.2", "192.168.1.10"] { XCTAssertTrue(isPrivateAddress(value), value) }
        for value in ["127.0.0.1", "8.8.8.8", "172.32.0.1", "192.168.1.999", "10.0.0.1.evil", "::1", "10..0.1", "10.1.1.-1"] { XCTAssertFalse(isPrivateAddress(value), value) }
    }
    private func invitation(address: String = "192.168.1.2", expiry: Double = Date().addingTimeInterval(100).timeIntervalSince1970 * 1000) throws -> String {
        let object = Invitation(v: 1, deviceId: UUID().uuidString, name: "测试电脑", addresses: [address], port: 43821, fingerprint: String(repeating: "a", count: 64), code: String(repeating: "b", count: 32), expiresAt: expiry)
        let text = String(data: try JSONEncoder().encode(object), encoding: .utf8)!
        var url = URLComponents(); url.scheme = "imagebridge"; url.host = "pair"; url.queryItems = [URLQueryItem(name: "data", value: text)]
        return url.string!
    }
    func testPairingRejectsExpiredPublicAndWrongScheme() throws {
        XCTAssertEqual(try Invitation.parse(invitation()).name, "测试电脑")
        XCTAssertThrowsError(try Invitation.parse(invitation(address: "8.8.8.8")))
        XCTAssertThrowsError(try Invitation.parse(invitation(expiry: 1)))
        XCTAssertThrowsError(try Invitation.parse(invitation().replacingOccurrences(of: "imagebridge:", with: "https:")))
    }
    func testBatchMatchesWindowsWireFormat() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("a.png"), second = directory.appendingPathComponent("b.jpg")
        try Data([1, 2, 3]).write(to: first); try Data([4, 5]).write(to: second)
        let payload = try UploadPayload.prepare([MediaItem(url: first, mime: "image/png"), MediaItem(url: second, mime: "image/jpeg")], directory: directory)
        XCTAssertEqual(payload.route, "/v1/batches")
        let data = try Data(contentsOf: payload.file)
        let count = data.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        let header = data.subdata(in: 4..<(4 + count))
        XCTAssertEqual(digestData(header), payload.digest)
        XCTAssertEqual(Array(data.suffix(5)), [1,2,3,4,5])
        struct Entry: Decodable { let bytes: Int; let mime: String; let sha256: String }
        struct Manifest: Decodable { let images: [Entry] }
        let manifest = try JSONDecoder().decode(Manifest.self, from: header)
        XCTAssertEqual(manifest.images.map(\.bytes), [3,2])
        XCTAssertEqual(manifest.images[0].sha256, digestData(Data([1,2,3])))
    }
    func testRejectsEmptyAndMixedVideoBatch() throws {
        let directory = FileManager.default.temporaryDirectory
        XCTAssertThrowsError(try UploadPayload.prepare([], directory: directory))
        let file = directory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertThrowsError(try UploadPayload.prepare([MediaItem(url: file, mime: "video/mp4"), MediaItem(url: file, mime: "image/png")], directory: directory))
    }
}
