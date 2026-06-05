import XCTest
@testable import WatchAccuracyPro

/// INFRA-1 (Sprint 2): ProEntitlement 핵심 로직 단위 테스트.
/// StoreKit 트랜잭션 자체는 StoreKitTest(SKTestSession) 없이는 simulate 불가능 — 여기선
/// allProductIds 집합과 UserDefaults 연동만 검증.
@MainActor
final class ProEntitlementTests: XCTestCase {

    override func setUp() {
        super.setUp()
        LaunchPromo.overrideActive = false   // 프로모 off → isPro 가 실제 entitlement 반영(초기 false 검증)
        UserDefaults.standard.removeObject(forKey: "ticklab.isPro")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "ticklab.isPro")
        LaunchPromo.overrideActive = nil
        super.tearDown()
    }

    // MARK: - Product ID 집합

    func test_allProductIds_contains_monthly() {
        XCTAssertTrue(ProEntitlement.allProductIds.contains(ProEntitlement.monthlyProductId))
    }

    func test_allProductIds_contains_yearly() {
        XCTAssertTrue(ProEntitlement.allProductIds.contains(ProEntitlement.yearlyProductId))
    }

    func test_allProductIds_count_is_two() {
        XCTAssertEqual(ProEntitlement.allProductIds.count, 2,
                       "monthly + yearly = 2 (평생 제거). 신규 상품 추가 시 이 테스트 업데이트 필요.")
    }

    // MARK: - UserDefaults 초기화

    func test_initial_isPro_false_when_no_userdefaults() {
        // UserDefaults 에 값 없으면 false 로 초기화.
        let entitlement = ProEntitlement.shared
        // 다른 테스트가 setUp에서 지워주므로 false 여야 함.
        // NOTE: shared 싱글턴이라 다른 테스트 오염 가능 — 값만 검증, 변경은 markPro(DEBUG) 사용.
        XCTAssertFalse(entitlement.isPro)
    }

    // MARK: - Product ID 형식

    func test_product_ids_have_ticklab_prefix() {
        for id in ProEntitlement.allProductIds {
            XCTAssertTrue(id.hasPrefix("com.ticklab."),
                          "\(id) should start with com.ticklab.")
        }
    }

    func test_monthly_product_id_is_correct() {
        XCTAssertEqual(ProEntitlement.monthlyProductId, "com.ticklab.watchaccuracypro.pro.monthly")
    }

    func test_yearly_product_id_is_correct() {
        XCTAssertEqual(ProEntitlement.yearlyProductId, "com.ticklab.app.pro.yearly")
    }

    // MARK: - Free tier limits

    func test_free_watch_limit_is_one() {
        XCTAssertEqual(ProEntitlement.freeWatchLimit, 1)
    }

    func test_free_daily_measurement_limit_is_three() {
        XCTAssertEqual(ProEntitlement.freeDailyMeasurementLimit, 3)
    }

    func test_free_journal_month_limit_is_five() {
        XCTAssertEqual(ProEntitlement.freeJournalMonthLimit, 5)
    }
}
