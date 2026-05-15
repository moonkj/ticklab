import SwiftData
import SwiftUI
import Charts

/// TickLab v3 Tab 3 — Stats.
/// Phase 1: donut by mood + 자세별 평균 rate. Phase 2.5: trends.
struct StatsView: View {
    @Environment(\.modelContext) private var modelContext
    // Round 146 (Doyoon/Hyemi): @Query sort 명시 — 결정론적 순서.
    @Query(sort: \WatchMeasurement.timestamp, order: .reverse) private var measurements: [WatchMeasurement]
    @Query(sort: \JournalEntry.timestamp, order: .reverse) private var journalEntries: [JournalEntry]
    @Query(sort: \WearLog.date, order: .reverse) private var wearLogs: [WearLog]
    @Query(sort: \Watch.createdAt, order: .reverse) private var watches: [Watch]
    /// Round 119 (이재현 High): per-watch position breakdown — 선택한 시계만 필터링.
    @State private var selectedWatchForPosition: Watch?

    /// Round 176: RootTabView 가 주입하는 NavigationStack path. 탭 재선택 시 외부에서 리셋됨.
    private let externalPath: Binding<NavigationPath>?
    @State private var localPath = NavigationPath()
    private var pathBinding: Binding<NavigationPath> {
        externalPath ?? $localPath
    }

    init(path: Binding<NavigationPath>? = nil) {
        self.externalPath = path
    }

    var body: some View {
        NavigationStack(path: pathBinding) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 업적·브랜드리그 진입 카드 최상단 배치.
                    funEntryCards
                    summaryCards
                    wearChartSection
                    cumulativeWearSection
                    moodDonut
                    averageRateSection
                }
                .padding(20)
            }
            .background(AppColors.paper0.ignoresSafeArea())
            // 헤더 톤 통일 (BadgesView/BrandLeagueView 와 동일하게 inline 타이틀).
            .navigationTitle(String(localized: "stats.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.paper0, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
        }
    }

    /// 와이어프레임 Section E — Stats 에서 진입하는 두 카드 (업적 / 리그).
    private var funEntryCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                NavigationLink {
                    BadgesView()
                } label: {
                    funEntryCard(emoji: "🏆",
                                 title: String(localized: "stats.entry.badges"),
                                 subtitle: String(localized: "stats.entry.badges.subtitle"),
                                 tint: AppColors.accent.opacity(0.18))
                }
                .buttonStyle(.plain)
                NavigationLink {
                    BrandLeagueView()
                } label: {
                    funEntryCard(emoji: "📣",
                                 title: String(localized: "stats.entry.league"),
                                 subtitle: String(localized: "stats.entry.league.subtitle"),
                                 tint: AppColors.info.opacity(0.18))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func funEntryCard(emoji: String, title: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(emoji).font(.system(size: 26))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.ink0)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.ink2)
            HStack {
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AppColors.ink2)
            }
        }
        .padding(14)
        // Round 169: minHeight 120→132 (chevron 과 subtitle 간 spacing 확보).
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(LinearGradient(colors: [tint, AppColors.paper1],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Round 120 — 착용 통계 (디자인 SSOT Pivot Journey axis).

    private var wearChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                EyebrowLabel(text: String(localized: "stats.wear.last14days"))
                Spacer()
                Text(String(format: NSLocalizedString("stats.wear.total_days", comment: ""), wearLogs.count))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.ink2)
            }
            let series = WearLogService.dailyCounts(days: 14, in: modelContext)
            if series.allSatisfy({ $0.count == 0 }) {
                Text(String(localized: "stats.wear.empty"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink2)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(series, id: \.date) { item in
                    BarMark(
                        x: .value("Day", item.date, unit: .day),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(AppColors.accent.gradient)
                    .cornerRadius(4)
                }
                .frame(height: 120)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 3)) { value in
                        AxisValueLabel(format: .dateTime.day().month(), centered: true)
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
                .chartYAxis(.hidden)
            }
        }
        .padding(14)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    private var cumulativeWearSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: String(localized: "stats.wear.cumulative.title"))
            let cumulative = WearLogService.cumulativeByWatch(in: modelContext)
            if cumulative.isEmpty {
                Text(String(localized: "stats.wear.cumulative.empty"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink2)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 6) {
                    ForEach(cumulative.prefix(5), id: \.watch.id) { row in
                        HStack(spacing: 12) {
                            Group {
                                if let img = PhotoCache.image(for: row.watch.id, data: row.watch.photoData) {
                                    Image(uiImage: img).resizable().scaledToFill()
                                } else {
                                    WatchSilhouette(watch: row.watch, size: 36)
                                }
                            }
                            .frame(width: 36, height: 36)
                            .background(AppColors.paper2)
                            .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.watch.model)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppColors.ink0)
                                Text(row.watch.brand)
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppColors.ink2)
                            }
                            Spacer()
                            Text("\(row.days)일")
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppColors.accent)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppColors.paper1)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(
                title: String(localized: "stats.total_measurements"),
                value: "\(measurements.count)",
                accent: AppColors.accent
            )
            summaryCard(
                title: String(localized: "stats.total_entries"),
                value: "\(journalEntries.count)",
                accent: AppColors.primaryDeep
            )
        }
    }

    private func summaryCard(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(AppColors.ink2)
            Text(value)
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .foregroundStyle(accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    // MARK: - Mood donut
    /// Round 167: '이번 달' 텍스트가 카피만이고 실제로는 전체 기간 카운트하던 문제 → 실제 월 필터링.
    private var thisMonthEntries: [JournalEntry] {
        let cal = Calendar.current
        let now = Date()
        return journalEntries.filter {
            cal.isDate($0.timestamp, equalTo: now, toGranularity: .month)
        }
    }

    private var moodDonut: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: String(localized: "stats.mood_breakdown"))
            if thisMonthEntries.isEmpty {
                Text(String(localized: "stats.empty.mood"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink3)
                    .padding(.vertical, 30)
                    .frame(maxWidth: .infinity)
            } else {
                ZStack {
                    Chart(moodCounts(), id: \.mood) { item in
                        SectorMark(
                            angle: .value("Count", item.count),
                            innerRadius: .ratio(0.6)
                        )
                        .foregroundStyle(colorForMood(item.mood))
                        .annotation(position: .overlay) {
                            Text(item.mood.emoji)
                                .font(.system(size: 14))
                        }
                    }
                    VStack(spacing: 2) {
                        Text(String(localized: "stats.mood.this_month"))
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(2)
                            .foregroundStyle(AppColors.ink2)
                        Text("\(thisMonthEntries.count)")
                            .font(.system(size: 28, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppColors.ink0)
                        Text(String(localized: "stats.total_entries"))
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.ink2)
                    }
                }
                .frame(height: 220)
                .padding(.vertical, 6)
            }
        }
    }

    private struct MoodCount { let mood: Mood; let count: Int }
    private func moodCounts() -> [MoodCount] {
        let groups = Dictionary(grouping: thisMonthEntries, by: { $0.mood })
        return groups.map { MoodCount(mood: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    /// Round 59: 6가지 mood color 색약 친화 — Okabe-Ito 팔레트 일부 차용 + 시각 명도 차이 확대.
    private func colorForMood(_ mood: Mood) -> Color {
        switch mood {
        case .happy:      return AppColors.accent                                  // gold
        case .proud:      return AppColors.primaryDeep                             // dark indigo (강한 대비)
        case .curious:    return Color(red: 0.0, green: 0.620, blue: 0.451)        // bluish-green (Okabe-Ito)
        case .neutral:    return AppColors.ink3                                    // light gray (was ink2 too dark)
        case .concerned:  return Color(red: 0.835, green: 0.369, blue: 0.0)        // vermillion (Okabe-Ito)
        case .nostalgic:  return Color(red: 0.337, green: 0.706, blue: 0.914)      // sky blue (Okabe-Ito)
        }
    }

    // MARK: - 평균 오차
    // 사용자 요청: 6포지션별 표시 제거, 전체(또는 선택 시계) 평균 rate 단일 카드로 통합.
    // 자세별 데이터는 SwiftData 에 그대로 저장되며 UI에서만 숨김.
    private var averageRateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                EyebrowLabel(text: String(localized: "stats.average_rate.title"))
                Spacer()
                // Round 119 (이재현 High): per-watch picker — 유지.
                if watches.count >= 2 {
                    Picker(String(localized: "stats.position.watch_picker"), selection: $selectedWatchForPosition) {
                        Text(String(localized: "stats.position.all")).tag(Watch?.none)
                        ForEach(watches) { w in
                            Text(w.nickname ?? w.model).tag(Watch?.some(w))
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                }
            }
            let summary = averageRateSummary()
            if summary.count == 0 {
                Text(String(localized: "stats.empty.positions"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink3)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            } else {
                averageRateCard(rate: summary.average, count: summary.count)
            }
        }
    }

    private struct AverageRateSummary { let average: Double; let count: Int }
    private func averageRateSummary() -> AverageRateSummary {
        let filtered = selectedWatchForPosition.map { w in
            measurements.filter { $0.watch?.id == w.id }
        } ?? measurements
        guard !filtered.isEmpty else { return AverageRateSummary(average: 0, count: 0) }
        let mean = filtered.map { $0.rateSecondsPerDay }.reduce(0, +) / Double(filtered.count)
        return AverageRateSummary(average: mean, count: filtered.count)
    }

    private func averageRateCard(rate: Double, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(formatRate(rate))
                .font(.system(size: 40, weight: .medium, design: .monospaced))
                .foregroundStyle(rateColor(rate))
            Text(String(format: NSLocalizedString("stats.average_rate.subtitle", comment: ""), count))
                .font(.system(size: 12))
                .foregroundStyle(AppColors.ink2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    private func rateColor(_ r: Double) -> Color {
        let a = abs(r)
        if a <= 6 { return AppColors.success }
        if a <= 20 { return AppColors.warning }
        return AppColors.danger
    }
}
