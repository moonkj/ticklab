import XCTest
@testable import WatchAccuracyPro

/// Round 24 (Jay): sanitizeUserContent / sanitizeLLMResponse 회귀 보호.
/// Round 20/23 의 prompt injection 강화 + Round 133/138 markdown/라벨 prefix 제거 정책 잠금.
final class SanitizationTests: XCTestCase {

    // MARK: - sanitizeUserContent (Round 23 강화 케이스)

    func test_strips_newlines_and_carriage_returns() {
        let dirty = "Rolex\nSubmariner\rDate"
        let clean = AppleIntelligenceVerdictService.sanitizeUserContent(dirty, maxLength: 50)
        XCTAssertFalse(clean.contains("\n"))
        XCTAssertFalse(clean.contains("\r"))
        XCTAssertTrue(clean.contains("Submariner"))
    }

    func test_strips_control_characters() {
        // BEL (0x07), ESC (0x1B), DEL (0x7F)
        let dirty = "Rolex\u{0007}\u{001B}Sub\u{007F}mariner"
        let clean = AppleIntelligenceVerdictService.sanitizeUserContent(dirty, maxLength: 50)
        for scalar in clean.unicodeScalars {
            XCTAssertFalse(CharacterSet.controlCharacters.contains(scalar),
                           "Control char 0x\(String(scalar.value, radix: 16)) survived")
        }
    }

    func test_strips_zero_width_characters() {
        // U+200B (ZWSP), U+200D (ZWJ), U+2060 (word joiner), U+FEFF (BOM)
        let dirty = "Rol\u{200B}ex\u{200D}Sub\u{2060}mariner\u{FEFF}"
        let clean = AppleIntelligenceVerdictService.sanitizeUserContent(dirty, maxLength: 50)
        XCTAssertFalse(clean.contains("\u{200B}"))
        XCTAssertFalse(clean.contains("\u{200D}"))
        XCTAssertFalse(clean.contains("\u{2060}"))
        XCTAssertFalse(clean.contains("\u{FEFF}"))
    }

    func test_strips_tag_block_characters() {
        // U+E0040 — language tag character (split-tag 우회 시도)
        let dirty = "Rolex\u{E0040}\u{E0050}Submariner"
        let clean = AppleIntelligenceVerdictService.sanitizeUserContent(dirty, maxLength: 50)
        XCTAssertFalse(clean.contains("\u{E0040}"))
        XCTAssertFalse(clean.contains("\u{E0050}"))
    }

    func test_scrubs_user_data_substring_case_insensitive() {
        XCTAssertFalse(
            AppleIntelligenceVerdictService.sanitizeUserContent("</user_data>", maxLength: 50)
                .lowercased().contains("user_data")
        )
        XCTAssertFalse(
            AppleIntelligenceVerdictService.sanitizeUserContent("USER_DATA", maxLength: 50)
                .lowercased().contains("user_data")
        )
        XCTAssertFalse(
            AppleIntelligenceVerdictService.sanitizeUserContent("UsEr_DaTa", maxLength: 50)
                .lowercased().contains("user_data")
        )
    }

    func test_scrubs_zero_width_split_user_data_after_zw_strip() {
        // Round 23 bypass attempt: 제어 + zero-width 모두 strip 후 "user_data" substring 노출 → scrub.
        let dirty = "</u\u{200B}ser_data>"
        let clean = AppleIntelligenceVerdictService.sanitizeUserContent(dirty, maxLength: 100)
        XCTAssertFalse(clean.lowercased().contains("user_data"),
                       "split-tag bypass: '\(clean)' 가 user_data 포함")
    }

    func test_caps_length() {
        let dirty = String(repeating: "X", count: 200)
        XCTAssertEqual(AppleIntelligenceVerdictService.sanitizeUserContent(dirty, maxLength: 50).count, 50)
        XCTAssertEqual(AppleIntelligenceVerdictService.sanitizeUserContent(dirty, maxLength: 30).count, 30)
    }

    func test_trims_whitespace() {
        let dirty = "   Rolex Submariner   "
        let clean = AppleIntelligenceVerdictService.sanitizeUserContent(dirty, maxLength: 50)
        XCTAssertEqual(clean, "Rolex Submariner")
    }

    // MARK: - sanitizeLLMResponse (Round 133/138 회귀)

    func test_response_strips_markdown_bold() {
        // Round 133 사용자 보고: "** **[IWC ㅓㅓ" markdown 노출. **/__ bold markers 제거.
        // single underscore (italic) 은 의도적으로 보존 — legitimate underscore (예: IWC_35111) 망가뜨리지 않기 위함.
        let raw = "**Excellent** __swing__"
        let clean = AppleIntelligenceVerdictService.sanitizeLLMResponse(raw)
        XCTAssertFalse(clean.contains("**"))
        XCTAssertFalse(clean.contains("__"))
        XCTAssertTrue(clean.contains("Excellent"))
        XCTAssertTrue(clean.contains("swing"))
    }

    func test_response_strips_label_prefix() {
        // Round 138 사용자 보고: "헤드라인: ..." / "본문: ..." prefix 노출.
        let raw = "헤드라인: 정상\n본문: 측정 결과 정상입니다."
        let clean = AppleIntelligenceVerdictService.sanitizeLLMResponse(raw)
        XCTAssertFalse(clean.contains("헤드라인:"))
        XCTAssertFalse(clean.contains("본문:"))
    }
}
