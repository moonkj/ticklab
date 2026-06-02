import SwiftUI

/// Editorial 스타일 버튼.
/// - filled: ink-0 배경 + paper-0 텍스트 (pill shape)
/// - bordered: paper-0 배경 + ink-0 텍스트 + rule-strong 테두리
/// - accent: indigo 배경 + 흰 텍스트 (drama)
struct PrimaryButton: View {
    enum Style { case filled, bordered, accent }
    let title: String
    let style: Style
    let isEnabled: Bool
    let icon: String?
    let height: CGFloat
    let action: () -> Void

    init(
        _ title: String,
        style: Style = .filled,
        isEnabled: Bool = true,
        icon: String? = nil,
        height: CGFloat = 52,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.isEnabled = isEnabled
        self.icon = icon
        self.height = height
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 15, weight: .semibold)) }
                Text(title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .tracking(0.2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(borderColor, lineWidth: borderWidth))
        }
        // Round 170: PressableStyle 로 scale-on-tap + brightness 피드백.
        .buttonStyle(PressableButtonStyle())
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)
    }

    private var background: Color {
        switch style {
        case .filled:   return AppColors.ink0
        case .bordered: return AppColors.paper0
        case .accent:   return AppColors.accent
        }
    }
    private var foreground: Color {
        switch style {
        case .filled:   return AppColors.paper0
        case .bordered: return AppColors.ink0
        case .accent:   return .white
        }
    }
    private var borderColor: Color {
        switch style {
        case .filled:   return AppColors.ink0
        case .bordered: return AppColors.ruleStrong
        case .accent:   return AppColors.accent
        }
    }
    private var borderWidth: CGFloat {
        style == .bordered ? 1 : 1
    }
}

/// Round 170 + Sprint 8 (UX): 모든 버튼에 scale-on-tap + spring 복귀 + haptic.
/// Reduce Motion 활성 시 scale 없이 haptic만.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect((!reduceMotion && configuration.isPressed) ? 0.94 : 1.0)
            // Round 175 (사용자 보고: "측정시작 버튼 누름효과 약함 — 컬렉션 측정 버튼과 동일하게"):
            //   scale 은 Reduce Motion 시 사라지므로 opacity dim 으로 항상 보이는 누름 피드백.
            //   dim 을 더 뚜렷하게(0.6) + 햅틱을 컬렉션 측정 버튼과 동일한 selection tick 으로 통일.
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(
                configuration.isPressed
                    ? .easeIn(duration: 0.06)
                    : .spring(response: 0.28, dampingFraction: 0.65, blendDuration: 0),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    // 컬렉션 측정 버튼(CollectionView)과 동일한 햅틱 — crisp selection tick.
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
    }
}

#Preview {
    VStack(spacing: 12) {
        PrimaryButton("Begin measurement", icon: "mic") {}
        PrimaryButton("Begin 12-hour long test", style: .bordered, icon: "clock.arrow.circlepath") {}
        PrimaryButton("Save reading", style: .accent) {}
    }
    .padding()
    .background(AppColors.paper0)
}
