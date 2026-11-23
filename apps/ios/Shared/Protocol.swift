import Foundation
import CryptoKit

enum BridgeError: LocalizedError {
    case message(String)
    case receiver(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case let .message(text), let .receiver(_, text): return text
        }
    }
}

struct Invitation: Codable {
    let v: Int
    let deviceId: String
    let name: String
    var addresses: [String]
    var port: Int
    let fingerprint: String
    let code: String
    let expiresAt: Double

    static func parse(_ text: String, now: Date = Date()) throws -> Invitation {
        guard text.utf8.count <= 8192,
              let url = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "imagebridge", url.host == "pair",
              let json = url.queryItems?.first(where: { $0.name == "data" })?.value?.data(using: .utf8),
              let value = try? JSONDecoder().decode(Invitation.self, from: json) else {
            throw BridgeError.message(String(localized: "Scan the pairing QR code in CtrlV or CommandV."))
        }
        guard value.v == 1, UUID(uuidString: value.deviceId) != nil,
              !value.name.isEmpty, value.name.count <= 80,
              !value.addresses.isEmpty, value.addresses.count <= 16,
              value.addresses.allSatisfy(isPrivateAddress), (1...65535).contains(value.port),
              value.fingerprint.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              value.code.range(of: "^[A-Za-z0-9_-]{16,128}$", options: .regularExpression) != nil else {
            throw BridgeError.message(String(localized: "Invalid pairing information. Choose a computer on the same local network."))
        }
        guard value.expiresAt > now.timeIntervalSince1970 * 1000 else {
            throw BridgeError.message(String(localized: "The pairing QR code expired. Refresh it on the computer."))
        }
        return value
    }
}

func isPrivateAddress(_ address: String) -> Bool {
    let parts = address.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return false }
    let numbers = parts.compactMap { Int($0) }
    guard numbers.count == 4, numbers.allSatisfy({ (0...255).contains($0) }) else { return false }
    return numbers[0] == 10 || (numbers[0] == 192 && numbers[1] == 168) || (numbers[0] == 172 && (16...31).contains(numbers[1]))
}

struct PairedDevice: Codable, Identifiable {
    var id: String
    var name: String
    var addresses: [String]
    var port: Int
    let fingerprint: String
    let token: String
}

struct TransferResult: Decodable {
    let requestId: String?
    let status: String?
    let error: String?
}

enum CaptureBatch {
    static let defaultLimit = 10
    static let maximum = 99

    static func limit(_ value: Int) -> Int { min(max(1, value), maximum) }
}

struct MediaItem: Identifiable {
    let id: UUID
    let url: URL
    let mime: String
    var bytes: Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
    init(url: URL, mime: String, id: UUID = UUID()) { self.url = url; self.mime = mime; self.id = id }
}

struct UploadPayload {
    let file: URL
    let route: String
    let mime: String
    let digest: String
    let temporary: Bool
    let imageCount: Int
    static func prepare(_ items: [MediaItem], directory: URL, asBatch: Bool = false) throws -> UploadPayload {
        guard !items.isEmpty, items.count <= CaptureBatch.maximum else { throw BridgeError.message(String(localized: "Choose 1–99 images.")) }
        for item in items {
            let limit = item.mime == "video/mp4" ? 100_000_000 : 32 * 1024 * 1024
            guard item.bytes > 0, item.bytes <= limit else { throw BridgeError.message(String(localized: "Images can be up to 32 MB each. Videos can be up to 100 MB.")) }
        }
        if items.count == 1 && (!asBatch || items[0].mime == "video/mp4") {
            let item = items[0]
            guard ["image/jpeg", "image/png", "video/mp4"].contains(item.mime) else { throw BridgeError.message(String(localized: "This file type isn’t supported.")) }
            return UploadPayload(file: item.url, route: item.mime == "video/mp4" ? "/v1/videos" : "/v1/images", mime: item.mime, digest: try digestFile(item.url), temporary: false, imageCount: 0)
        }
        guard items.allSatisfy({ ["image/jpeg", "image/png"].contains($0.mime) }), items.reduce(0, { $0 + $1.bytes }) <= 100_000_000 else {
            throw BridgeError.message(String(localized: "A batch can contain images only, up to 100 MB in total."))
        }
        struct Entry: Encodable { let bytes: Int; let mime: String; let sha256: String }
        struct Manifest: Encodable { let images: [Entry] }
        // A retry must reproduce the same manifest digest for the same request ID.
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let header = try encoder.encode(Manifest(images: items.map { Entry(bytes: $0.bytes, mime: $0.mime, sha256: try digestFile($0.url)) }))
        guard header.count <= 16384 else { throw BridgeError.message(String(localized: "The batch metadata is too large.")) }
        let file = directory.appendingPathComponent(UUID().uuidString + ".batch")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        do {
            let output = try FileHandle(forWritingTo: file)
            defer { try? output.close() }
            var size = UInt32(header.count).bigEndian
            try withUnsafeBytes(of: &size) { try output.write(contentsOf: $0) }
            try output.write(contentsOf: header)
            for item in items { try copyFile(item.url, to: output) }
        } catch { try? FileManager.default.removeItem(at: file); throw error }
        return UploadPayload(file: file, route: "/v1/batches", mime: "application/x-imagebridge-batch", digest: digestData(header), temporary: true, imageCount: items.count)
    }
}

func digestData(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func digestFile(_ file: URL) throws -> String {
    let input = try FileHandle(forReadingFrom: file)
    defer { try? input.close() }
    var digest = SHA256()
    while let chunk = try input.read(upToCount: 65536), !chunk.isEmpty { digest.update(data: chunk) }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
}
private func copyFile(_ file: URL, to output: FileHandle) throws {
    let input = try FileHandle(forReadingFrom: file)
    defer { try? input.close() }
    while let chunk = try input.read(upToCount: 65536), !chunk.isEmpty { try output.write(contentsOf: chunk) }
}
