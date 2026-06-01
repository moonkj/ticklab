import SwiftUI

/// Sprint 8 (UX): 탭 시 자연스러운 press 피드백.
/// - 누르는 순간 scale 0.97 + dim → 손가락 뗄 때 spring back
/// - Reduce Motion 활성 시 애니메이션 없음
///
/// 스크롤 충돌 fix (사용자 보고: 시계 다수 시 컬렉션 위아래 스와이프 곤란):
///   기존 `.simultaneousGesture(DragGesture(minimumDistance: 0))` 는 손가락이 닿는 즉시
///   press 상태 + 햅틱을 발동시켜 ScrollView 세로 팬과 경쟁 → 카드 위 스와이프가 끈적였음.
///   ButtonStyle 기반으로 교체하면 시스템이 스크롤 vs 탭을 직접 판별 → 세로 스와이프 시
///   press/햅틱 오발이 사라지고 스크롤이 매끄러워짐. 탭 액션은 그대로 유지.
struct PressableCard<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            content()
        }
        .buttonStyle(PressableCardButtonStyle())
    }
}

private struct PressableCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .brightness(configuration.isPressed && !reduceMotion ? -0.04 : 0)
            .animation(
                configuration.isPressed
                    ? .easeIn(duration: 0.08)
                    : .spring(response: 0.35, dampingFraction: 0.65),
                value: configuration.isPressed
            )
            .contentShape(Rectangle())
    }
}
