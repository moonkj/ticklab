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
        case .watchDeleted:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}
