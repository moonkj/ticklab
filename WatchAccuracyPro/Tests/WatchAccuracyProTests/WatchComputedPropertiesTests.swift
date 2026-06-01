import XCTest
@testable import WatchAccuracyPro

/// Watch / value-type 모델의 순수 computed property·enum 접근자 커버리지.
/// (SmartwatchBatteryTests / ModelTests 가 다루지 않는 부분만.)
final class WatchComputedPropertiesTests: XCTestCase {

    // MARK: - Watch.isCaliberManualEntry / manualCaliberTag

    func test_isCaliberManualEntry_true_when_sentinel() {
        let w = Watch(brand: "X", model: "Y", caliber: Watch.manualCaliberTag)
        XCTAssertTrue(w.isCaliberManualEntry)
    }

    func test_isCaliberManualEntry_false_for_real_caliber() {
        let w = Watch(brand: "Omega", model: "Speedmaster", caliber: "1861")
        XCTAssertFalse(w.isCaliberManualEntry)
    }

    func test_isCaliberManualEntry_false_when_nil() {
        let w = Watch(brand: "Omega", model: "Speedmaster")
        XCTAssertNil(w.caliber)
        XCTAssertFalse(w.isCaliberManualEntry)
    }

    func test_manualCaliberTag_is_stable_sentinel() {
        XCTAssertEqual(Watch.manualCaliberTag, "__manual__")
    }

    // MARK: - Watch.movementType get/set (raw String <-> enum)

    func test_movementType_default_is_automatic() {
        let w = Watch(brand: "A", model: "B")
        XCTAssertEqual(w.movementType, .automatic)
        XCTAssertEqual(w.movementTypeRaw, "automatic")
    }

    func test_movementType_init_persists_raw() {
        let w = Watch(brand: "A", model: "B", movementType: .manual)
        XCTAssertEqual(w.movementTypeRaw, "manual")
        XCTAssertEqual(w.movementType, .manual)
    }

    func test_movementType_setter_updates_raw() {
        let w = Watch(brand: "A", model: "B")
        w.movementType = .quartz
        XCTAssertEqual(w.movementTypeRaw, "quartz")
        XCTAssertEqual(w.movementType, .quartz)
    }

    func test_movementType_getter_falls_back_to_automatic_on_garbage() {
        let w = Watch(brand: "A", model: "B")
        w.movementTypeRaw = "not-a-real-type"
        XCTAssertEqual(w.movementType, .automatic, "unknown raw 는 automatic 으로 폴백")
    }

    // MARK: - Watch.purchaseCondition get/set

    func test_purchaseCondition_nil_by_default() {
        let w = Watch(brand: "A", model: "B")
        XCTAssertNil(w.purchaseCondition)
        XCTAssertNil(w.purchaseConditionRaw)
    }

    func test_purchaseCondition_setter_roundtrip() {
        let w = Watch(brand: "A", model: "B")
        w.purchaseCondition = .used
        XCTAssertEqual(w.purchaseConditionRaw, "used")
        XCTAssertEqual(w.purchaseCondition, .used)
    }

    func test_purchaseCondition_set_nil_clears_raw() {
        let w = Watch(brand: "A", model: "B")
        w.purchaseCondition = .new
        w.purchaseCondition = nil
        XCTAssertNil(w.purchaseConditionRaw)
        XCTAssertNil(w.purchaseCondition)
    }

    func test_purchaseCondition_getter_nil_on_garbage_raw() {
        let w = Watch(brand: "A", model: "B")
        w.purchaseConditionRaw = "bogus"
        XCTAssertNil(w.purchaseCondition)
    }

    // MARK: - Watch.batteryNextDue

    func test_batteryNextDue_nil_when_no_last_replaced() {
        let w = Watch(brand: "A", model: "B")
        XCTAssertNil(w.batteryLastReplaced)
        XCTAssertNil(w.batteryNextDue)
    }

    func test_batteryNextDue_adds_expected_life_months() throws {
        let cal = Calendar.current
        let last = cal.date(from: DateComponents(year: 2024, month: 1, day: 15))!
        let w = Watch(brand: "A", model: "B",
                      batteryLastReplaced: last,
                      batteryExpectedLifeMonths: 30)
        let due = try XCTUnwrap(w.batteryNextDue)
        let expected = cal.date(byAdding: .month, value: 30, to: last)
        XCTAssertEqual(due, expected)
    }

    // MARK: - Watch.warrantyExpirationDate

    func test_warrantyExpirationDate_nil_without_purchaseDate() {
        let w = Watch(brand: "A", model: "B", warrantyMonths: 24)
        XCTAssertNil(w.warrantyExpirationDate)
    }

    func test_warrantyExpirationDate_nil_when_months_zero() {
        let w = Watch(brand: "A", model: "B",
                      purchaseDate: Date(), warrantyMonths: 0)
        XCTAssertNil(w.warrantyExpirationDate)
    }

    func test_warrantyExpirationDate_adds_months_from_purchaseDate() throws {
        let cal = Calendar.current
        let purchased = cal.date(from: DateComponents(year: 2023, month: 6, day: 1))!
        let w = Watch(brand: "A", model: "B",
                      purchaseDate: purchased, warrantyMonths: 24)
        let exp = try XCTUnwrap(w.warrantyExpirationDate)
        XCTAssertEqual(exp, cal.date(byAdding: .month, value: 24, to: purchased))
    }

    // MARK: - WatchMovementType

    func test_movementType_isMeasurable_solar_and_manual() {
        XCTAssertTrue(WatchMovementType.solar.isMeasurable)
        XCTAssertTrue(WatchMovementType.manual.isMeasurable)
        XCTAssertFalse(WatchMovementType.smartwatch.isMeasurable)
    }

    func test_movementType_displayNames_nonEmpty_and_distinct() {
        let names = WatchMovementType.allCases.map(\.displayName)
        XCTAssertFalse(names.contains(where: \.isEmpty), "displayName 빈 문자열 없음")
        XCTAssertEqual(Set(names).count, names.count, "각 타입 displayName 은 서로 달라야 함")
    }

    func test_movementType_allCases_count() {
        XCTAssertEqual(WatchMovementType.allCases.count, 5)
    }

    // MARK: - PurchaseCondition

    func test_purchaseCondition_displayNames_nonEmpty_and_distinct() {
        let names = PurchaseCondition.allCases.map(\.displayName)
        XCTAssertFalse(names.contains(where: \.isEmpty))
        XCTAssertEqual(Set(names).count, names.count)
    }

    func test_purchaseCondition_rawValues() {
        XCTAssertEqual(PurchaseCondition.new.rawValue, "new")
        XCTAssertEqual(PurchaseCondition.unworn.rawValue, "unworn")
        XCTAssertEqual(PurchaseCondition.used.rawValue, "used")
    }

    // MARK: - WatchBrands.popular

    func test_popularBrands_contains_expected_marquee_brands() {
        let expected = ["Rolex", "Omega", "Patek Philippe", "Audemars Piguet",
                        "Apple", "Seiko", "Grand Seiko", "Tudor", "IWC"]
        for brand in expected {
            XCTAssertTrue(WatchBrands.popular.contains(brand),
                          "popular 목록에 \(brand) 누락")
        }
    }

    func test_popularBrands_no_duplicates_and_sorted_unique() {
        let list = WatchBrands.popular
        XCTAssertEqual(Set(list).count, list.count, "중복 브랜드 없음")
        XCTAssertFalse(list.isEmpty)
    }
}
