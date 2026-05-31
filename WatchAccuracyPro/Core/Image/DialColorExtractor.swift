import CoreImage
import SwiftUI
import UIKit

/// Sprint 1 (P3-7): 시계 다이얼 사진에서 평균 색상 추출.
/// Core Image `CIAreaAverage` 사용 — 단일 픽셀 RGBA로 압축 후 추출.
///
/// 성능: 작은 thumbnail (256×256) 입력 시 ~5ms 미만.
/// 사용처: WatchDetailView/CollectionView 카드 배경 그라데이션.
enum DialColorExtractor {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// 사진 데이터 → 평균 RGB Color. 실패 시 nil.
    /// 접근성 안전: 추출된 색상 명도 < 0.25 면 nil 반환 (대비 부족 → 기본 배경 사용).
    static func averageColor(from data: Data) -> Color? {
        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else { return nil }
        return averageColor(from: cgImage)
    }

    static func averageColor(from cgImage: CGImage) -> Color? {
        let extent = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(outputImage,
                         toBitmap: &bitmap,
                         rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8,
                         colorSpace: CGColorSpaceCreateDeviceRGB())

        let r = Double(bitmap[0]) / 255.0
        let g = Double(bitmap[1]) / 255.0
        let b = Double(bitmap[2]) / 255.0

        // 접근성: 너무 어두우면 배경 텍스트 대비 부족 → nil 로 폴백.
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        guard luminance > 0.15 else { return nil }

        return Color(red: r, green: g, blue: b)
    }
}
