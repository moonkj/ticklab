import SwiftData
import SwiftUI

/// Sprint 14 (S2, R5 시그니처): 2층 진단 카드.
/// 한 줄 평(입문자) + 탭하면 시계공 코칭 펼침(전문가). 측정 히스토리 기반 추세 진단.
struct TrendDiagnosisCard: View {
    let watch: Watch
    let measurements: [WatchMeasurement]
    @State private var expanded = false

    private var diagnosis: TrendDiagnosisService.Diagnosis? {
        TrendDiagnosisService.diagnose(watch: watch, measurements: measurements)
    }

    private func tone(_ s: TrendDiagnosisService.Severity) -> Color {
        switch s {
        case .good:    return AppColors.success
        case .watch:   return AppColors.warning
        case .service: return AppColors.danger
        }
    }

    private func icon(_ s: TrendDiagnosisService.Severity) -> String {
        switch s {
        case .good:    return "checkmark.seal.fill"
        case .watch:   return "eye.fill"
        case .service: return "wrench.and.screwdriver.fill"
        }
    }

    var body: some View {
        if let d = diagnosis {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() }
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ConceptGlyph(systemName: icon(d.severity), size: 18, color: tone(d.severity))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "trend.eyebrow"))
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.5)
                                .foregroundStyle(AppColors.accentDark)
                            Text(d.headline)
                                .font(.system(size: 16, weight: .semibold, design: .serif))
                                .foregroundStyle(AppColors.ink0)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.ink3)
                    }
                    if expanded {
                        Divider()
                        Text(d.coaching)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.ink1)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                        Text(String(localized: "trend.disclaimer"))
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.ink3)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tone(d.severity).opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(tone(d.severity).opacity(0.25), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
