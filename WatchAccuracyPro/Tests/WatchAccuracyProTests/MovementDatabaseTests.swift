import XCTest
@testable import WatchAccuracyPro

final class MovementDatabaseTests: XCTestCase {
    func test_loadFromBundle_returnsTopTen() throws {
        let bundle = Bundle(for: type(of: self))
        // 메인 앱 번들이 아닌 테스트 번들에서도 동일 리소스 검색을 위해 fallback 처리
        let movements: [Movement]
        do {
            movements = try MovementDatabase.loadFromBundle(.main)
        } catch {
            movements = try MovementDatabase.loadFromBundle(bundle)
        }
        XCTAssertEqual(movements.count, 10, "Top 10 무브먼트 seed 가 정확히 10개여야 한다")
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
}
