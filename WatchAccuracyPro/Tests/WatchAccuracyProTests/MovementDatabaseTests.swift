import XCTest
@testable import WatchAccuracyPro

final class MovementDatabaseTests: XCTestCase {
    func test_loadFromBundle_returnsTopMovements() throws {
        let bundle = Bundle(for: type(of: self))
        let movements: [Movement]
        do {
            movements = try MovementDatabase.loadFromBundle(.main)
        } catch {
            movements = try MovementDatabase.loadFromBundle(bundle)
        }
        // Phase 2 OTA 확장: Top 10 → Top 30 으로. 최소 25개 이상 + 핵심 캘리버 유지를 검증.
        XCTAssertGreaterThanOrEqual(movements.count, 25, "Phase 2 무브먼트 DB 는 최소 25개 이상")
        let coreCalibers = ["ETA_2824-2", "ETA_7750", "Sellita_SW200",
                            "Rolex_3135", "Omega_8800", "Tudor_MT5602", "Seiko_NH35"]
        for id in coreCalibers {
            XCTAssertNotNil(movements.first(where: { $0.id == id }), "필수 캘리버 \(id) 누락")
        }
    }

    func test_eta_2824_has_correct_lift_angle_and_bph() throws {
        let movements = try MovementDatabase.loadFromBundle(.main)
        let eta = try XCTUnwrap(movements.first(where: { $0.id == "ETA_2824-2" }))
        XCTAssertEqual(eta.bph, 28800)
        XCTAssertEqual(eta.liftAngleDegrees, 52.0, accuracy: 0.01)
        XCTAssertEqual(eta.escapement, .swissLever)
        XCTAssertEqual(eta.confidenceLabel, .high)
    }

    func test_omega_8800_is_coaxial_and_does_not_display_amplitude() throws {
        let movements = try MovementDatabase.loadFromBundle(.main)
        let omega = try XCTUnwrap(movements.first(where: { $0.id == "Omega_8800" }))
        XCTAssertEqual(omega.escapement, .coAxial)
        XCTAssertEqual(omega.confidenceLabel, .medium)
        XCTAssertFalse(omega.shouldDisplayAmplitude, "코악시얼은 amplitude 미표시")
        XCTAssertNil(omega.typicalAmplitudeRange, "코악시얼은 typical amplitude range 가 없어야 한다")
    }

    func test_database_lookup_by_id() throws {
        let db = try MovementDatabase(movements: MovementDatabase.loadFromBundle(.main))
        XCTAssertNotNil(db.movement(id: "Rolex_3135"))
        XCTAssertNil(db.movement(id: "Nonexistent_0000"))
    }

    func test_lift_angle_lookup_returns_nil_for_unknown_caliber() throws {
        let db = try MovementDatabase(movements: MovementDatabase.loadFromBundle(.main))
        XCTAssertEqual(db.liftAngle(forCaliber: "ETA_2824-2"), 52.0)
        XCTAssertNil(db.liftAngle(forCaliber: nil))
        XCTAssertNil(db.liftAngle(forCaliber: "InventedCaliber_9999"))
    }

    // MARK: - Brand search (T-07: AddWatchView 브랜드 자동완성)

    /// 고정 fixture — brandFamilies 의 brand + model-line 혼합을 표준 브랜드로 collapse 하는지 검증.
    private func makeSearchDB() -> MovementDatabase {
        let movements: [Movement] = [
            Movement(id: "Rolex_3135",
                     brandFamilies: ["Rolex Submariner", "Rolex Datejust (vintage 1970s-80s)"],
                     bph: 28800, liftAngleDegrees: 52.0, escapement: .swissLever,
                     typicalAmplitudeMin: nil, typicalAmplitudeMax: nil,
                     coscToleranceMin: nil, coscToleranceMax: nil, confidenceLabel: .high),
            Movement(id: "ETA_2824-2",
                     brandFamilies: ["Hamilton", "Tissot", "Tudor (vintage)", "Mido"],
                     bph: 28800, liftAngleDegrees: 52.0, escapement: .swissLever,
                     typicalAmplitudeMin: nil, typicalAmplitudeMax: nil,
                     coscToleranceMin: nil, coscToleranceMax: nil, confidenceLabel: .high),
            Movement(id: "Seiko_NH35",
                     brandFamilies: ["Seiko 5 Sports", "microbrand"],
                     bph: 21600, liftAngleDegrees: 53.0, escapement: .swissLever,
                     typicalAmplitudeMin: nil, typicalAmplitudeMax: nil,
                     coscToleranceMin: nil, coscToleranceMax: nil, confidenceLabel: .high),
            Movement(id: "GS_9S65",
                     brandFamilies: ["Grand Seiko Heritage"],
                     bph: 28800, liftAngleDegrees: 52.0, escapement: .swissLever,
                     typicalAmplitudeMin: nil, typicalAmplitudeMax: nil,
                     coscToleranceMin: nil, coscToleranceMax: nil, confidenceLabel: .high),
        ]
        return MovementDatabase(movements: movements)
    }

    func test_searchBrands_exactMatch_returnsBrandFirst() {
        let db = makeSearchDB()
        let results = db.searchBrands("Tissot")
        // 정확 일치는 결과의 맨 앞에 위치.
        XCTAssertEqual(results.first, "Tissot")
    }

    func test_searchBrands_caseInsensitive() {
        let db = makeSearchDB()
        // 소문자 query 도 "Hamilton" 매칭.
        XCTAssertTrue(db.searchBrands("hamilton").contains("Hamilton"))
        // 대문자 query 도 동일 결과.
        XCTAssertTrue(db.searchBrands("HAMILTON").contains("Hamilton"))
    }

    func test_searchBrands_partialContains_collapsesToCanonicalBrand() {
        let db = makeSearchDB()
        // "rol" → "Rolex Submariner"/"Rolex Datejust ..." 가 모두 "Rolex" 로 collapse + dedupe.
        let results = db.searchBrands("rol")
        XCTAssertEqual(results, ["Rolex"])
        // 멀티워드 브랜드: "grand" → "Grand Seiko" (단일 "Seiko" 로 잘리지 않음).
        XCTAssertEqual(db.searchBrands("grand"), ["Grand Seiko"])
    }

    func test_searchBrands_emptyQuery_returnsEmpty() {
        let db = makeSearchDB()
        XCTAssertTrue(db.searchBrands("").isEmpty)
        XCTAssertTrue(db.searchBrands("   ").isEmpty)
    }

    func test_searchBrands_noMatch_returnsEmpty() {
        let db = makeSearchDB()
        // 어떤 브랜드에도 없는 query.
        XCTAssertTrue(db.searchBrands("ZzNonexistentBrandZz").isEmpty)
        // 일반 분류 토큰 "microbrand" 는 브랜드 후보에서 제외 → 매칭 안 됨.
        XCTAssertTrue(db.searchBrands("microbrand").isEmpty)
    }
}
