import XCTest
@testable import WatchAccuracyPro

/// 커뮤니티 텍스트 검열 — 거래금지/연락처/전화번호/욕설/길이. 순수 함수.
final class CommunityModerationTests: XCTestCase {

    // MARK: - screen()
    func test_screen_empty_is_allowed() {
        XCTAssertEqual(CommunityTextModerator.screen("   "), .allowed)
    }

    func test_screen_normal_is_allowed() {
        XCTAssertEqual(CommunityTextModerator.screen("오늘 손목 위 IWC 포르투기저"), .allowed)
    }

    func test_screen_too_long() {
        let long = String(repeating: "가", count: 61)   // maxLength 60 초과
        XCTAssertEqual(CommunityTextModerator.screen(long), .tooLong)
    }

    func test_screen_trade_keyword_is_tradeBan() {
        XCTAssertEqual(CommunityTextModerator.screen("이거 팝니다 싸게"), .tradeBan)
        XCTAssertEqual(CommunityTextModerator.screen("급하게 삽니다"), .tradeBan)
        XCTAssertEqual(CommunityTextModerator.screen("직거래 가능"), .tradeBan)
    }

    func test_screen_profane_is_profane() {
        XCTAssertEqual(CommunityTextModerator.screen("this is fuck"), .profane)
    }

    // MARK: - containsTradeIntent
    func test_trade_intent_keywords() {
        XCTAssertTrue(CommunityTextModerator.containsTradeIntent("매매 원합니다"))
        XCTAssertTrue(CommunityTextModerator.containsTradeIntent("양도해요"))
    }

    func test_trade_intent_contact() {
        XCTAssertTrue(CommunityTextModerator.containsTradeIntent("카톡 주세요"))
        XCTAssertTrue(CommunityTextModerator.containsTradeIntent("연락처 남겨요"))
    }

    func test_trade_intent_phone_number() {
        XCTAssertTrue(CommunityTextModerator.containsTradeIntent("010-1234-5678 로 연락"))
        XCTAssertTrue(CommunityTextModerator.containsTradeIntent("01012345678"))
    }

    func test_trade_intent_false_for_plain_comment() {
        XCTAssertFalse(CommunityTextModerator.containsTradeIntent("이 시계 정말 멋지네요"))
        // 단순 가격 언급은 통과(보수적 정책).
        XCTAssertFalse(CommunityTextModerator.containsTradeIntent("정가 800만원짜리"))
    }

    // MARK: - containsProfanity (정규화 우회 완화 포함)
    func test_profanity_basic() {
        XCTAssertTrue(CommunityTextModerator.containsProfanity("FUCK you"))
        XCTAssertFalse(CommunityTextModerator.containsProfanity("좋은 하루"))
    }

    func test_profanity_normalizes_separators() {
        // 공백/기호 삽입 우회 — normalize 가 영숫자·한글 외 제거.
        XCTAssertTrue(CommunityTextModerator.containsProfanity("f.u.c.k"))
    }
}
