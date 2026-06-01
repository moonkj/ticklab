import Foundation

/// 커뮤니티(익명 사진 피드) DTO — Supabase REST 응답 매핑. `docs/community/schema.sql` 대응.
/// 원격 데이터이므로 SwiftData @Model 아님. 순수 Codable struct.
enum Community {

    /// 게시물 상태 — 서버 `status` 컬럼.
    enum PostStatus: String, Codable {
        case approved, hidden, blocked
    }

    /// 피드 게시물.
    struct Post: Codable, Identifiable, Equatable {
        let id: String              // uuid
        let authorUID: String       // 내부 식별자(화면엔 비노출 — 익명)
        let imagePath: String       // Storage 'community' 경로
        let brand: String?
        let caption: String?        // 짧은 한 줄 멘트(선택) — 온디바이스 텍스트 검열 통과분만
        let authorName: String?     // 공개 프로필 표시명(신원 전환). nil = 구 익명 글
        let authorAvatarPath: String?
        var likeCount: Int
        let status: PostStatus
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case authorUID = "author_uid"
            case imagePath = "image_path"
            case brand
            case caption
            case authorName = "author_name"
            case authorAvatarPath = "author_avatar_path"
            case likeCount = "like_count"
            case status
            case createdAt = "created_at"
        }

        /// 현재 익명 사용자(uid)가 작성자인가 — 본인 글은 게이팅/검열 예외.
        func isMine(currentUID: String?) -> Bool {
            guard let currentUID else { return false }
            return authorUID == currentUID
        }
    }

    /// 운영 대시보드 — 신고 항목(관리자 조회용).
    struct AdminReport: Codable, Identifiable {
        let postID: String
        let reason: String
        let createdAt: Date
        var id: String { "\(postID)|\(createdAt.timeIntervalSince1970)" }
        enum CodingKeys: String, CodingKey {
            case postID = "post_id"
            case reason
            case createdAt = "created_at"
        }
    }

    /// 운영 통계.
    struct OpsStats {
        var activeUsers: Int = 0
        var todayPosts: Int = 0
        var totalPosts: Int = 0
    }

    /// 공지 (운영자 발송 — 노출 기간 동안 하단 시트로 표시).
    struct Announcement: Codable, Identifiable {
        let id: String
        let body: String
        let startsAt: Date?
        let endsAt: Date?
        let active: Bool
        let createdAt: Date
        enum CodingKeys: String, CodingKey {
            case id, body, active
            case startsAt = "starts_at"
            case endsAt = "ends_at"
            case createdAt = "created_at"
        }
    }

    /// 경고 (운영자 → 특정 사용자).
    struct Warning: Codable, Identifiable {
        let id: String
        let message: String
        let createdAt: Date
        enum CodingKeys: String, CodingKey { case id; case message; case createdAt = "created_at" }
    }

    /// 인앱 활동 알림(컬렉션 종 배지) — 내 글 좋아요 · 새 팔로워. 댓글 미구현이라 제외.
    struct Notice: Identifiable {
        enum Kind { case like, follow }
        let id: String
        let kind: Kind
        let postImagePath: String?
        let createdAt: Date
    }

    /// 신고 사유 — UGC 의무(Guideline 1.2).
    enum ReportReason: String, Codable, CaseIterable {
        case inappropriate   // 부적절/선정적
        case spam            // 스팸/광고
        case offensive       // 욕설/혐오
        case copyright       // 저작권/타인 사진
        case trade           // 거래/판매 유도 (거래 금지 정책)
        case scam            // 거래 사기 의심
        case other

        /// l10n 키 (Localizable.strings). 인라인 문자열 금지(Hard Rule #3).
        var localizationKey: String {
            switch self {
            case .inappropriate: return "community.report.inappropriate"
            case .spam:          return "community.report.spam"
            case .offensive:     return "community.report.offensive"
            case .copyright:     return "community.report.copyright"
            case .trade:         return "community.report.trade"
            case .scam:          return "community.report.scam"
            case .other:         return "community.report.other"
            }
        }
    }
}
