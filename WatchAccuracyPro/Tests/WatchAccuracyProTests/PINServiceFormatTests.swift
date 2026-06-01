import XCTest
@testable import WatchAccuracyPro

/// PINService 의 순수(deterministic) 부분만 검증.
/// - `isValidPINFormat` 는 static pure helper (Keychain 무관).
/// - `retryAfterSeconds` / `isPINLockedOut` / `resetFailureCount` 는 UserDefaults·in-memory state 기반.
/// Keychain 의존 경로(setPIN/verifyPIN/clearPIN)는 테스트 호스트 entitlement 불확실 → 의도적으로 제외.
@MainActor
final class PINServiceFormatTests: XCTestCase {

    private let failureCountKey = "com.ticklab.pin.failureCount"

    override func tearDown() {
        // resetFailureCount 가 쓰는 키 정리.
        UserDefaults.standard.removeObject(forKey: failureCountKey)
        super.tearDown()
    }

    // MARK: - isValidPINFormat

    func test_isValidPINFormat_accepts_six_ascii_digits() {
        XCTAssertTrue(PINService.isValidPINFormat("000000"))
        XCTAssertTrue(PINService.isValidPINFormat("123456"))
        XCTAssertTrue(PINService.isValidPINFormat("987654"))
    }

    func test_isValidPINFormat_rejects_wrong_length() {
        XCTAssertFalse(PINService.isValidPINFormat(""))
        XCTAssertFalse(PINService.isValidPINFormat("12345"))   // 5자리
        XCTAssertFalse(PINService.isValidPINFormat("1234567")) // 7자리
    }

    func test_isValidPINFormat_rejects_non_digits() {
        XCTAssertFalse(PINService.isValidPINFormat("12345a"))
        XCTAssertFalse(PINService.isValidPINFormat("abcdef"))
        XCTAssertFalse(PINService.isValidPINFormat("12 456"))
    }

    func test_isValidPINFormat_rejects_non_ascii_digits() {
        // 아라비아-인도 숫자(٠١٢٣٤٥) — isNumber 는 true 이지만 isASCII 는 false.
        XCTAssertFalse(PINService.isValidPINFormat("٠١٢٣٤٥"))
    }

    // MARK: - 상수

    func test_constants() {
        XCTAssertEqual(PINService.pinLength, 6)
        XCTAssertEqual(PINService.maxFailureAttempts, 5)
    }

    // MARK: - failure counter / locked-out (UserDefaults 기반, Keychain 무관)

    func test_resetFailureCount_clears_counter_and_unlocks() {
        let service = PINService.shared
        service.resetFailureCount()
        XCTAssertEqual(service.failureCount, 0)
        XCTAssertFalse(service.isPINLockedOut)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: failureCountKey), 0)
    }

    // MARK: - retryAfterSeconds

    func test_retryAfterSeconds_zero_when_no_recent_failure() {
        // 초기 상태(또는 reset 직후)엔 lastFailureAt 가 없어 throttle 0.
        let service = PINService.shared
        service.resetFailureCount()
        // verify 를 호출하지 않았으므로 lastFailureAt 은 nil 경로.
        XCTAssertEqual(service.retryAfterSeconds, 0, accuracy: 0.0001)
    }
}
