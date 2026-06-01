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

/// 커뮤니티 **캡션(짧은 멘트) 온디바이스 텍스트 검열**.
/// 자유 텍스트 UGC 가 생기면 App Store Guideline 1.2 상 욕설·비방 1차 필터가 필요 →
/// 외부 API 없이(비용·Hard Rule #6) 금칙어 리스트 기반 best-effort 차단 + 길이 제한.
/// 못 잡는 케이스는 기존 신고/차단(서버) 흐름이 보완한다. 리스트는 시작 셋 — 운영하며 확장.
enum CommunityTextModerator {

    /// 캡션 최대 길이(자). UX·남용 방지.
    static let maxLength = 60

    /// 금칙어(소문자·기호제거 정규화 후 부분일치). 명백한 욕설·혐오·성적 표현 중심.
    /// 한국어는 어절 경계가 없어 substring 매칭. 우회(공백·기호 삽입)는 정규화로 일부 차단.
    private static let banned: Set<String> = [
        // ko
        "씨발", "시발", "씨바", "ㅅㅂ", "병신", "ㅂㅅ", "개새끼", "새끼", "지랄",
        "좆", "보지", "자지", "섹스", "야동", "창녀", "걸레", "느금마", "니애미", "엠창",
        // en
        "fuck", "shit", "bitch", "asshole", "cunt", "dick", "pussy", "porn",
        "nigger", "faggot", "whore", "slut", "rape",
    ]

    enum Result { case allowed, tooLong, profane }

    /// 캡션 검열(길이 + 금칙어). trim 후 빈 문자열은 allowed(선택 항목).
    static func screen(_ raw: String) -> Result {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .allowed }
        if trimmed.count > maxLength { return .tooLong }
        return containsProfanity(trimmed) ? .profane : .allowed
    }

    /// 길이 무관 — 금칙어 포함 여부만. 앱 전역 텍스트 입력 필드(메모·이름 등)용.
    /// 일반 필드는 길이 제한이 없으므로 `screen` 대신 이걸 쓴다.
    static func containsProfanity(_ raw: String) -> Bool {
        let normalized = normalize(raw)
        for word in banned where normalized.contains(word) { return true }
        return false
    }

    /// 소문자화 + 영숫자/한글 외 문자 제거(공백·기호 삽입 우회 완화).
    private static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        return String(lowered.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
                || (0xAC00...0xD7A3).contains($0.value)   // 한글 음절
                || (0x3130...0x318F).contains($0.value)   // 한글 자모(ㅅㅂ 등)
        })
    }
}
