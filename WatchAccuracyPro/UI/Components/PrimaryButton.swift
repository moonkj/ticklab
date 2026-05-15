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

/// Round 170: 모든 버튼에 scale-on-tap 적용용 ButtonStyle.
/// contentShape(Rectangle()) — 배경 전체를 hit-test 영역으로 지정.
/// 이 없으면 SwiftUI 가 텍스트/아이콘 크기만 hit-test → 가운데만 눌림.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
