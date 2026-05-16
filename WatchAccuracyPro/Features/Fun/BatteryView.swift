import SwiftData
import SwiftUI

/// Screen 20 — Quartz Battery 모니터 (독립 화면).
/// WatchDetail의 careSection batteryCard 과 동일 데이터, 더 큰 시각화.
struct BatteryView: View {
    @Query(sort: \Watch.createdAt, order: .reverse) private var allWatches: [Watch]
    @State private var activeId: PersistentIdentifier?

    private var quartzWatches: [Watch] {
        allWatches.filter { $0.movementType == .quartz }
    }

    private var active: Watch? {
        if let id = activeId, let w = quartzWatches.first(where: { $0.persistentModelID == id }) {
            return w
        }
        return quartzWatches.first
    }

    var body: some View {
        Group {
            if quartzWatches.isEmpty {
                emptyState
            } else if let active {
                content(for: active)
            }
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .navigationTitle(String(localized: "battery.nav.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "battery.0percent")
                .font(.system(size: 56))
                .foregroundStyle(AppColors.accent.opacity(0.5))
            Text(String(localized: "battery.empty"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.ink0)
            Text(String(localized: "battery.empty.hint"))
                .font(.system(size: 13))
                .foregroundStyle(AppColors.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(for watch: Watch) -> some View {
        let lastChange = watch.batteryLastReplaced ?? watch.createdAt
        let lifespanDays = watch.batteryExpectedLifeMonths * 30
        let daysSince = max(0, Calendar.current.dateComponents([.day], from: lastChange, to: Date()).day ?? 0)
        let remainingDays = max(0, lifespanDays - daysSince)
        let pct: Double = lifespanDays > 0
            ? max(0, min(100, 100 - (Double(daysSince) / Double(lifespanDays)) * 100))
            : 100
        let expires = Calendar.current.date(byAdding: .day, value: lifespanDays, to: lastChange) ?? Date()

        return ScrollView {
            VStack(spacing: 14) {
                watchChips
                heroGauge(watch: watch, pct: pct)
                timelineCard(changed: lastChange, expires: expires, daysSince: daysSince, pct: pct)
                insightCard(pct: pct, watch: watch)
                actions(watch: watch, daysSince: daysSince, remaining: remainingDays)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 80)
        }
    }

    private var watchChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quartzWatches, id: \.persistentModelID) { w in
                    let isActive = (active?.persistentModelID == w.persistentModelID)
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        activeId = w.persistentModelID
                    } label: {
                        Text("\(w.brand) · \(w.model)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isActive ? .white : AppColors.ink0)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .frame(minHeight: 44)
                            .background(isActive ? AppColors.primaryDeep : AppColors.paper2)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(isActive ? AppColors.primaryDeep : AppColors.rule, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
        }
    }

    private func heroGauge(watch: Watch, pct: Double) -> some View {
        let health: (color: Color, label: String) = {
            switch pct {
            case 60...: return (AppColors.success, String(localized: "battery.status.good"))
            case 25..<60: return (AppColors.warning, String(localized: "battery.status.warn"))
            default: return (AppColors.danger, String(localized: "battery.status.low"))
            }
        }()
        return VStack(spacing: 14) {
            batteryCellSVG(pct: pct, color: health.color)
            Text("\(Int(pct))")
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.ink0)
                + Text("%")
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColors.ink2)
            HStack(spacing: 6) {
                Circle().fill(health.color).frame(width: 6, height: 6)
                Text(health.label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(health.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(health.color.opacity(0.13))
            .clipShape(Capsule())

            VStack(spacing: 2) {
                Text("\(watch.brand) \(watch.model)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                Text(String(format: String(localized: "battery.caliber_life"), watch.caliber ?? "-", watch.batteryExpectedLifeMonths))
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.ink2)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(format: NSLocalizedString("a11y.battery.gauge", comment: ""), Int(pct), health.label, watch.brand, watch.model)))
    }

    private func batteryCellSVG(pct: Double, color: Color) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.ink0, lineWidth: 2.5)
                .frame(width: 200, height: 80)
            HStack(spacing: 0) {
                Spacer().frame(width: 200)
                Rectangle()
                    .fill(AppColors.ink0)
                    .frame(width: 8, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            // UX 감사: danger 색상 정의 강화 — opacity gradient + 외곽선 0.5pt.
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [color, color.opacity(0.65)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.85), lineWidth: 0.5))
                .frame(width: max(8, (pct / 100) * 188), height: 64)
                .padding(.leading, 6)
        }
        .frame(width: 208, height: 84)
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
                Text(AppDateFormat.shortMonthDay(changed))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.ink2)
                Spacer()
                Text(String(localized: "battery.today"))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.primaryDeep)
                Spacer()
                Text(AppDateFormat.shortMonthDay(expires))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.danger)
            }

            HStack(spacing: 8) {
                kv(String(localized: "battery.kv.last"), value: AppDateFormat.shortMonthDay(changed))
                kv(String(localized: "battery.kv.elapsed"), value: "\(daysSince)d", accent: true)
                kv(String(localized: "battery.kv.due"), value: AppDateFormat.shortMonthDay(expires))
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

    private func insightCard(pct: Double, watch: Watch) -> some View {
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

    @Environment(\.modelContext) private var modelContext

    private func actions(watch: Watch, daysSince: Int, remaining: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                watch.batteryLastReplaced = Date()
                try? modelContext.save()
                if watch.batteryReminderEnabled {
                    NotificationService.scheduleBatteryReminder(for: watch)
                }
            } label: {
                Text(String(localized: "battery.replace.recorded"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColors.primaryDeep)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
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

#Preview {
    NavigationStack { BatteryView() }
        .modelContainer(for: [Watch.self], inMemory: true)
}
