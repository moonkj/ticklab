import SwiftUI

/// Sprint 6 (INFRA-5): 파워리저브 게이지 컴포넌트.
/// 배터리 아이콘 스타일, opt-in 기본 꺼짐 (UserPreferences 연동).
/// SpecCard.powerReserveHours + 마지막 착용 시간 → 현재 예상 잔량.
struct PowerReserveGauge: View {
    /// 전체 파워리저브 시간 (예: 48h, 72h).
    let maxHours: Double
    /// 마지막 완전 태엽 감은 시각 (nil = 현재 시각 기준 계산 불가).
    let lastWoundAt: Date?

    private var currentHours: Double {
        guard let last = lastWoundAt else { return maxHours }
        let elapsed = Date().timeIntervalSince(last) / 3600
        return max(0, maxHours - elapsed)
    }

    private var fraction: Double {
        guard maxHours > 0 else { return 0 }
        return min(1, currentHours / maxHours)
    }

    private var gaugeColor: Color {
        if fraction > 0.5 { return AppColors.success }
        if fraction > 0.2 { return AppColors.warning }
        return AppColors.danger
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(gaugeColor)
                Text(String(localized: "powerreserve.title"))
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(AppColors.ink2)
                Spacer()
                Text(String(format: NSLocalizedString("powerreserve.remaining", comment: ""), Int(currentHours)))
                    .font(.caption.weight(.bold, design: .monospaced))
                    .foregroundStyle(gaugeColor)
            }
            // 게이지 바
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.paper2).frame(height: 8)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [gaugeColor.opacity(0.7), gaugeColor],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(0, geo.size.width * fraction), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(12)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: NSLocalizedString("powerreserve.a11y", comment: ""), Int(currentHours), Int(maxHours)))
    }
}

private extension Font {
    func weight(_ weight: Font.Weight, design: Font.Design = .default) -> Font { self.weight(weight) }
    func weight(_ weight: Font.Weight) -> Font { self }
}
