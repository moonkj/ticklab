import XCTest
@testable import WatchAccuracyPro

/// PURE/deterministic 부분만 검증: AppLockService.
/// - `autoLockSeconds` 상수 (auto-lock threshold).
/// - 초기 `unlocked` 상태.
/// 생체인증(LAContext)·Keychain(PIN verify) 경로는 테스트 호스트 환경 의존 → 의도적 제외.
/// AppLockService 는 @MainActor 싱글톤 → 클래스도 @MainActor.
@MainActor
final class AppLockServiceTests: XCTestCase {

    // MARK: - auto-lock threshold 상수

    func test_autoLockSeconds_isSixty() {
        XCTAssertEqual(AppLockService.autoLockSeconds, 60)
    }

    // MARK: - 초기 상태

    func test_initialState_isLocked() {
        // 앱 시작 시 잠금 상태(unlocked == false)에서 출발.
        // 생체인증/PIN 성공 경로만 unlocked 를 true 로 만들며, 테스트 환경에선 호출하지 않음.
        XCTAssertFalse(AppLockService.shared.unlocked)
    }
}
