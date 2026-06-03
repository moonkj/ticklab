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
        /// Storage 'community' 경로. **글-전용 게시(사진 없음)면 nil** (Round 171).
        let imagePath: String?
        let brand: String?
        let caption: String?        // 짧은 한 줄 멘트(선택) — 온디바이스 텍스트 검열 통과분만
        let authorName: String?     // 공개 프로필 표시명(신원 전환). nil = 구 익명 글
        let authorAvatarPath: String?
        /// Round 171: 작성자가 닉네임 옆에 장착한 뱃지 이모지(선택). nil = 미장착.
        let authorBadge: String?
        /// Round 174: 작성자 대표 시계 메이커(프로필 좋아하는 브랜드 1순위). 아바타 하단 칩. nil = 미설정/구글.
        let authorRepBrand: String?
        var likeCount: Int
        var commentCount: Int?      // 비정규화(트리거). 미배포 시 nil → 0 처리.
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
            case authorBadge = "author_badge"
            case authorRepBrand = "author_rep_brand"
            case likeCount = "like_count"
            case commentCount = "comment_count"
            case status
            case createdAt = "created_at"
        }

        /// 현재 익명 사용자(uid)가 작성자인가 — 본인 글은 게이팅/검열 예외.
        func isMine(currentUID: String?) -> Bool {
            guard let currentUID else { return false }
            return authorUID == currentUID
        }
    }

    /// Round 172: 커뮤니티 배지용 내 활동 통계.
    struct MyStats: Equatable {
        let postCount: Int          // 내가 올린 글 수
        let likesReceived: Int      // 내 글이 받은 좋아요 합
        let commentsReceived: Int   // 내 글에 달린 댓글 합
        var followerCount: Int = 0  // 나를 팔로우한 사람 수(community_follows)
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

    /// 좋아요 라이커(인스타 "누가 좋아요"). 익명 닉네임 표시 + 팔로우용 uid.
    struct Liker: Codable, Identifiable, Hashable {
        let uid: String
        let authorName: String?
        var id: String { uid }
        enum CodingKeys: String, CodingKey { case uid; case authorName = "author_name" }
    }

    /// 커뮤니티 댓글.
    struct Comment: Codable, Identifiable {
        let id: String
        let postID: String
        let uid: String
        let authorName: String?
        let body: String
        let createdAt: Date
        enum CodingKeys: String, CodingKey {
            case id, uid, body
            case postID = "post_id"
            case authorName = "author_name"
            case createdAt = "created_at"
        }
        func isMine(_ myUID: String?) -> Bool { myUID != nil && uid == myUID }
    }

    /// 사용자 채널 제안(영상 피드) — 사용자가 추천 채널 주소를 운영자에게. 운영자만 조회.
    struct ChannelSuggestion: Codable, Identifiable {
        let id: String
        let url: String
        let note: String?
        let createdAt: Date
        enum CodingKeys: String, CodingKey { case id, url, note; case createdAt = "created_at" }
    }

    /// 인앱 피드백 — 사용자가 설정>피드백에서 보낸 의견(버그/제안/일반). 운영자만 조회.
    /// (Round 175) 기존 mailto 대신 Supabase 로 수집 → 운영 대시보드에서 확인.
    struct Feedback: Codable, Identifiable {
        let id: String
        let type: String        // "bug" | "suggestion" | "general"
        let message: String
        let appVersion: String?
        let createdAt: Date
        enum CodingKeys: String, CodingKey {
            case id, type, message
            case appVersion = "app_version"
            case createdAt = "created_at"
        }
    }

    /// 운영자 큐레이션 YouTube 채널(영상 피드). 언어별. RSS는 channelId 로 앱이 직접 읽음.
    struct CuratedChannel: Codable, Identifiable {
        let id: String
        let channelID: String
        let title: String
        let thumbnailURL: String?
        let locale: String
        let category: String?
        let sortOrder: Int
        let active: Bool
        enum CodingKeys: String, CodingKey {
            case id, title, locale, category, active
            case channelID = "channel_id"
            case thumbnailURL = "thumbnail_url"
            case sortOrder = "sort_order"
        }
    }

    /// Edge Function(youtube-videos)이 반환하는 큐레이션 영상 한 건.
    /// YouTube 공개 RSS 차단(2026-06-03) → Data API + 서버캐시 경유로 전환.
    struct CuratedVideo: Codable, Identifiable {
        let id: String              // videoId
        let title: String
        let channelTitle: String
        let publishedAt: Date
        let locale: String?
        enum CodingKeys: String, CodingKey {
            case id, title, locale
            case channelTitle = "channel_title"
            case publishedAt = "published_at"
        }
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
