import XCTest
@testable import WatchAccuracyPro

/// `BadgeCatalog` 카탈로그 정합성 + `name(forBadge:)` 조회 로직 회귀 보호.
/// 네트워크/시스템 의존 없음 — 순수 딕셔너리/문자열 산술.
final class BadgeCatalogTests: XCTestCase {

    // MARK: - emojiToID 딕셔너리 정합성

    func test_emojiToID_is_not_empty() {
        XCTAssertFalse(BadgeCatalog.emojiToID.isEmpty, "카탈로그에 최소 1개 이상의 뱃지가 있어야 함")
    }

    func test_all_emoji_keys_are_unique() {
        // 딕셔너리 키는 구조상 고유하지만, 실수로 중복 리터럴이 들어가면
        // Swift 컴파일러가 마지막 값으로 조용히 덮어쓴다. Set 크기로 교차 검증.
        let keys = Array(BadgeCatalog.emojiToID.keys)
        let uniqueKeys = Set(keys)
        XCTAssertEqual(uniqueKeys.count, keys.count,
                       "이모지 키 중복 발생 — 딕셔너리 리터럴 내 덮어쓰기 주의")
    }

    func test_all_badge_ids_are_unique() {
        // 두 이모지가 같은 id 에 매핑되면 이름 조회가 모호해진다.
        let ids = Array(BadgeCatalog.emojiToID.values)
        let uniqueIds = Set(ids)
        XCTAssertEqual(uniqueIds.count, ids.count,
                       "뱃지 ID 중복: \(ids.filter { id in ids.filter { $0 == id }.count > 1 })")
    }

    func test_all_badge_ids_have_b_prefix() {
        // 컨벤션: 모든 id 는 "b" 로 시작하는 문자열
        for (emoji, id) in BadgeCatalog.emojiToID {
            XCTAssertTrue(id.hasPrefix("b"), "이모지 \(emoji) 의 id '\(id)' 가 'b' 접두어 없음")
        }
    }

    func test_all_badge_ids_have_numeric_suffix() {
        // "b" 이후는 숫자여야 한다 (예: "b34" → 34는 Int 변환 가능)
        for (emoji, id) in BadgeCatalog.emojiToID {
            let suffix = id.dropFirst()
            XCTAssertNotNil(Int(suffix),
                            "이모지 \(emoji) 의 id '\(id)' 숫자 접미어 없음, suffix='\(suffix)'")
        }
    }

    // MARK: - name(forBadge:) — 미등록 이모지

    func test_name_returns_nil_for_unknown_emoji() {
        // "🚀" 는 카탈로그에 없으므로 nil
        XCTAssertNil(BadgeCatalog.name(forBadge: "🚀"))
    }

    func test_name_returns_nil_for_empty_string() {
        XCTAssertNil(BadgeCatalog.name(forBadge: ""))
    }

    func test_name_returns_nil_for_plain_text() {
        XCTAssertNil(BadgeCatalog.name(forBadge: "hello"))
    }

    func test_name_returns_nil_for_emoji_not_in_catalog() {
        // 카탈로그에 없는 다른 이모지들도 nil 반환해야 함
        let notInCatalog = ["🦄", "🐉", "🌈", "💎", "🎃"]
        for emoji in notInCatalog {
            XCTAssertNil(BadgeCatalog.name(forBadge: emoji),
                         "'\(emoji)' 는 카탈로그에 없으므로 nil 이어야 함")
        }
    }

    // MARK: - name(forBadge:) — 등록된 이모지

    func test_name_returns_non_nil_for_known_emoji() {
        // 카탈로그의 모든 이모지에 대해 non-nil 반환 검증
        for (emoji, _) in BadgeCatalog.emojiToID {
            let result = BadgeCatalog.name(forBadge: emoji)
            XCTAssertNotNil(result, "등록된 이모지 '\(emoji)' 가 nil 을 반환함")
        }
    }

    func test_name_for_b34_returns_localized_key_lookup() {
        // "👍" → id "b34" → NSLocalizedString("badges.b34.name")
        // 테스트 번들에 strings 파일이 없으면 키 자체가 반환된다(NSLocalizedString 폴백).
        // 어느 경우든 nil 이 아니어야 하고, 예상 NSLocalizedString 결과와 일치해야 한다.
        let emoji = "👍"
        guard let id = BadgeCatalog.emojiToID[emoji] else {
            XCTFail("'👍' 가 emojiToID 에 없음 — 카탈로그 갱신 필요")
            return
        }
        let expected = NSLocalizedString("badges.\(id).name", comment: "")
        let result = BadgeCatalog.name(forBadge: emoji)
        XCTAssertNotNil(result)
        XCTAssertEqual(result, expected)
    }

    func test_name_for_verified_emoji_returns_localized_result() {
        // "🔥" → id "b35"
        let emoji = "🔥"
        guard let id = BadgeCatalog.emojiToID[emoji] else {
            XCTFail("'🔥' 가 emojiToID 에 없음")
            return
        }
        let expected = NSLocalizedString("badges.\(id).name", comment: "")
        XCTAssertEqual(BadgeCatalog.name(forBadge: emoji), expected)
    }

    func test_name_all_known_emojis_match_localized_lookup() {
        // 모든 등록 이모지의 name 이 NSLocalizedString("badges.{id}.name") 과 동일해야 한다.
        for (emoji, id) in BadgeCatalog.emojiToID {
            let expected = NSLocalizedString("badges.\(id).name", comment: "")
            let actual   = BadgeCatalog.name(forBadge: emoji)
            XCTAssertEqual(actual, expected,
                           "이모지 '\(emoji)' (id=\(id)) 의 name 이 예상 localized key 와 불일치")
        }
    }

    // MARK: - catalog 규모 회귀 (추가/삭제 감지)

    func test_catalog_has_expected_minimum_count() {
        // 2026-06-02 기준 29개 확인. 향후 뱃지 추가 시 이 값을 올려준다.
        XCTAssertGreaterThanOrEqual(BadgeCatalog.emojiToID.count, 29,
                                    "뱃지 삭제 회귀 — 29개 이상이어야 함")
    }
}
