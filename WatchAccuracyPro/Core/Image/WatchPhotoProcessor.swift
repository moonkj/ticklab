import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Sprint 6 (P2-3): 시계 전용 사진 자동 보정 파이프라인.
/// Core Image 온디바이스 처리 — 서버/외부 전송 없음.
///
/// 보정 순서:
///   ① 화이트 밸런스 / 노출 자동 조정
///   ② 하이라이트 억제 (사파이어 크리스털 반사 감소)
///   ③ 샤프닝
///   ④ 비네팅 (선택, 매거진 스타일)
enum WatchPhotoProcessor {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// 표준 보정 — 일반 시계 사진.
    static func process(_ data: Data, style: ProcessingStyle = .standard) -> Data? {
        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else { return nil }
        var ci = CIImage(cgImage: cgImage)

        switch style {
        case .standard:
            ci = autoExposure(ci)
            ci = reduceHighlights(ci, amount: 0.3)
            ci = sharpen(ci, radius: 1.5, sharpness: 0.5)
        case .caseback:
            ci = autoExposure(ci)
            ci = sharpen(ci, radius: 2.0, sharpness: 0.7)
        case .vivid:
            ci = autoExposure(ci)
            ci = vibrance(ci, amount: 0.4)
            ci = sharpen(ci, radius: 1.0, sharpness: 0.4)
        }

        guard let output = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: output, scale: uiImage.scale, orientation: uiImage.imageOrientation)
            .jpegData(compressionQuality: PhotoQuality.current.jpegQuality)
    }

    // MARK: - Filters

    private static func autoExposure(_ ci: CIImage) -> CIImage {
        let filter = CIFilter.exposureAdjust()
        filter.inputImage = ci
        // 자동 노출: 히스토그램 기반 아님 — 약한 +0.2EV로 시계 다이얼 디테일 살림
        filter.ev = 0.15
        return filter.outputImage ?? ci
    }

    private static func reduceHighlights(_ ci: CIImage, amount: Float) -> CIImage {
        let filter = CIFilter.highlightShadowAdjust()
        filter.inputImage = ci
        filter.highlightAmount = 1.0 - amount  // 1.0 = 원본, 0.0 = 완전 억제
        filter.shadowAmount = 0.0
        return filter.outputImage ?? ci
    }

    private static func sharpen(_ ci: CIImage, radius: Float, sharpness: Float) -> CIImage {
        let filter = CIFilter.unsharpMask()
        filter.inputImage = ci
        filter.radius = radius
        filter.intensity = sharpness
        return filter.outputImage ?? ci
    }

    private static func vibrance(_ ci: CIImage, amount: Float) -> CIImage {
        let filter = CIFilter.vibrance()
        filter.inputImage = ci
        filter.amount = amount
        return filter.outputImage ?? ci
    }
}

enum ProcessingStyle: String, CaseIterable, Identifiable {
    case standard
    case caseback
    case vivid
    var id: String { rawValue }
}
