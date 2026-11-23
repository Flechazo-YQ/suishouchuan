import AppKit
import AVFoundation

enum HelperError: Error, LocalizedError {
    case invalidArguments, imageUnavailable, clipboardRejected, invalidVideo

    var errorDescription: String? {
        switch self {
        case .invalidArguments: return "无效的 CommandV 操作"
        case .imageUnavailable: return "无法读取要复制的图片"
        case .clipboardRejected: return "macOS 剪贴板未能保留素材，请稍后重试"
        case .invalidVideo: return "仅支持 30 秒、6400 万像素以内的 MP4 视频"
        }
    }
}

struct VideoMetadata: Encodable {
    let width: Int
    let height: Int
    let durationMs: Int
}

@main
enum CommandVMac {
    @MainActor private static func copyImage(_ file: URL) throws {
        let bytes = try Data(contentsOf: file)
        guard let source = NSImage(data: bytes), let tiff = source.tiffRepresentation else {
            throw HelperError.imageUnavailable
        }
        let item = NSPasteboardItem()
        guard item.setData(bytes, forType: .png), item.setData(tiff, forType: .tiff) else {
            throw HelperError.clipboardRejected
        }
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.changeCount
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]), pasteboard.changeCount != previous,
              pasteboard.data(forType: .png) == bytes else { throw HelperError.clipboardRejected }
    }

    @MainActor private static func filePaths(_ pasteboard: NSPasteboard) -> [String] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.map { $0.standardizedFileURL.path } ?? []
    }

    @MainActor private static func copyFiles(_ files: [URL]) throws {
        guard (1...99).contains(files.count) else { throw HelperError.invalidArguments }
        for file in files where !FileManager.default.isReadableFile(atPath: file.path) {
            throw CocoaError(.fileReadNoPermission)
        }
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.changeCount
        let items = try files.map { file -> NSPasteboardItem in
            let item = NSPasteboardItem()
            guard item.setString(file.absoluteString, forType: .fileURL) else {
                throw HelperError.clipboardRejected
            }
            return item
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(items), pasteboard.changeCount != previous,
              filePaths(pasteboard) == files.map(\.path) else { throw HelperError.clipboardRejected }
    }

    private static func inspectVideo(_ file: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: file, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw HelperError.invalidVideo
        }
        let seconds = try await asset.load(.duration).seconds
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let bounds = CGRect(origin: .zero, size: size).applying(transform).standardized
        let width = bounds.width.rounded()
        let height = bounds.height.rounded()
        guard seconds.isFinite, seconds > 0, seconds <= 30.1,
              width.isFinite, height.isFinite, width > 0, height > 0,
              width * height <= 64_000_000 else { throw HelperError.invalidVideo }
        return VideoMetadata(width: Int(width), height: Int(height), durationMs: Int((seconds * 1000).rounded()))
    }

    @MainActor static func main() async {
        do {
            let arguments = CommandLine.arguments.dropFirst()
            let files = arguments.dropFirst().map { URL(fileURLWithPath: $0).standardizedFileURL }
            switch arguments.first {
            case "copy-image" where files.count == 1:
                try copyImage(files[0])
            case "copy-files":
                try copyFiles(files)
            case "read-files" where files.isEmpty:
                try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(filePaths(.general)))
            case "video" where files.count == 1:
                let metadata = try await inspectVideo(files[0])
                try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(metadata))
            default: throw HelperError.invalidArguments
            }
        } catch {
            FileHandle.standardError.write(Data(error.localizedDescription.utf8))
            exit(1)
        }
    }
}
