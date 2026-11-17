import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

struct LibraryPicker: UIViewControllerRepresentable {
    let limit: Int
    let finished: ([NSItemProvider]) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = max(1, limit)
        configuration.filter = .any(of: [.images, .videos])
        configuration.selection = .ordered
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(finished) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let finished: ([NSItemProvider]) -> Void
        init(_ finished: @escaping ([NSItemProvider]) -> Void) { self.finished = finished }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) { finished(results.map(\.itemProvider)) }
    }
}

enum CameraResult { case image(UIImage); case video(URL) }
struct CameraPicker: UIViewControllerRepresentable {
    let video: Bool
    let finished: (CameraResult?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [video ? UTType.movie.identifier : UTType.image.identifier]
        picker.videoQuality = .typeMedium; picker.videoMaximumDuration = 30
        picker.cameraCaptureMode = video ? .video : .photo
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(finished) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let finished: (CameraResult?) -> Void
        init(_ finished: @escaping (CameraResult?) -> Void) { self.finished = finished }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finished(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL { finished(.video(url)) }
            else if let image = info[.originalImage] as? UIImage { finished(.image(image)) }
            else { finished(nil) }
        }
    }
}

@MainActor func requestCamera(video: Bool) async throws {
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else { throw BridgeError.message("这台设备没有可用相机") }
    guard await AVCaptureDevice.requestAccess(for: .video) else { throw BridgeError.message("请在系统设置中允许 CommandV 使用相机") }
    if video, !(await AVCaptureDevice.requestAccess(for: .audio)) { throw BridgeError.message("录像需要麦克风权限，请在系统设置中开启") }
}
