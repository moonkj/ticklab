import SwiftUI

/// 디자인 SSOT components.jsx ConfidenceBadge port.
/// Dot + icon + value% — tier 별 색상 (ok ≥90 / warn ≥70 / bad ≥50 / unk <50).
/// 기존 인터페이스 호환: `score` (Int), `compact` (Bool).
struct ConfidenceBadge: View {
    let score: Int
    var compact: Bool = false

    private var tier: Tier {
        if score >= 90 { return .ok }
        if score >= 70 { return .warn }
        if score >= 50 { return .bad }
        return .unk
    }

    enum Tier {
        case ok, warn, bad, unk
        var color: Color {
            switch self {
            case .ok:   return AppColors.success
            case .warn: return AppColors.warning
            case .bad:  return AppColors.danger
            case .unk:  return AppColors.ink2
            }
        }
        var iconName: String {
            switch self {
            case .ok:   return "checkmark.circle.fill"
            case .warn: return "moon.fill"
            case .bad:  return "exclamationmark.triangle.fill"
            case .unk:  return "questionmark.circle.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Circle()
                .fill(tier.color)
                .frame(width: compact ? 6 : 8, height: compact ? 6 : 8)
            Image(systemName: tier.iconName)
                .font(.system(size: compact ? 10 : 12))
                .foregroundStyle(tier.color)
            Text("\(score)%")
                .font(.system(size: compact ? 11 : 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(tier.color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(format: NSLocalizedString("a11y.confidence_badge", comment: ""), score)))
    }
}

#Preview {
    VStack(spacing: 12) {
        ConfidenceBadge(score: 96)
        ConfidenceBadge(score: 78)
        ConfidenceBadge(score: 55)
        ConfidenceBadge(score: 30, compact: true)
    }
    .padding()
    .background(AppColors.paper0)
}
