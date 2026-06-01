import XCTest
@testable import WatchAccuracyPro

/// 커뮤니티 DTO Codable 디코딩 — PostgREST snake_case 매핑·옵셔널·날짜 전략 검증.
/// CommunityService.decoder 가 @MainActor 정적 → 테스트도 MainActor.
@MainActor
final class CommunityModelDecodeTests: XCTestCase {
    private var decoder: JSONDecoder { CommunityService.decoder }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(type, from: Data(json.utf8))
    }

    func test_post_full() throws {
        let p = try decode(Community.Post.self, """
        {"id":"p1","author_uid":"u1","image_path":"img/p1.jpg","brand":"Rolex",
         "caption":"hello","author_name":"Alice","author_avatar_path":"a/u1.jpg",
         "like_count":5,"comment_count":3,"status":"approved","created_at":"2026-06-01T12:00:00Z"}
        """)
        XCTAssertEqual(p.id, "p1")
        XCTAssertEqual(p.authorUID, "u1")
        XCTAssertEqual(p.imagePath, "img/p1.jpg")
        XCTAssertEqual(p.brand, "Rolex")
        XCTAssertEqual(p.caption, "hello")
        XCTAssertEqual(p.authorName, "Alice")
        XCTAssertEqual(p.likeCount, 5)
        XCTAssertEqual(p.commentCount, 3)
        XCTAssertEqual(p.status, .approved)
        XCTAssertGreaterThan(p.createdAt.timeIntervalSince1970, 0)
    }

    func test_post_minimal_optionals_absent() throws {
        let p = try decode(Community.Post.self, """
        {"id":"p2","author_uid":"u2","image_path":"x.jpg","like_count":0,
         "status":"hidden","created_at":"2026-06-01T12:00:00.123Z"}
        """)
        XCTAssertNil(p.brand)
        XCTAssertNil(p.caption)
        XCTAssertNil(p.authorName)
        XCTAssertNil(p.commentCount)
        XCTAssertEqual(p.status, .hidden)
    }

    func test_post_isMine() throws {
        let p = try decode(Community.Post.self, """
        {"id":"p","author_uid":"me","image_path":"x","like_count":0,"status":"approved","created_at":"2026-06-01T00:00:00Z"}
        """)
        XCTAssertTrue(p.isMine(currentUID: "me"))
        XCTAssertFalse(p.isMine(currentUID: "other"))
        XCTAssertFalse(p.isMine(currentUID: nil))
    }

    func test_comment() throws {
        let c = try decode(Community.Comment.self, """
        {"id":"c1","post_id":"p1","uid":"u2","author_name":"Bob","body":"nice","created_at":"2026-06-01T00:00:00Z"}
        """)
        XCTAssertEqual(c.id, "c1")
        XCTAssertEqual(c.postID, "p1")
        XCTAssertEqual(c.uid, "u2")
        XCTAssertEqual(c.authorName, "Bob")
        XCTAssertEqual(c.body, "nice")
        XCTAssertTrue(c.isMine("u2"))
        XCTAssertFalse(c.isMine("z"))
        XCTAssertFalse(c.isMine(nil))
    }

    func test_liker() throws {
        let l = try decode(Community.Liker.self, """
        {"uid":"u3","author_name":"Carol"}
        """)
        XCTAssertEqual(l.uid, "u3")
        XCTAssertEqual(l.id, "u3")
        XCTAssertEqual(l.authorName, "Carol")
        let anon = try decode(Community.Liker.self, #"{"uid":"u4"}"#)
        XCTAssertNil(anon.authorName)
    }

    func test_curated_channel() throws {
        let ch = try decode(Community.CuratedChannel.self, """
        {"id":"ch1","channel_id":"UCabc","title":"Watch TV","thumbnail_url":"t.jpg",
         "locale":"en","category":"review","sort_order":2,"active":true}
        """)
        XCTAssertEqual(ch.channelID, "UCabc")
        XCTAssertEqual(ch.title, "Watch TV")
        XCTAssertEqual(ch.locale, "en")
        XCTAssertEqual(ch.sortOrder, 2)
        XCTAssertTrue(ch.active)
        XCTAssertEqual(ch.id, "ch1")
    }

    func test_channel_suggestion() throws {
        let s = try decode(Community.ChannelSuggestion.self, """
        {"id":"s1","url":"https://youtube.com/@x","created_at":"2026-06-01T00:00:00Z"}
        """)
        XCTAssertEqual(s.url, "https://youtube.com/@x")
        XCTAssertNil(s.note)
    }

    func test_announcement_and_warning() throws {
        let a = try decode(Community.Announcement.self, """
        {"id":"a1","body":"hello","active":true,"created_at":"2026-06-01T00:00:00Z"}
        """)
        XCTAssertEqual(a.body, "hello")
        XCTAssertTrue(a.active)
        XCTAssertNil(a.startsAt)

        let w = try decode(Community.Warning.self, """
        {"id":"w1","message":"warn","created_at":"2026-06-01T00:00:00Z"}
        """)
        XCTAssertEqual(w.message, "warn")
    }

    func test_report_reason_cases() {
        XCTAssertEqual(Community.ReportReason.trade.rawValue, "trade")
        XCTAssertEqual(Community.ReportReason.scam.rawValue, "scam")
        XCTAssertTrue(Community.ReportReason.allCases.contains(.trade))
        XCTAssertTrue(Community.ReportReason.allCases.contains(.scam))
        for r in Community.ReportReason.allCases {
            XCTAssertFalse(r.localizationKey.isEmpty)
        }
    }
}
