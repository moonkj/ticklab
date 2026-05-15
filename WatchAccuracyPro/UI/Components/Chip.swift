import SwiftUI

/// Editorial pill chip — 작은 status 라벨 (e.g. "✓ COSC band", "Outside COSC", "NEW").
struct Chip: View {
    enum Tone { case neutral, success, warning, danger, accent }
    let text: String
    let tone: Tone
    let small: Bool

    init(_ text: String, tone: Tone = .neutral, small: Bool = false) {
        self.text = text
        self.tone = tone
        self.small = small
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: small ? 9.5 : 10.5, weight: .semibold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(fg)
            .padding(.horizontal, small ? 8 : 10)
            .padding(.vertical, small ? 2 : 3)
            .background(bg)
            .clipShape(Capsule())
    }

    private var bg: Color {
        switch tone {
        case .neutral: return AppColors.paper2
        case .success: return AppColors.successTint
        case .warning: return AppColors.warningTint
        case .danger:  return AppColors.dangerTint
        case .accent:  return AppColors.accentTint
        }
    }
    private var fg: Color {
        switch tone {
        case .neutral: return AppColors.ink1
        case .success: return AppColors.success
        case .warning: return AppColors.warning
        case .danger:  return AppColors.danger
        case .accent:  return AppColors.accent
        }
    }
}

#Preview {
    HStack {
        Chip("✓ COSC band", tone: .success, small: true)
        Chip("−4 / +6 s/d", small: true)
        Chip("NEW", tone: .accent, small: true)
    }
    .padding().background(AppColors.paper0)
}
