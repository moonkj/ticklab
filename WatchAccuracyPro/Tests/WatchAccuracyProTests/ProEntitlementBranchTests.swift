import XCTest
@testable import WatchAccuracyPro

/// 커버리지 보강 — ProEntitlement 의 DEBUG-only markPro / storeKitMarkPro 경로.
/// StoreKit transaction 자체(purchase/restore/handle)는 SKTestSession 없이는 simulate 불가 → 제외.
/// markPro 는 #if DEBUG 전용이며 테스트는 항상 DEBUG 빌드에서 돈다.
///
/// shared 싱글턴 오염을 막기 위해 각 테스트는 끝에서 상태를 false 로 되돌린다.
@MainActor
final class ProEntitlementBranchTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "ticklab.isPro")
        ProEntitlement.shared.markPro(false)
    }

    override func tearDown() {
        ProEntitlement.shared.markPro(false)
        UserDefaults.standard.removeObject(forKey: "ticklab.isPro")
        super.tearDown()
    }

    // MARK: - markPro → storeKitMarkPro 상태 전이

    func test_markPro_true_sets_isPro_and_userdefaults() {
        let ent = ProEntitlement.shared
        XCTAssertFalse(ent.isPro)
        ent.markPro(true)
        XCTAssertTrue(ent.isPro)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "ticklab.isPro"),
                      "isPro 변경은 UserDefaults 와 동기화돼야 한다")
    }

    func test_markPro_false_clears_isPro() {
        let ent = ProEntitlement.shared
        ent.markPro(true)
        ent.markPro(false)
        XCTAssertFalse(ent.isPro)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "ticklab.isPro"))
    }

    func test_markPro_same_state_is_noop_no_notification() {
        // guard isPro != on — 이미 false 인데 false set → notification post 안 됨.
        let ent = ProEntitlement.shared
        XCTAssertFalse(ent.isPro)

        var notified = false
        let token = NotificationCenter.default.addObserver(
            forName: .ticklabProEntitlementChanged, object: nil, queue: nil
        ) { _ in notified = true }
        defer { NotificationCenter.default.removeObserver(token) }

        ent.markPro(false)  // 동일 상태 → 조기 return
        XCTAssertFalse(notified, "동일 상태 set 은 notification 을 발행하지 않는다")
    }

    func test_markPro_state_change_posts_notification_with_payload() {
        let ent = ProEntitlement.shared
        let expectation = expectation(description: "pro entitlement changed")
        var receivedIsPro: Bool?
        let token = NotificationCenter.default.addObserver(
            forName: .ticklabProEntitlementChanged, object: nil, queue: nil
        ) { note in
            receivedIsPro = note.userInfo?["isPro"] as? Bool
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        ent.markPro(true)  // false → true 상태 전이 → notification.
        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(receivedIsPro, true, "notification payload isPro=true")
    }

    func test_markPro_toggle_round_trip() {
        let ent = ProEntitlement.shared
        ent.markPro(true)
        XCTAssertTrue(ent.isPro)
        ent.markPro(false)
        XCTAssertFalse(ent.isPro)
        ent.markPro(true)
        XCTAssertTrue(ent.isPro)
    }
}
