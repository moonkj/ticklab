import SwiftData
import SwiftUI

/// Round 138 사용자 요청: 쿼츠 시계는 측정 무의미 → 측정 탭 자리에 배터리 모니터 표시.
/// BatteryView 의 핵심 카드 (hero gauge + timeline + insight + actions) 통합.
/// Round (잔여 분할): WatchDetailView 의 private struct 에서 별 파일로 분리 — 220 줄.
struct QuartzBatteryCard: View {
    @Bindable var watch: Watch
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        // Round 138 BUG FIX (사용자 보고: 교체 기록 버튼 동작 X):
        // @Bindable 로 watch.batteryLastReplaced 명시적 observe → 변경 시 body 재계산.
        let lastChange = watch.batteryLastReplaced ?? watch.createdAt
        let lifespanDays = max(1, watch.batteryExpectedLifeMonths * 30)
        let daysSince = max(0, Calendar.current.dateComponents([.day], from: lastChange, to: Date()).day ?? 0)
        let pct: Double = max(0, min(100, 100 - (Double(daysSince) / Double(lifespanDays)) * 100))
        let expires = Calendar.current.date(byAdding: .day, value: lifespanDays, to: lastChange) ?? Date()

        return VStack(spacing: 14) {
            heroGauge(pct: pct)
            timelineCard(changed: lastChange, expires: expires, daysSince: daysSince, pct: pct)
            insightCard(pct: pct)
            actions(daysSince: daysSince)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private func heroGauge(pct: Double) -> some View {
        let health: (Color, String) = {
            switch pct {
            case 60...: return (AppColors.success, String(localized: "battery.status.good"))
            case 25..<60: return (AppColors.warning, String(localized: "battery.status.warn"))
            default: return (AppColors.danger, String(localized: "battery.status.low"))
            }
        }()
        return VStack(spacing: 14) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColors.ink0, lineWidth: 2.5)
                    .frame(width: 200, height: 80)
                HStack(spacing: 0) {
                    Spacer().frame(width: 200)
                    Rectangle().fill(AppColors.ink0)
                        .frame(width: 8, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [health.0, health.0.opacity(0.65)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(health.0.opacity(0.85), lineWidth: 0.5))
                    .frame(width: max(8, (pct / 100) * 188), height: 64)
                    .padding(.leading, 6)
            }
            .frame(width: 208, height: 84)
            (Text("\(Int(pct))")
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.ink0)
                + Text("%")
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColors.ink2))
            HStack(spacing: 6) {
                Circle().fill(health.0).frame(width: 6, height: 6)
                Text(health.1).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(health.0)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(health.0.opacity(0.13))
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func timelineCard(changed: Date, expires: Date, daysSince: Int, pct: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "battery.timeline").uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(AppColors.ink2)
            GeometryReader { geo in
                let progress = 1 - (pct / 100)
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.paper2).frame(height: 6)
                    Capsule()
                        .fill(LinearGradient(colors: [AppColors.success, AppColors.warning, AppColors.danger],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(progress), height: 6)
                    Circle()
                        .fill(AppColors.primaryDeep)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .frame(width: 14, height: 14)
                        .offset(x: max(0, geo.size.width * CGFloat(progress) - 7))
                }
            }
            .frame(height: 14)
            .padding(.vertical, 8)
            HStack {
                Text(AppDateFormat.fullDate(changed))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.ink2)
                Spacer()
                Text(String(localized: "battery.today"))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.primaryDeep)
                Spacer()
                Text(AppDateFormat.fullDate(expires))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.danger)
            }
            HStack(spacing: 8) {
                kv(String(localized: "battery.kv.last"), value: AppDateFormat.fullDate(changed))
                kv(String(localized: "battery.kv.elapsed"), value: "\(daysSince)d", accent: true)
            }
        }
        .padding(14)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func kv(_ label: String, value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(AppColors.ink3)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(accent ? AppColors.accentDark : AppColors.ink0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(accent ? AppColors.accent50 : AppColors.paper2)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func insightCard(pct: Double) -> some View {
        let (icon, msg, color): (String, String, Color) = {
            if pct < 25 { return ("exclamationmark.triangle.fill", String(localized: "battery.insight.low"), AppColors.danger) }
            if pct < 60 { return ("clock.badge.exclamationmark", String(localized: "battery.insight.warn"), AppColors.warning) }
            return ("sparkles", String(localized: "battery.insight.ok"), AppColors.success)
        }()
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(pct < 25 ? String(localized: "battery.status.urgent")
                              : pct < 60 ? String(localized: "battery.status.caution")
                              : String(localized: "battery.status.ok"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(pct < 25 ? AppColors.danger.opacity(0.14) : AppColors.accent50)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func actions(daysSince: Int) -> some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(AppColors.primaryDeep)
                DatePicker(
                    String(localized: "watch.battery.last_replaced"),
                    selection: Binding(
                        get: { watch.batteryLastReplaced ?? Date() },
                        set: { newDate in
                            watch.batteryLastReplaced = newDate
                            try? modelContext.save()
                            if watch.batteryReminderEnabled {
                                NotificationService.scheduleBatteryReminder(for: watch)
                            }
                        }
                    ),
                    displayedComponents: .date
                )
                .font(.system(size: 14))
            }
            .padding(14)
            .background(AppColors.paper1)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                watch.batteryReminderEnabled.toggle()
                try? modelContext.save()
                if watch.batteryReminderEnabled {
                    NotificationService.scheduleBatteryReminder(for: watch)
                } else {
                    NotificationService.cancelBatteryReminder(for: watch)
                }
            } label: {
                Text(String(localized: watch.batteryReminderEnabled ? "battery.reminder.off" : "battery.reminder.on"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColors.paper2)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }
}
