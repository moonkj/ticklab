import SwiftUI

/// Sprint 8 (UX): 탭 시 자연스러운 press 피드백 — 누르는 순간 scale 0.96 + dim, 뗄 때 spring back.
///
/// 스크롤 공존 fix (사용자 보고: 시계 다수 시 컬렉션 위아래 스와이프 곤란):
///   기존 코드는 onChanged 에서 touch-down 즉시 햅틱을 울려, 스크롤을 시작할 때마다 카드마다
///   햅틱·스케일이 깜빡여 세로 스와이프가 끈적였다.
///   → 햅틱·탭 액션은 "이동 거리 < tapSlop(=탭)" 일 때 onEnded 에서만 발동하고,
///     드래그가 tapSlop 을 넘으면(=스크롤 의도) press 를 즉시 해제한다.
///     simultaneousGesture 라 ScrollView 세로 스크롤은 그대로 동작하고,
///     touch-down 즉시 들어가는 누름 효과(scale)는 유지된다.
/// - Reduce Motion 활성 시 애니메이션 없음(누름 효과 생략).
struct PressableCard<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 탭 vs 스크롤 판정 임계값(pt). 이 이상 움직이면 스크롤로 간주.
    private let tapSlop: CGFloat = 12

    var body: some View {
        content()
            .scaleEffect(isPressed && !reduceMotion ? 0.96 : 1.0)
            .brightness(isPressed && !reduceMotion ? -0.04 : 0)
            .animation(
                isPressed
                    ? .easeIn(duration: 0.08)
                    : .spring(response: 0.35, dampingFraction: 0.65),
                value: isPressed
            )
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        let d = hypot(val.translation.width, val.translation.height)
                        if d < tapSlop {
                            // 손가락이 거의 안 움직임 → 누름 효과 즉시 표시.
                            if !isPressed { isPressed = true }
                        } else if isPressed {
                            // 움직이기 시작 → 스크롤 의도. 누름 해제(스크롤은 ScrollView 가 처리).
                            isPressed = false
                        }
                    }
                    .onEnded { val in
                        let wasPressed = isPressed
                        isPressed = false
                        let d = hypot(val.translation.width, val.translation.height)
                        // 탭(거의 안 움직임)일 때만 햅틱 + 액션. 스크롤이면 무시.
                        if wasPressed && d < tapSlop {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            action()
                        }
                    }
            )
    }
}
