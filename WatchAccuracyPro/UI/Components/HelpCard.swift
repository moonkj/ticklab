import SwiftUI

/// 안내 카드 (코악시얼 알림, 측정 팁 등). icon + title + message.
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(toneColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(AppTypography.headline)
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(toneColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(toneColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var toneColor: Color {
        switch tone {
        case .info: return AppColors.primary
        case .warning: return AppColors.warning
        }
    }
}

#Preview {
    VStack(spacing: 10) {
        HelpCard(
            title: "이 무브먼트는 코악시얼입니다",
            body: "amplitude 측정 정확도가 일반 timegrapher 보다 낮을 수 있어 표시되지 않습니다."
        )
        HelpCard(
            icon: "exclamationmark.triangle",
            title: "측정 환경에 주의하세요",
            body: "시계와 마이크 거리는 1cm 이내, 주변 소음 30dB 이하 권장.",
            tone: .warning
        )
    }
    .padding()
}
