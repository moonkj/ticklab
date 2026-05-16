import Foundation
import LocalAuthentication

/// Face ID / Touch ID 기반 앱 잠금 + 커스텀 PIN (선택).
/// UserPreferences.appLockEnabled 토글에 의해 활성.
/// Pivot Addendum Security: 시계 컬렉션은 민감한 자산 정보 — 디바이스 잠금 외에도 앱 별 잠금.
@MainActor
final class AppLockService: ObservableObject {
    static let shared = AppLockService()

    /// 현재 unlock 상태. true 면 정상 진입.
    @Published private(set) var unlocked: Bool = false

    /// 마지막 unlock 시각. background 일정 시간 후 자동 lock.
    private var lastUnlockedAt: Date?
    static let autoLockSeconds: TimeInterval = 60

    private let pinService: PINService

    private init(pinService: PINService = .shared) {
        self.pinService = pinService
    }

    // MARK: - PIN 사용 가능 여부

    /// PIN 으로 잠금 해제할 수 있는 상태인지.
    /// - 사용자가 PIN 을 설정해두었고
    /// - 5회 연속 실패로 lockout 되지 않았어야 함
    var canUsePIN: Bool {
        pinService.hasPIN && !pinService.isPINLockedOut
    }

    // MARK: - Face ID / Passcode unlock

    /// 토글 켜진 상태에서 호출 — 인증 요청.
    /// PIN 이 활성/미락아웃 이라도 PIN 입력 화면은 별도 호출자가 띄움.
    /// 본 메서드는 항상 Face ID / passcode 기반 unlock.
    func unlock() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // biometrics 없음 → passcode fallback.
            return await fallbackPasscode()
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: String(localized: "applock.reason")
            )
            // Round 15 (Min): 인증 취소/실패 시 unlocked = false 로 덮어쓰지 않음.
            //   이미 unlocked 인 세션이 biometric 재인증 실패로 락 되는 회귀 차단.
            if success {
                unlocked = true
                lastUnlockedAt = Date()
                // Face ID 성공은 PIN 실패 카운터를 리셋 (사용자가 본인임을 입증).
                pinService.resetFailureCount()
            }
            return success
        } catch {
            return await fallbackPasscode()
        }
    }

    private func fallbackPasscode() async -> Bool {
        let context = LAContext()
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "applock.reason")
            )
            if success {
                unlocked = true
                lastUnlockedAt = Date()
                pinService.resetFailureCount()
            }
            return success
        } catch {
            return false
        }
    }

    // MARK: - PIN unlock

    /// 사용자가 입력한 6자리 PIN 으로 잠금 해제 시도.
    /// 성공 시 unlocked = true. lockout 상태면 무조건 실패.
    func unlockWithPIN(_ pin: String) -> Bool {
        guard canUsePIN else { return false }
        let success = pinService.verifyPIN(pin)
        if success {
            unlocked = true
            lastUnlockedAt = Date()
        }
        return success
    }

    // Round 146 (Hyemi 6): didEnterBackground/didBecomeActive 메서드는 dead code — RootView 가
    // 자체적으로 ScenePhase 60s 로직을 구현. 의미상 buggy (didEnterBackground 가 lastUnlockedAt 갱신해
    // auto-lock 을 오히려 지연) 이라 호출됐다면 위험. 안전하게 제거.
}
