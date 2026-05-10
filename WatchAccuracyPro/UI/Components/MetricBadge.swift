import SwiftUI

/// 큰 숫자 + 단위 + 라벨 한 묶음. 측정 화면/결과 화면에서 rate, beat error 등을 표시.
struct MetricBadge: View {
    enum Tone { case neutral, success, warning, danger }

    let label: String
    let value: String
    let unit: String?
    let tone: Tone

    init(label: String, value: String, unit: String? = nil, tone: Tone = .neutral) {
        self.label = label
        self.value = value
        self.unit = unit
        self.tone = tone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(AppTypography.monoMetric)
                    .foregroundStyle(toneColor)
                if let unit {
                    Text(unit)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var toneColor: Color {
        switch tone {
        case .neutral: return AppColors.textPrimary
        case .success: return AppColors.success
        case .warning: return AppColors.warning
        case .danger:  return AppColors.danger
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        MetricBadge(label: "Rate", value: "+5.2", unit: "초/일", tone: .success)
        MetricBadge(label: "Beat Error", value: "0.4", unit: "ms")
        MetricBadge(label: "Amplitude", value: "—", tone: .neutral)
    }
    .padding()
}
