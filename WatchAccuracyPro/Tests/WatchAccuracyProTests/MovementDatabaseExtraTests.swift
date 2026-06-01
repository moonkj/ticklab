import XCTest
@testable import WatchAccuracyPro

/// MovementDatabase — MovementDatabaseTests 가 안 다루는 추가 분기.
///   · movements getter · 중복 id init dedup(first-wins) · brandNames() 정규화/정렬/dedupe
///   · normalizedBrandName 경계(괄호 제거, generic 토큰 제외, 빈 입력)
///   · replaceAll in-place 교체 · 정적 searchBrands · liftAngle fixture 경로
final class MovementDatabaseExtraTests: XCTestCase {

    private func makeMovement(id: String, families: [String],
                              lift: Double = 52.0) -> Movement {
        Movement(id: id, brandFamilies: families, bph: 28_800, liftAngleDegrees: lift,
                 escapement: .swissLever, typicalAmplitudeMin: nil, typicalAmplitudeMax: nil,
                 coscToleranceMin: nil, coscToleranceMax: nil, confidenceLabel: .high)
    }

    // MARK: - init / movements getter

    func test_init_exposes_movements() {
        let db = MovementDatabase(movements: [
            makeMovement(id: "A", families: ["Rolex"]),
            makeMovement(id: "B", families: ["Omega"]),
        ])
        XCTAssertEqual(db.movements.count, 2)
        XCTAssertEqual(Set(db.movements.map(\.id)), ["A", "B"])
    }

    func test_init_empty_yields_no_lookups() {
        let db = MovementDatabase(movements: [])
        XCTAssertTrue(db.movements.isEmpty)
        XCTAssertNil(db.movement(id: "anything"))
        XCTAssertTrue(db.brandNames().isEmpty)
    }

    // MARK: - movement(id:) lookup (hit / miss)

    func test_movement_lookup_hit_and_miss() {
        let db = MovementDatabase(movements: [makeMovement(id: "ETA_2824-2", families: ["Tissot"])])
        XCTAssertNotNil(db.movement(id: "ETA_2824-2"))
        XCTAssertNil(db.movement(id: "Missing_9999"))
    }

    // MARK: - liftAngle fixture (hit / nil)

    func test_liftAngle_fixture_hit_and_miss() {
        let db = MovementDatabase(movements: [makeMovement(id: "Cal_X", families: ["Brand"], lift: 49.0)])
        XCTAssertEqual(db.liftAngle(forCaliber: "Cal_X"), 49.0)
        XCTAssertNil(db.liftAngle(forCaliber: "Cal_Y"))
        XCTAssertNil(db.liftAngle(forCaliber: nil))
    }

    // MARK: - normalizedBrandName 경계

    func test_normalizedBrandName_strips_parenthetical_qualifier() {
        // known brand 매칭이 우선 → "Tudor (vintage)" → "Tudor".
        XCTAssertEqual(MovementDatabase.normalizedBrandName("Tudor (vintage)"), "Tudor")
    }

    func test_normalizedBrandName_unknown_keeps_paren_stripped_name() {
        // known brand 가 아니면 괄호만 제거한 원문 후보.
        XCTAssertEqual(MovementDatabase.normalizedBrandName("Acme Watches (limited)"), "Acme Watches")
    }

    func test_normalizedBrandName_generic_tokens_return_nil() {
        XCTAssertNil(MovementDatabase.normalizedBrandName("microbrand"))
        XCTAssertNil(MovementDatabase.normalizedBrandName("various"))
        XCTAssertNil(MovementDatabase.normalizedBrandName("generic"))
    }

    func test_normalizedBrandName_empty_or_paren_only_returns_nil() {
        XCTAssertNil(MovementDatabase.normalizedBrandName(""))
        XCTAssertNil(MovementDatabase.normalizedBrandName("(only qualifier)"))
        XCTAssertNil(MovementDatabase.normalizedBrandName("   "))
    }

    func test_normalizedBrandName_multiword_brand_prefers_longest() {
        // "Grand Seiko ..." 는 단일 "Seiko" 가 아니라 "Grand Seiko" 로.
        XCTAssertEqual(MovementDatabase.normalizedBrandName("Grand Seiko Heritage"), "Grand Seiko")
        XCTAssertEqual(MovementDatabase.normalizedBrandName("TAG Heuer Carrera"), "TAG Heuer")
    }

    // MARK: - brandNames() 정규화 + dedupe + 정렬

    func test_brandNames_dedupes_and_sorts() {
        let db = MovementDatabase(movements: [
            makeMovement(id: "1", families: ["Rolex Submariner", "Rolex Datejust"]),
            makeMovement(id: "2", families: ["Omega Speedmaster", "rolex day-date"]),
        ])
        let names = db.brandNames()
        // Rolex 대소문자 무시 dedupe → 1회, Omega 1회.
        XCTAssertEqual(names.filter { $0.lowercased() == "rolex" }.count, 1)
        XCTAssertTrue(names.contains("Omega"))
        // 알파벳 정렬: Omega < Rolex.
        XCTAssertEqual(names, names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    func test_brandNames_excludes_generic_token() {
        let db = MovementDatabase(movements: [
            makeMovement(id: "1", families: ["Seiko 5 Sports", "microbrand"]),
        ])
        let names = db.brandNames()
        XCTAssertTrue(names.contains("Seiko"))
        XCTAssertFalse(names.contains("microbrand"))
    }

    // MARK: - replaceAll in-place swap

    func test_replaceAll_swaps_dataset_atomically() {
        let db = MovementDatabase(movements: [makeMovement(id: "Old", families: ["OldBrand"])])
        XCTAssertNotNil(db.movement(id: "Old"))
        db.replaceAll(with: [makeMovement(id: "New", families: ["NewBrand"])])
        XCTAssertNil(db.movement(id: "Old"), "교체 후 옛 항목은 사라진다")
        XCTAssertNotNil(db.movement(id: "New"))
        XCTAssertEqual(db.movements.map(\.id), ["New"])
    }

    // MARK: - 정적 searchBrands (shared 진입점)

    func test_static_searchBrands_empty_query_returns_empty() {
        // 정적 진입점은 shared 인스턴스 사용 — 빈 query 는 항상 빈 배열.
        XCTAssertTrue(MovementDatabase.searchBrands("").isEmpty)
        XCTAssertTrue(MovementDatabase.searchBrands("   ").isEmpty)
    }

    func test_searchBrands_respects_limit() {
        // 다양한 contains 매칭이 limit 으로 cap 되는지 (인스턴스 메서드 limit 분기).
        let db = MovementDatabase(movements: [
            makeMovement(id: "1", families: ["Omega"]),
            makeMovement(id: "2", families: ["Oris"]),
        ])
        let results = db.searchBrands("o", limit: 1)
        XCTAssertEqual(results.count, 1, "limit 1 로 cap")
    }
}
