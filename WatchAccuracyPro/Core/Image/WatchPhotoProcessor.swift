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

    static func process(_ data: Data, style: ProcessingStyle = .standard) -> Data? {
        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else { return nil }
        var ci = CIImage(cgImage: cgImage)

        switch style {

        case .standard:
            // 자연스러운 시계 사진 — 반사 억제 + 미세 샤프닝
            ci = exposure(ci, ev: 0.2)
            ci = reduceHighlights(ci, amount: 0.55)   // 사파이어 반사 강하게 억제
            ci = sharpen(ci, radius: 2.5, intensity: 0.65)
            ci = toneCurve(ci, shadows: 0.05, highlights: -0.05)  // 살짝 플랫

        case .caseback:
            // 케이스백/각인 전용 — 명암 대비 극대화, 텍스트 가독성
            ci = exposure(ci, ev: 0.1)
            ci = contrast(ci, amount: 1.4)            // 대비 40% 강화
            ci = sharpen(ci, radius: 3.5, intensity: 1.2)  // 강한 샤프닝
            ci = toneCurve(ci, shadows: -0.08, highlights: 0.08) // 명암 분리

        case .vivid:
            // 선명하고 인상적인 SNS용 — 채도 + 색감 강화
            ci = exposure(ci, ev: 0.3)
            ci = vibrance(ci, amount: 0.8)            // 채도 강하게
            ci = saturation(ci, amount: 1.25)         // 전체 채도 25% 추가
            ci = contrast(ci, amount: 1.15)
            ci = sharpen(ci, radius: 2.0, intensity: 0.8)
            ci = toneCurve(ci, shadows: 0.0, highlights: -0.1) // 하이라이트 약간 억제
        }

        guard let output = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: output, scale: uiImage.scale, orientation: uiImage.imageOrientation)
            .jpegData(compressionQuality: PhotoQuality.current.jpegQuality)
    }

    // MARK: - Filters

    private static func exposure(_ ci: CIImage, ev: Float) -> CIImage {
        let f = CIFilter.exposureAdjust()
        f.inputImage = ci; f.ev = ev
        return f.outputImage ?? ci
    }

    private static func contrast(_ ci: CIImage, amount: Float) -> CIImage {
        let f = CIFilter.colorControls()
        f.inputImage = ci; f.contrast = amount; f.saturation = 1.0; f.brightness = 0
        return f.outputImage ?? ci
    }

    private static func saturation(_ ci: CIImage, amount: Float) -> CIImage {
        let f = CIFilter.colorControls()
        f.inputImage = ci; f.saturation = amount; f.contrast = 1.0; f.brightness = 0
        return f.outputImage ?? ci
    }

    private static func reduceHighlights(_ ci: CIImage, amount: Float) -> CIImage {
        let f = CIFilter.highlightShadowAdjust()
        f.inputImage = ci
        f.highlightAmount = 1.0 - amount
        f.shadowAmount = 0.1   // 그림자 살짝 밝혀 디테일 보존
        return f.outputImage ?? ci
    }

    private static func sharpen(_ ci: CIImage, radius: Float, intensity: Float) -> CIImage {
        let f = CIFilter.unsharpMask()
        f.inputImage = ci; f.radius = radius; f.intensity = intensity
        return f.outputImage ?? ci
    }

    private static func vibrance(_ ci: CIImage, amount: Float) -> CIImage {
        let f = CIFilter.vibrance()
        f.inputImage = ci; f.amount = amount
        return f.outputImage ?? ci
    }

    /// 섀도/하이라이트 독립 조정 — 커브 근사.
    private static func toneCurve(_ ci: CIImage, shadows: Float, highlights: Float) -> CIImage {
        let f = CIFilter.highlightShadowAdjust()
        f.inputImage = ci
        f.shadowAmount = shadows
        f.highlightAmount = 1.0 + highlights
        return f.outputImage ?? ci
    }
}

enum ProcessingStyle: String, CaseIterable, Identifiable {
    case standard
    case caseback
    case vivid
    var id: String { rawValue }
}
