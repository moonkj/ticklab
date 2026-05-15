import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// EXIF (GPS, device id, timestamps) strip 후 disk 저장.
/// Pivot Addendum Security: 일기 사진 업로드 시 위치/촬영 metadata 절대 보존 X.
enum EXIFStripper {
    /// JPEG/HEIC 데이터를 받아 EXIF 제거 후 새 JPEG Data 반환.
    /// Round 142 (사용자 보고): 카메라 사진이 반시계 90° 회전돼 저장됨.
    /// 원인: EXIF Orientation 키까지 제거되어 raw pixel orientation 으로 디코드되는데,
    /// CGImage 자체는 항상 .up 으로 가정. UIImage 로 한 번 normalize 해 픽셀을 재배열한 후 jpeg 인코딩.
    static func strippedJPEG(from data: Data) -> Data? {
        guard let uiImage = UIImage(data: data) else { return nil }
        let normalized = uiImage.imageOrientation == .up
            ? uiImage
            : normalizedImage(uiImage)
        return normalized.jpegData(compressionQuality: 0.85)
    }

    /// 회전 적용된 픽셀로 redraw — UIImage.normalizedOrientation.
    private static func normalizedImage(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// photos 디렉토리 URL — 앱 업데이트 후에도 동일 위치.
    private static var photosDirectoryURL: URL? {
        guard let supportDir = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = supportDir.appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// EXIF strip 후 저장. **파일명(UUID.jpg)만 반환** — 절대 경로 저장 금지.
    /// 앱 업데이트 시 컨테이너 UUID 변경으로 절대 경로가 깨지는 문제 방지.
    static func savePhoto(_ data: Data) -> String? {
        guard let stripped = strippedJPEG(from: data),
              let dir = photosDirectoryURL else { return nil }
        let filename = "\(UUID().uuidString).jpg"
        let url = dir.appendingPathComponent(filename)
        do {
            try stripped.write(to: url, options: .atomic)
            return filename  // 파일명만 반환
        } catch {
            return nil
        }
    }

    /// 저장된 path(파일명 또는 레거시 절대경로)를 현재 유효한 절대경로로 resolve.
    /// 기존 절대경로로 저장된 데이터 자동 마이그레이션 지원.
    static func resolvePhotoPath(_ stored: String) -> String? {
        // 파일명만 있는 경우 (신규 방식)
        if !stored.contains("/") {
            return photosDirectoryURL?.appendingPathComponent(stored).path
        }
        // 절대 경로인 경우 — 파일이 존재하면 그대로 사용, 없으면 파일명 기준으로 재시도 (레거시 마이그레이션).
        if FileManager.default.fileExists(atPath: stored) { return stored }
        let filename = URL(fileURLWithPath: stored).lastPathComponent
        guard let resolved = photosDirectoryURL?.appendingPathComponent(filename).path else { return nil }
        return FileManager.default.fileExists(atPath: resolved) ? resolved : nil
    }
}
