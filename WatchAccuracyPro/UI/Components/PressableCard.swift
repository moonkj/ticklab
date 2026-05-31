import SwiftUI

/// Sprint 8 (UX): 탭 시 자연스러운 press 피드백.
/// - 누르는 순간 scale 0.97 + dim → 손가락 뗄 때 spring back
/// - Reduce Motion 활성 시 애니메이션 없이 즉시 action
struct PressableCard<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content()
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1.0)
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
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                    .onEnded { val in
                        isPressed = false
                        // 드래그 거리가 짧으면 탭으로 간주
                        let d = sqrt(pow(val.translation.width, 2) + pow(val.translation.height, 2))
                        if d < 10 { action() }
                    }
            )
    }
}
