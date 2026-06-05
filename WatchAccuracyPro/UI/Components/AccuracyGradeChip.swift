import SwiftUI

/// Sprint 3 (P2-5): 정확도 등급 칩 — rate 값 기반 4단계 레이블.
/// COSCBar 아래에 배치해 수치 + 등급 문맥 동시 제공.
///
/// 기준:
///   COSC 크로노미터: −4 ~ +6 s/d
///   우수:           ±15 s/d (일반 정밀 기계식)
///   보통:           ±30 s/d
///   정비 권장:      그 외
struct AccuracyGradeChip: View {
    let rateSecondsPerDay: Double

    private enum AccuracyTier {
        case cosc, excellent, normal, service

        var label: LocalizedStringResource {
            switch self {
            case .cosc:      return "accuracy.tier.cosc"
            case .excellent: return "accuracy.tier.excellent"
            case .normal:    return "accuracy.tier.normal"
            case .service:   return "accuracy.tier.service"
            }
        }

        var icon: String {
            switch self {
            case .cosc:      return "checkmark.seal.fill"
            case .excellent: return "star.fill"
            case .normal:    return "minus.circle"
            case .service:   return "wrench.and.screwdriver"
            }
        }

        var color: Color {
            switch self {
            case .cosc:      return AppColors.success
            case .excellent: return Color(red: 0.2, green: 0.6, blue: 0.9)
            case .normal:    return AppColors.warning
            case .service:   return AppColors.danger
            }
        }
    }

    private var tier: AccuracyTier {
        let abs = Swift.abs(rateSecondsPerDay)
        if rateSecondsPerDay >= -4 && rateSecondsPerDay <= 6 { return .cosc }
        if abs <= 15 { return .excellent }
        if abs <= 30 { return .normal }
        return .service
    }

    var body: some View {
        HStack(spacing: 5) {
            ConceptGlyph(systemName: tier.icon, size: 11)
            Text(tier.label)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tier.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tier.color.opacity(0.12))
        .overlay(Capsule().stroke(tier.color.opacity(0.35), lineWidth: 1))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }
}
