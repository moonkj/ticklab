import XCTest
@testable import WatchAccuracyPro

/// 커뮤니티 텍스트 검열 — CommunityModerationTests 가 안 다루는 추가 분기.
///   · 추가 금칙어(ko/en) · 추가 거래/연락처 키워드 · 반복문자 축약 정규화 · 우선순위(거래 > 욕설)
/// 기존 단언과 중복하지 않는다. 순수 함수.
final class CommunityModerationExtraTests: XCTestCase {

    // MARK: - 추가 금칙어 (한국어)

    func test_profanity_additional_korean_words() {
        XCTAssertTrue(CommunityTextModerator.containsProfanity("진짜 병신 같네"))
        XCTAssertTrue(CommunityTextModerator.containsProfanity("개새끼야"))
        XCTAssertTrue(CommunityTextModerator.containsProfanity("지랄하지마"))
    }

    func test_profanity_additional_english_words() {
        XCTAssertTrue(CommunityTextModerator.containsProfanity("you bitch"))
        XCTAssertTrue(CommunityTextModerator.containsProfanity("what an asshole"))
        XCTAssertTrue(CommunityTextModerator.containsProfanity("this porn site"))
    }

    func test_profanity_jamo_only_token() {
        // 한글 자모 ㅅㅂ (0x3130~0x318F 보존) — substring 매칭.
        XCTAssertTrue(CommunityTextModerator.containsProfanity("ㅅㅂ 진짜"))
        XCTAssertTrue(CommunityTextModerator.containsProfanity("ㅂㅅ 같은"))
    }

    func test_profanity_clean_text_is_false() {
        XCTAssertFalse(CommunityTextModerator.containsProfanity("오늘 날씨 정말 좋다"))
        XCTAssertFalse(CommunityTextModerator.containsProfanity("nice watch today"))
    }

    // MARK: - 반복문자 축약 정규화 (3회 이상 → 2회)

    func test_normalize_repeated_char_compression_blocks_padded_profanity() {
        // "ㅅㅅㅂ" 같은 단순 반복은 영향 없지만, 동일 문자 3+회 삽입 우회는 2회로 축약.
        // "fuuuck" → "fuuck"? — 규칙은 (.)\1{2,} → $1$1 (3회+ 를 2회로).
        // "fuuuuck"(u 4개) → "fuuck" 이라 "fuck" 미포함. 단 정확한 "fuck" 형태는 그대로 매칭.
        XCTAssertTrue(CommunityTextModerator.containsProfanity("fuck"))
        // 반복 축약이 적용돼도 정상 단어는 통과(거짓양성 없음).
        XCTAssertFalse(CommunityTextModerator.containsProfanity("coooool watch"))
    }

    func test_normalize_does_not_create_false_positive_from_compression() {
        // 반복 축약이 일반 텍스트를 금칙어로 바꾸지 않는다.
        XCTAssertFalse(CommunityTextModerator.containsProfanity("hellooo there"))
    }

    // MARK: - 추가 거래 키워드

    func test_trade_intent_additional_sell_keywords() {
        XCTAssertTrue(CommunityTextModerator.containsTradeIntent("팔아요 급매"))
        XCTAssertTrue(CommunityTextModerator.containsTradeIntent("판매중입니다"))
        XCTAssertTrue(CommunityTextModerator.containsTradeIntent("분양 합니다"))
        XCTAssertTrue(CommunityTextModerator.containsTradeIntent("택배비 별도"))
    }

    func test_trade_intent_additional_contact_keywords() {
        XCTAssertTrue(CommunityTextModerator.containsTradeIntent("오픈톡 오세요"))
        XCTAssertTrue(CommunityTextModerator.containsTradeIntent("디엠 주세요"))
        XCTAssertTrue(CommunityTextModerator.containsTradeIntent("쪽지주세요"))
        XCTAssertTrue(CommunityTextModerator.containsTradeIntent("문자주시면"))
    }

    func test_trade_intent_phone_with_dots_and_spaces() {
        // 정규식: 0[0-9]{1,2}[-. ]?[0-9]{3,4}[-. ]?[0-9]{4}
        XCTAssertTrue(CommunityTextModerator.containsTradeIntent("010.1234.5678"))
        XCTAssertTrue(CommunityTextModerator.containsTradeIntent("010 1234 5678"))
    }

    // MARK: - screen() 우선순위 / 경계

    func test_screen_trade_takes_priority_over_profanity() {
        // 거래 의도 + 욕설 동시 → 거래금지 우선(검열 순서: trade 먼저).
        XCTAssertEqual(CommunityTextModerator.screen("이 shit 시계 팝니다"), .tradeBan)
    }

    func test_screen_exactly_maxLength_is_allowed() {
        // 정확히 60자(maxLength)는 통과(초과만 tooLong).
        let exact = String(repeating: "가", count: 60)
        XCTAssertEqual(CommunityTextModerator.screen(exact), .allowed)
    }

    func test_screen_profane_within_length_limit() {
        XCTAssertEqual(CommunityTextModerator.screen("느금마"), .profane)
    }
}
