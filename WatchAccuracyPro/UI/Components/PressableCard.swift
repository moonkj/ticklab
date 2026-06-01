import SwiftUI

/// Sprint 8 (UX): 탭 시 자연스러운 press 피드백 — 스케일 펄스 + 가벼운 햅틱.
///
/// 스크롤 공존 + 누름 효과(사용자 보고 여러 번):
///   - 커스텀 DragGesture(minimumDistance:0) 방식은 ScrollView 세로 스크롤을 가로채 막았다.
///   - 순수 ButtonStyle(isPressed) 방식은 스크롤은 되지만, ScrollView 안에서 isPressed 가
///     켜져 있는 시간이 매우 짧아(빠른 탭 + 즉시 화면 이동) 스케일이 눈에 안 보였다(햅틱만 느껴짐).
///   → `.plain` 버튼(스크롤 안전)을 쓰고, 탭 시 누름 펄스(scale 0.95)를 **명시적으로 재생**한 뒤
///     아주 짧게(~0.09s) 지연해 action 을 호출한다. 스크롤은 .plain 버튼이라 그대로 동작하고,
///     탭할 때마다 스케일 펄스가 확실히 보인다.
/// - Reduce Motion 활성 시 펄스 생략(즉시 action), 햅틱만.
struct PressableCard<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            guard !reduceMotion else { action(); return }
            withAnimation(.easeOut(duration: 0.07)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) { pressed = false }
                action()
            }
        } label: {
            content()
                .scaleEffect(pressed ? 0.95 : 1.0)
                .brightness(pressed ? -0.05 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
