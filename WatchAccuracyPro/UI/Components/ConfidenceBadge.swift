import SwiftUI

/// 0~100 점수를 색·라벨·게이지로 시각화.
struct ConfidenceBadge: View {
    let score: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "confidence.label"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                Text("\(score) / 100")
                    .font(AppTypography.headline)
                    .foregroundStyle(color)
            }
            Spacer()
            ProgressView(value: Double(score) / 100)
                .progressViewStyle(.linear)
                .tint(color)
                .frame(width: 100)
        }
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var color: Color {
        switch score {
        case 80...:  return AppColors.success
        case 50..<80: return AppColors.warning
        default:     return AppColors.danger
        }
    }

    private var icon: String {
        switch score {
        case 80...:   return "checkmark.seal.fill"
        case 50..<80: return "exclamationmark.triangle"
        default:      return "questionmark.circle"
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        ConfidenceBadge(score: 92)
        ConfidenceBadge(score: 65)
        ConfidenceBadge(score: 30)
    }
    .padding()
}
