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
        XCTAssertEqual(suggestion?.movement.id, "ETA_2824-2")
    }

    func test_match_tudor_black_bay_58_returns_mt5602() {
        let matcher = MovementMatcher(database: db)
        let suggestion = matcher.suggest(brand: "Tudor", model: "Black Bay 58")
        XCTAssertEqual(suggestion?.movement.id, "Tudor_MT5602")
    }

    func test_match_rolex_submariner_returns_3135() {
        let matcher = MovementMatcher(database: db)
        let suggestion = matcher.suggest(brand: "Rolex", model: "Submariner")
        XCTAssertEqual(suggestion?.movement.id, "Rolex_3135")
    }

    func test_match_unknown_brand_returns_nil() {
        let matcher = MovementMatcher(database: db)
        XCTAssertNil(matcher.suggest(brand: "Unknown", model: "Mystery Watch 9999"))
    }

    func test_match_empty_inputs_returns_nil() {
        let matcher = MovementMatcher(database: db)
        XCTAssertNil(matcher.suggest(brand: "", model: ""))
        XCTAssertNil(matcher.suggest(brand: "   ", model: "   "))
    }
}
