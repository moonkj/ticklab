import XCTest
@testable import WatchAccuracyPro

/// WatchModelSuggestionService — 완전 온디바이스·순수 결정적 자동완성 로직.
final class WatchModelSuggestionServiceTests: XCTestCase {

    // MARK: - models(for:)

    func test_models_for_known_brand_nonEmpty() {
        let rolex = WatchModelSuggestionService.models(for: "Rolex")
        XCTAssertFalse(rolex.isEmpty)
        XCTAssertTrue(rolex.contains("Submariner"))
        XCTAssertTrue(rolex.contains("Daytona"))
    }

    func test_models_for_unknown_brand_empty() {
        XCTAssertTrue(WatchModelSuggestionService.models(for: "Nonexistent Brand").isEmpty)
    }

    func test_models_for_is_case_sensitive_on_brand_key() {
        // modelDB 키는 정확한 케이스. 소문자는 매칭 안 됨.
        XCTAssertTrue(WatchModelSuggestionService.models(for: "rolex").isEmpty)
    }

    // MARK: - suggestions(brand:partialModel:)

    func test_suggestions_empty_partial_returns_all_models() {
        let all = WatchModelSuggestionService.models(for: "Omega")
        let suggested = WatchModelSuggestionService.suggestions(brand: "Omega", partialModel: "")
        XCTAssertEqual(suggested, all)
    }

    func test_suggestions_filters_case_insensitively() {
        let result = WatchModelSuggestionService.suggestions(brand: "Rolex", partialModel: "sub")
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.allSatisfy { $0.lowercased().contains("sub") })
        XCTAssertTrue(result.contains("Submariner"))
    }

    func test_suggestions_no_match_returns_empty() {
        let result = WatchModelSuggestionService.suggestions(brand: "Rolex", partialModel: "zzzzz")
        XCTAssertTrue(result.isEmpty)
    }

    func test_suggestions_unknown_brand_returns_empty() {
        XCTAssertTrue(
            WatchModelSuggestionService.suggestions(brand: "Bogus", partialModel: "a").isEmpty
        )
    }

    // MARK: - globalSearch(_:)

    func test_globalSearch_empty_query_returns_empty() {
        XCTAssertTrue(WatchModelSuggestionService.globalSearch("").isEmpty)
    }

    func test_globalSearch_by_brand_name_matches_models() {
        let results = WatchModelSuggestionService.globalSearch("Rolex")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.brand == "Rolex" })
        // 브랜드 매칭 시 brand 당 최대 3개.
        XCTAssertLessThanOrEqual(results.count, 3)
    }

    func test_globalSearch_by_model_name_matches_across_brands() {
        let results = WatchModelSuggestionService.globalSearch("Submariner")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { $0.brand == "Rolex" && $0.model.contains("Submariner") })
    }

    func test_globalSearch_caps_results_at_ten() {
        // 매우 흔한 substring("a") 으로 상한 검증.
        let results = WatchModelSuggestionService.globalSearch("a")
        XCTAssertLessThanOrEqual(results.count, 10)
    }

    func test_globalSearch_is_case_insensitive() {
        let lower = WatchModelSuggestionService.globalSearch("rolex")
        XCTAssertFalse(lower.isEmpty)
        XCTAssertTrue(lower.allSatisfy { $0.brand == "Rolex" })
    }
}
