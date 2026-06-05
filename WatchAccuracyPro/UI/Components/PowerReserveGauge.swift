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
                ConceptGlyph(systemName: "timer", size: 12, color: gaugeColor)
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

/// 스마트워치 배터리 배지 — 완충 N일 기준 경과 시간으로 산출한 잔량(%)을 배터리 아이콘+숫자로.
/// percent == nil(완충일 미설정) 이면 "—". compact = 리스트 행용(배경 없는 인라인).
struct SmartwatchBatteryBadge: View {
    let percent: Int?
    var compact: Bool = false

    private var pct: Int { max(0, min(100, percent ?? 0)) }
    private var icon: String {
        switch pct {
        case 0..<13:  return "battery.0"
        case 13..<38: return "battery.25"
        case 38..<63: return "battery.50"
        case 63..<88: return "battery.75"
        default:      return "battery.100"
        }
    }
    private var tone: Color {
        if pct <= 15 { return AppColors.danger }
        if pct <= 35 { return AppColors.warning }
        return AppColors.success
    }

    var body: some View {
        HStack(spacing: compact ? 4 : 5) {
            ConceptGlyph(systemName: icon, size: compact ? 13 : 14)
                .accessibilityHidden(true)
            Text(percent == nil ? "—" : "\(pct)%")
                .font(.system(size: compact ? 12 : 11, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(tone)
        .modifier(BatteryBadgeChrome(compact: compact, tone: tone))
        .accessibilityLabel(percent == nil
            ? String(localized: "misc.battery.a11y.unset")
            : String(format: String(localized: "misc.battery.a11y.percent"), pct))
    }
}

private struct BatteryBadgeChrome: ViewModifier {
    let compact: Bool
    let tone: Color
    func body(content: Content) -> some View {
        if compact {
            content
        } else {
            content
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(tone.opacity(0.12))
                .overlay(Capsule().stroke(tone.opacity(0.35), lineWidth: 1))
                .clipShape(Capsule())
        }
    }
}
