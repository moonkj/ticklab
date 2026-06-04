import UIKit

/// T-17: 앱 전역 햅틱 피드백 중앙화.
/// `UserPreferences.hapticsEnabled`(UserDefaults)를 매 trigger 시 참조 → 설정 토글이 즉시 반영.
enum HapticEvent {
    case measurementStart      // 측정 시작
    case measurementComplete   // 측정 완료(성공)
    case measurementFailed     // 측정 실패
    case watchAdded            // 시계 추가
    case watchDeleted          // 시계 삭제
    case confidenceHigh        // 고신뢰 측정
    case selection             // 선택 변경
    case lightTap              // 경량 탭
    // 웨이브2-B: 결과 "다이얼 영접" reveal 햅틱.
    case revealCrescendo       // 다이얼 스윕 도착 크레센도(.measurementComplete 와 동의어, 의미 명시용)
    case sealStamped           // 골드 인장 stamp — rigid 단발
}

enum HapticManager {
    /// 사용자 설정(기본 ON). UserPreferences 와 동일 키를 직접 읽어 별도 동기화 불필요.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "ticklab.hapticsEnabled") as? Bool ?? true
    }

    @MainActor
    static func trigger(_ event: HapticEvent) {
        guard isEnabled else { return }
        switch event {
        case .measurementStart:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .measurementComplete, .confidenceHigh:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .measurementFailed:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .watchAdded, .lightTap:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .watchDeleted, .sealStamped:
            // 인장이 linen 위에 '쾅' 찍히는 단단한 단발.
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .revealCrescendo:
            // 바늘이 zone 에 도착하는 순간의 성공 크레센도.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// 웨이브2-B: reveal 크레센도 시퀀스 — 스윕 동안 가벼운 탭 ×2 → 도착 순간 성공 노티.
    /// 호출 측에서 Reduce Motion·`isEnabled` 가드를 통과한 뒤 단발로 부른다.
    /// (개별 trigger 도 각자 `isEnabled` 를 확인하므로 토글이 OFF 면 자동으로 무음.)
    @MainActor
    static func playRevealCrescendo() {
        guard isEnabled else { return }
        // t=0, t=0.35s 가벼운 탭(상승) → t=0.85s 도착 크레센도.
        trigger(.lightTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            trigger(.lightTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            trigger(.revealCrescendo)
        }
    }
}
