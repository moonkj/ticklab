import SwiftUI

/// Editorial help card — 안내 카드.
/// neutral: paper-1 배경 / warning: warningTint
struct HelpCard: View {
    enum Tone { case info, warning }
    let icon: String
    let title: String
    let message: String
    let tone: Tone

    init(icon: String = "info.circle", title: String, body: String, tone: Tone = .info) {
        self.icon = icon
        self.title = title
        self.message = body
        self.tone = tone
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(iconColor)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(AppColors.ink0)
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppColors.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var background: Color {
        switch tone {
        case .info:    return AppColors.paper1
        case .warning: return AppColors.warningTint
        }
    }
    private var borderColor: Color {
        switch tone {
        case .info:    return AppColors.rule
        case .warning: return AppColors.warning.opacity(0.3)
        }
    }
    private var iconColor: Color {
        switch tone {
        case .info:    return AppColors.ink2
        case .warning: return AppColors.warning
        }
    }
}

#Preview {
    VStack(spacing: 10) {
        HelpCard(icon: "mic", title: "Place the iPhone microphone near the watch",
                 body: "Lay the watch on a soft cloth and bring the iPhone within a few centimeters.")
        HelpCard(icon: "exclamationmark.triangle", title: "Weak signal",
                 body: "Move the iPhone closer to the watch — signal is weak.", tone: .warning)
    }
    .padding()
    .background(AppColors.paper0)
}
