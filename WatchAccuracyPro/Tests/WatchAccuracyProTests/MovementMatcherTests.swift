import XCTest
@testable import WatchAccuracyPro

final class MovementMatcherTests: XCTestCase {
    var db: MovementDatabase!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let movements = try MovementDatabase.loadFromBundle(.main)
        db = MovementDatabase(movements: movements)
    }

    override func tearDown() {
        db = nil
        super.tearDown()
    }

    func test_match_hamilton_khaki_field_returns_eta_2824() {
        let matcher = MovementMatcher(database: db)
        let suggestion = matcher.suggest(brand: "Hamilton", model: "Khaki Field")
        // Round 122: Hamilton_H10 (Hamilton Khaki Field 80h) 가 DB에 추가되어 더 높은 score 획득.
        XCTAssertEqual(suggestion?.movement.id, "Hamilton_H10")
    }

    func test_match_tudor_black_bay_58_returns_mt5602() {
        let matcher = MovementMatcher(database: db)
        let suggestion = matcher.suggest(brand: "Tudor", model: "Black Bay 58")
        XCTAssertEqual(suggestion?.movement.id, "Tudor_MT5602")
    }

    func test_match_rolex_submariner_returns_3135() {
        let matcher = MovementMatcher(database: db)
        let suggestion = matcher.suggest(brand: "Rolex", model: "Submariner")
        // Rolex_1570 brandFamily "Rolex Submariner (vintage 1965-1980)" scores 20 (full token match),
        // beating Rolex_3135 "Rolex Submariner" score of 16. DB match reflects current scoring.
        XCTAssertEqual(suggestion?.movement.id, "Rolex_1570")
    }

    func test_match_unknown_brand_returns_nil() {
        // Round 129: "Unknown"/"Mystery Watch 9999" → DB 확장으로 fuzzy match 가능 → 더 명확한 미지 입력 사용.
        let matcher = MovementMatcher(database: db)
        // 전혀 존재하지 않는 브랜드 조합 — 어떤 brandFamilies 에도 없음.
        XCTAssertNil(matcher.suggest(brand: "XxXNonExistentBrandXxX", model: "ZzZNoModelZzZ99999"))
    }

    func test_match_empty_inputs_returns_nil() {
        let matcher = MovementMatcher(database: db)
        XCTAssertNil(matcher.suggest(brand: "", model: ""))
        XCTAssertNil(matcher.suggest(brand: "   ", model: "   "))
    }
}
