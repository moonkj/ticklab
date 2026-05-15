import SwiftUI
import UIKit

/// UIImagePickerController 를 SwiftUI 로 래핑한 카메라 picker.
/// PhotosPicker 는 사진 보관함만 가능 — 카메라는 별도 UIKit 래핑 필요.
struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.cameraDevice = .rear
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraImagePicker
        init(_ parent: CameraImagePicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                // Round 155: camera UIImage 는 imageOrientation 메타데이터로 회전을 표현 →
                // EXIF strip 후 회전 정보가 사라져 90° CCW 로 보임.
                // 픽셀 자체를 회전된 상태로 redraw 한 뒤 인코딩.
                let normalized = Self.normalizeOrientation(image)
                if let data = normalized.jpegData(compressionQuality: 0.85) {
                    // Round 103 (Security C2): strip 실패 시 GPS 원본 저장 금지 — nil 이면 저장 안 함.
                    parent.imageData = EXIFStripper.strippedJPEG(from: data)
                }
            }
            parent.dismiss()
        }

        /// imageOrientation 을 .up 으로 굳혀 픽셀 데이터에 회전을 baked-in.
        private static func normalizeOrientation(_ image: UIImage) -> UIImage {
            if image.imageOrientation == .up { return image }
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
