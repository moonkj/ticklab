import XCTest
@testable import WatchAccuracyPro

/// INFRA-1 (Sprint 2): ReviewRequestService 쿨다운/카운트 로직 단위 테스트.
@MainActor
final class ReviewRequestServiceTests: XCTestCase {
    private let countKey = "ticklab.review.qualifyingMoments"
    private let lastKey  = "ticklab.review.lastRequest"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: countKey)
        UserDefaults.standard.removeObject(forKey: lastKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: countKey)
        UserDefaults.standard.removeObject(forKey: lastKey)
        super.tearDown()
    }

    func test_qualifying_moment_increments_count() {
        // threshold 100 으로 크게 설정해 실제 requestReview 호출 안 되게.
        ReviewRequestService.qualifyingMomentReached(threshold: 100)
        let count = UserDefaults.standard.integer(forKey: countKey)
        XCTAssertEqual(count, 1)
    }

    func test_qualifying_moment_accumulates() {
        ReviewRequestService.qualifyingMomentReached(threshold: 100)
        ReviewRequestService.qualifyingMomentReached(threshold: 100)
        ReviewRequestService.qualifyingMomentReached(threshold: 100)
        let count = UserDefaults.standard.integer(forKey: countKey)
        XCTAssertEqual(count, 3)
    }

    func test_cooldown_blocks_repeat_request() {
        // 방금 요청한 것처럼 설정 (lastRequest = now).
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastKey)
        // threshold 1 → 바로 fire 시도하지만 cooldown 이 막아야 함.
        // 카운트를 1 이상으로 올린 뒤 threshold=1 호출.
        UserDefaults.standard.set(0, forKey: countKey)
        ReviewRequestService.qualifyingMomentReached(threshold: 1)
        // 쿨다운이 작동하면 lastRequest 가 변하지 않아야 함 (seconds 단위 오차 허용).
        let stored = UserDefaults.standard.double(forKey: lastKey)
        let elapsed = Date().timeIntervalSince1970 - stored
        // 방금 설정한 값이 그대로이면 elapsed ≈ 0s. 새로 설정됐으면 elapsed ≈ 0s 로 같으나
        // count 가 0 으로 reset 됐으면 request 가 fire 됐음을 의미 — count 잔존 확인.
        let count = UserDefaults.standard.integer(forKey: countKey)
        // cooldown 에 걸려 request 안 됐으면 count = 1 (increment만, reset 없음).
        XCTAssertEqual(count, 1, "Cooldown should prevent request, count should still be 1")
        _ = elapsed
    }
}
