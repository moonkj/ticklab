import UIKit
#if canImport(SensitiveContentAnalysis)
import SensitiveContentAnalysis
#endif

/// 커뮤니티 사진 업로드 전 **온디바이스 사전 검열**. (검열 방식: 기기 사전필터 + 신고기반)
/// Apple SensitiveContentAnalysis(iOS 17+, 무료·프라이버시) — 노출/민감 콘텐츠 best-effort 차단.
/// 외부 vision API 미사용(비용·Hard Rule #6 회피). 폭력/저작권 등은 못 잡으므로 서버 신고기반과 병행.
enum CommunityModerationService {

    enum Result {
        case allowed
        case blocked        // 민감 콘텐츠 감지 → 게시 금지
        case unavailable    // 시스템 기능 비활성/미지원 → 통과(신고기반에 위임)
    }

    /// 업로드 직전 호출. blocked 면 게시 막고 안내 카드 표시.
    static func screen(_ image: UIImage) async -> Result {
        #if canImport(SensitiveContentAnalysis)
        if #available(iOS 17.0, *) {
            guard let cg = image.cgImage else { return .unavailable }
            let analyzer = SCSensitivityAnalyzer()
            // 사용자가 "민감한 콘텐츠 경고"를 끈 경우 .disabled → 사전 차단 불가, 신고기반 위임.
            guard analyzer.analysisPolicy != .disabled else { return .unavailable }
            do {
                let response = try await analyzer.analyzeImage(cg)
                return response.isSensitive ? .blocked : .allowed
            } catch {
                return .unavailable
            }
        } else {
            return .unavailable
        }
        #else
        return .unavailable
        #endif
    }
}
