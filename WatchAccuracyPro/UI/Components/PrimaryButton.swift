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
    /// true 면 SF 아이콘 대신 좌우로 진동하는 밸런스 휠을 리딩 아이콘으로 표시(측정 시작 등).
    let balanceWheel: Bool
    let height: CGFloat
    let action: () -> Void

    init(
        _ title: String,
        style: Style = .filled,
        isEnabled: Bool = true,
        icon: String? = nil,
        balanceWheel: Bool = false,
        height: CGFloat = 52,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.isEnabled = isEnabled
        self.icon = icon
        self.balanceWheel = balanceWheel
        self.height = height
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if balanceWheel {
                    ButtonBalanceWheel(size: 20, color: foreground)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                }
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

/// 버튼 리딩 아이콘용 밸런스 휠 — 시계 비트처럼 좌우로 진동(easeInOut 왕복). Reduce Motion 시 정지.
private struct ButtonBalanceWheel: View {
    var size: CGFloat = 20
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = false

    var body: some View {
        BalanceWheelIcon(size: size, color: color, holeColor: .clear)
            .rotationEffect(.degrees(reduceMotion ? 0 : (beat ? 28 : -28)))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.46).repeatForever(autoreverses: true)) { beat = true }
            }
            .accessibilityHidden(true)
    }
}

/// Round 170 + Sprint 8 (UX): 모든 버튼에 press 피드백 + spring 복귀 + haptic.
/// 웨이브2-A JellySquash: 균일 scale 대신 **비등방 스쿼시&스트레치** —
///   누르면 `scaleY:0.93, scaleX:1.03`(눌려 납작), 떼면 `.bouncy(extraBounce:0.25)` 로
///   오버슈트 후 복귀. transform-only(셰이더 0, 사실상 공짜).
/// Reduce Motion 활성 시 scale 없이 opacity dim + haptic만(가드 유지).
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let squashY: CGFloat = (!reduceMotion && pressed) ? 0.93 : 1.0
        let squashX: CGFloat = (!reduceMotion && pressed) ? 1.03 : 1.0
        return configuration.label
            .contentShape(Rectangle())
            // 비등방 스쿼시 — 누르면 가로로 퍼지고 세로로 납작해진다(젤리).
            .scaleEffect(x: squashX, y: squashY, anchor: .center)
            // Round 175 (사용자 보고: "측정시작 버튼 누름효과 약함"):
            //   scale 은 Reduce Motion 시 사라지므로 opacity dim 으로 항상 보이는 누름 피드백.
            .opacity(pressed ? 0.6 : 1.0)
            .brightness(pressed ? -0.04 : 0)
            .animation(
                pressed
                    ? .easeIn(duration: 0.06)
                    // 떼면 bouncy — 오버슈트 후 정착(젤리 복원).
                    : .bouncy(duration: 0.4, extraBounce: 0.25),
                value: pressed
            )
            .onChange(of: pressed) { _, isPressed in
                if isPressed {
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
