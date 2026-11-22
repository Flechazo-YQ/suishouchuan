import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers
import AVFoundation

enum MediaImporter {
    static func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CommandV-Outbox", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for child in children {
            let date = (try? child.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if date < Date().addingTimeInterval(-86400) { try? FileManager.default.removeItem(at: child) }
        }
        let session = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        return session
    }

    static func load(_ provider: NSItemProvider, into directory: URL) async throws -> MediaItem {
        let movie = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
        let type = movie ? UTType.movie.identifier : UTType.image.identifier
        guard movie || provider.hasItemConformingToTypeIdentifier(type) else { throw BridgeError.message(String(localized: "Choose a photo or video.")) }
        let copied: URL = try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw BridgeError.message(String(localized: "Download the selected item to your iPhone and try again.")) }
                    let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard bytes > 0, bytes <= 300_000_000 else { throw BridgeError.message(String(localized: "The original exceeds 300 MB. Reduce its size and try again.")) }
                    let target = directory.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
                    try FileManager.default.copyItem(at: url, to: target)
                    continuation.resume(returning: target)
                } catch { continuation.resume(throwing: error) }
            }
        }
        defer { try? FileManager.default.removeItem(at: copied) }
        if movie { return try await video(copied, into: directory) }
        return try image(copied, into: directory)
    }

    static func image(_ input: URL, into directory: URL) throws -> MediaItem {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil) else { throw BridgeError.message(String(localized: "Couldn’t read the image.")) }
        guard CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width) * Double(height) <= 64_000_000 else {
            throw BridgeError.message(String(localized: "Choose a still image up to 64 megapixels."))
        }
        let type = CGImageSourceGetType(source) as String?
        if type == UTType.png.identifier || type == UTType.jpeg.identifier {
            let bytes = try input.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes <= 32 * 1024 * 1024 else { throw BridgeError.message(String(localized: "The image exceeds 32 MB.")) }
            let png = type == UTType.png.identifier
            let output = directory.appendingPathComponent(UUID().uuidString + (png ? ".png" : ".jpg"))
            try FileManager.default.copyItem(at: input, to: output)
            return MediaItem(url: output, mime: png ? "image/png" : "image/jpeg")
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 4096, kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw BridgeError.message(String(localized: "This image format isn’t supported.")) }
        let png = (CGImageSourceGetType(source) as String?) == UTType.png.identifier
        let file = directory.appendingPathComponent(UUID().uuidString + (png ? ".png" : ".jpg"))
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, (png ? UTType.png.identifier : UTType.jpeg.identifier) as CFString, 1, nil) else { throw BridgeError.message(String(localized: "Couldn’t convert the image.")) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw BridgeError.message(String(localized: "Couldn’t save the image.")) }
        let item = MediaItem(url: file, mime: png ? "image/png" : "image/jpeg")
        guard item.bytes <= 32 * 1024 * 1024 else { try? FileManager.default.removeItem(at: file); throw BridgeError.message(String(localized: "The image exceeds 32 MB.")) }
        return item
    }

    static func cameraImage(_ image: UIImage, into directory: URL) throws -> MediaItem {
        let input = directory.appendingPathComponent(UUID().uuidString + ".camera.jpg")
        guard let data = image.jpegData(compressionQuality: 0.95) else { throw BridgeError.message(String(localized: "Couldn’t save the photo.")) }
        try data.write(to: input, options: .atomic)
        defer { try? FileManager.default.removeItem(at: input) }
        return try self.image(input, into: directory)
    }

    static func video(_ input: URL, into directory: URL) async throws -> MediaItem {
        let asset = AVURLAsset(url: input)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, duration <= 30.1 else { throw BridgeError.message(String(localized: "Choose a video up to 30 seconds long.")) }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else { throw BridgeError.message(String(localized: "Couldn’t convert the selected video.")) }
        let output = directory.appendingPathComponent(UUID().uuidString + ".mp4")
        exporter.outputURL = output; exporter.outputFileType = .mp4; exporter.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { continuation in exporter.exportAsynchronously { continuation.resume() } }
        guard exporter.status == .completed else { try? FileManager.default.removeItem(at: output); throw BridgeError.message(exporter.error?.localizedDescription ?? String(localized: "Video conversion failed.")) }
        let item = MediaItem(url: output, mime: "video/mp4")
        guard item.bytes <= 100_000_000 else { try? FileManager.default.removeItem(at: output); throw BridgeError.message(String(localized: "The converted video exceeds 100 MB.")) }
        return item
    }
}
