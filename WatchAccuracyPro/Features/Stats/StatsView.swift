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
    /// 평균 rate 요약 숫자 Dynamic Type 대응 — 기준값=기존 40pt → 기본 설정 변화 없음, 큰글씨만 확대.
    @ScaledMetric(relativeTo: .largeTitle) private var avgRateSize: CGFloat = 40
    /// Round 119 (이재현 High): per-watch position breakdown — 선택한 시계만 필터링.
    @State private var selectedWatchForPosition: Watch?

    /// Round (4): cumulativeByWatch 캐시 — body 매 render 마다 SwiftData full scan + group 하던 hotspot 차단.
    @State private var cachedCumulativeByWatch: [(watch: Watch, days: Int)] = []
    /// 사용자 요청: 착용 그리드 보고 있는 달 — 좌/우 화살표로 변경. 기본은 이번 달.
    @State private var wearMonthAnchor: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    /// 사용자 보고 fix: wearCount(on:) 가 cell 마다 O(N) 스캔 — 365 logs × 35 cells = 12k+ 비교/render.
    ///   startOfDay 기준 dict 으로 pre-compute. wearLogs.count 또는 anchor 변경 시 refresh.
    @State private var wearCountByDay: [Date: Int] = [:]
    /// 누적 착용 랭킹 더보기 토글 — 첫 진입 시 5개만 표시.
    @State private var cumulativeExpanded = false
    private static let cumulativePageSize = 5

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
            VStack(spacing: 0) {
                // 고정 헤더 — 스크롤되지 않는 최상단 제목 영역(4탭 통일).
                editorialHeader
                ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 사용자가 의도적으로 funEntryCards (업적/브랜드 리그) 를 상단에 배치한 기존 순서 유지.
                    funEntryCards
                    summaryCards
                    averageRateSection
                    analysisSection
                    wearChartSection
                    cumulativeWearSection
                    moodDonut
                }
                .padding(20)
                .readableContentWidth()   // iPad 가로폭 제한(아이폰 무영향)
                }
            }
            .background(AppColors.paper0.ignoresSafeArea())
            // 제목을 제일 상단으로 — 내비바 숨김(에디토리얼 헤더가 최상단). 4탭 통일.
            .toolbar(.hidden, for: .navigationBar)
            // Round (4): wearLogs 변화 시에만 무거운 fetch + group 재계산. body re-render 마다 fetch 차단.
            .onAppear { refreshWearStats() }
            .onChange(of: wearLogs.count) { _, _ in refreshWearStats() }
        }
    }

    private func refreshWearStats() {
        cachedCumulativeByWatch = WearLogService.cumulativeByWatch(in: modelContext)
        let cal = Calendar.current
        var dict: [Date: Int] = [:]
        for log in wearLogs {
            let key = cal.startOfDay(for: log.date)
            dict[key, default: 0] += 1
        }
        wearCountByDay = dict
    }

    private var editorialHeader: some View {
        EditorialPageHeader(
            eyebrow: String(localized: "stats.eyebrow.figures"),
            title: String(localized: "stats.title"),
            subtitle: String(localized: "stats.subtitle"),
            showGear: true
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// Sprint 12 (UX4): IA 2그룹화 — "내 기록" / "커뮤니티". 글로벌분석은 브랜드리그로 흡수.
    private var funEntryCards: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ── 그룹 1: 내 기록 ──
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "stats.group.mine"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(AppColors.ink3)
                HStack(spacing: 10) {
                    NavigationLink { BadgesView() } label: {
                        funEntryCard(emoji: "🏆",
                                     title: String(localized: "stats.entry.badges"),
                                     subtitle: String(localized: "stats.entry.badges.subtitle"),
                                     tint: AppColors.accent.opacity(0.18), fillHeight: true,
                                     symbol: "trophy.fill", symbolColor: AppColors.accent)
                    }.buttonStyle(.plain)
                    NavigationLink { HighlightTimelineView() } label: {
                        funEntryCard(emoji: "⭐",
                                     title: String(localized: "stats.entry.highlights"),
                                     subtitle: String(localized: "stats.entry.highlights.subtitle"),
                                     tint: AppColors.warning.opacity(0.15), fillHeight: true,
                                     symbol: "star.fill", symbolColor: AppColors.warning)
                    }.buttonStyle(.plain)
                }
                NavigationLink { WrappedView() } label: {
                    funEntryCard(emoji: "🎁",
                                 title: String(localized: "stats.entry.wrapped"),
                                 subtitle: String(localized: "stats.entry.wrapped.subtitle"),
                                 tint: Color.purple.opacity(0.15),
                                 symbol: "gift", symbolColor: .purple)
                }.buttonStyle(.plain)
            }

            // ── 그룹 2: 커뮤니티 ── (브랜드리그=글로벌분석 통합, 뉴스)
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "stats.group.community"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(AppColors.ink3)
                HStack(spacing: 10) {
                    // 브랜드리그 진입 → 내부에 글로벌분석 세그먼트 포함 (통합).
                    NavigationLink { BrandLeagueView() } label: {
                        funEntryCard(emoji: "🏅",
                                     title: String(localized: "stats.entry.league"),
                                     subtitle: String(localized: "stats.entry.community.subtitle"),
                                     tint: AppColors.info.opacity(0.18), fillHeight: true,
                                     symbol: "medal", symbolColor: AppColors.info)
                    }.buttonStyle(.plain)
                    NavigationLink { BrandNewsView() } label: {
                        funEntryCard(emoji: "📰",
                                     title: String(localized: "stats.entry.news"),
                                     subtitle: String(localized: "stats.entry.news.subtitle"),
                                     tint: Color.orange.opacity(0.15), fillHeight: true,
                                     symbol: "newspaper", symbolColor: .orange)
                    }.buttonStyle(.plain)
                    // 큐레이션 YouTube 영상 — 백엔드(curated_channels) 준비 후 플래그 ON.
                    if FeatureFlags.shared.videoFeedEnabled {
                        NavigationLink { VideoFeedView() } label: {
                            funEntryCard(emoji: "▶️",
                                         title: String(localized: "stats.entry.videos"),
                                         subtitle: String(localized: "stats.entry.videos.subtitle"),
                                         tint: Color.red.opacity(0.14), fillHeight: true,
                                         symbol: "play.rectangle.fill", symbolColor: .red)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// 웨이브2-C: 채도 높은 타일 → 단일 악센트의 절제된 톤(mono eyebrow + 단색 글리프 + hairline).
    /// 골드는 hero 1개에만 — 여기선 차분한 paper 표면. 순서·존재·진입은 그대로(사용자 의도).
    /// `tint` 는 글리프/eyebrow 단색 악센트로만 사용(이전엔 카드 배경 채도였음).
    private func funEntryCard(emoji: String, title: String, subtitle: String, tint: Color, fillHeight: Bool = false, symbol: String? = nil, symbolColor: Color = AppColors.ink0) -> some View {
        // tint 는 이미 저채도(.opacity 적용된 값) — 글리프 칩 배경으로 그대로 재사용.
        return VStack(alignment: .leading, spacing: 8) {
            // 단색 글리프 — 차분한 원형 칩 안에 둠.
            ZStack {
                Circle()
                    .fill(tint)
                    .frame(width: 38, height: 38)
                if let symbol {
                    ConceptGlyph(systemName: symbol, size: 21, color: symbolColor)
                } else {
                    Text(emoji).font(.system(size: 20))
                }
            }
            // mono eyebrow + 세리프 톤 타이틀.
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.ink0)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.ink2)
            Spacer(minLength: 6)
            HStack {
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.ink3)
            }
        }
        .padding(14)
        // Round 169: minHeight 120→132 (chevron 과 subtitle 간 spacing 확보).
        // fillHeight: HStack 행에서 형제 카드 중 가장 큰 높이로 늘려 박스 크기 통일.
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .cardShadow(.low)
    }

    // MARK: - Round 120 — 착용 통계 (디자인 SSOT Pivot Journey axis).

    /// 사용자 요청: 막대 차트 대신 선택한 달 칸이 채워지는 형태 — 날짜별 착용 횟수 heatmap.
    /// 좌/우 화살표로 달 이동, "이번 달" 버튼으로 빠르게 복귀.
    private var wearChartSection: some View {
        let monthInfo = monthDays(for: wearMonthAnchor)
        // 사용자 보고 fix: 이전엔 wear log 건수 합 (시계 10개면 같은 날 +10) → "121 일" 처럼 부풀려짐.
        //   "%d 일" 라벨 의미와 맞게 unique day 수로 변경.
        let uniqueWearDays = monthInfo.days.compactMap { $0 }.filter { wearCount(on: $0) > 0 }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                EyebrowLabel(text: String(localized: "stats.wear.section"))
                Spacer()
                Text(String(format: NSLocalizedString("stats.wear.total_days", comment: ""), uniqueWearDays))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.ink2)
            }
            monthNavigator
            if uniqueWearDays == 0 {
                Text(String(localized: "stats.wear.empty"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink2)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            } else {
                weekdayHeaderRow
                wearMonthGrid(days: monthInfo.days)
            }
        }
        .padding(14)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    /// 달 이동 헤더 — 좌 화살표 / 월 라벨 / 우 화살표.
    /// 우측 화살표는 이번 달이면 비활성 (미래 달 차단).
    private var monthNavigator: some View {
        let cal = Calendar.current
        let isCurrentMonth = cal.isDate(wearMonthAnchor, equalTo: Date(), toGranularity: .month)
        return HStack(spacing: 12) {
            Button {
                if let prev = cal.date(byAdding: .month, value: -1, to: wearMonthAnchor) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.easeOut(duration: 0.18)) { wearMonthAnchor = prev }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.ink2)
                    .frame(width: 32, height: 32)
                    .background(AppColors.paper2)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "stats.wear.prev_month"))

            VStack(spacing: 2) {
                Text(wearMonthAnchor, format: .dateTime.year().month(.wide))
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(AppColors.ink0)
                if !isCurrentMonth {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeOut(duration: 0.18)) {
                            wearMonthAnchor = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
                        }
                    } label: {
                        Text(String(localized: "stats.wear.jump_current"))
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(AppColors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                if let next = cal.date(byAdding: .month, value: 1, to: wearMonthAnchor) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.easeOut(duration: 0.18)) { wearMonthAnchor = next }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isCurrentMonth ? AppColors.ink3 : AppColors.ink2)
                    .frame(width: 32, height: 32)
                    .background(AppColors.paper2)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isCurrentMonth)
            .opacity(isCurrentMonth ? 0.4 : 1)
            .accessibilityLabel(String(localized: "stats.wear.next_month"))
            // 사용자 보고 fix: VoiceOver 가 "next month, dimmed" 만 읽음 → 비활성 사유 명시.
            .accessibilityHint(isCurrentMonth ? String(localized: "stats.wear.next_month.disabled_hint") : "")
        }
    }

    private var weekdayHeaderRow: some View {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 0) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, label in
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(AppColors.ink3)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func wearMonthGrid(days: [Date?]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    wearDayCell(day: day, count: wearCount(on: day))
                } else {
                    Color.clear.frame(height: 36)
                }
            }
        }
    }

    private func wearDayCell(day: Date, count: Int) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDate(day, inSameDayAs: Date())
        let dayNum = cal.component(.day, from: day)
        // count 0..N → opacity 0.18, 0.42, 0.66, 0.90 단계로 채움. 1 도 명확히 보이게.
        let fillOpacity: Double = {
            switch count {
            case 0:      return 0
            case 1:      return 0.30
            case 2:      return 0.55
            case 3:      return 0.78
            default:     return 0.95
            }
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.accent.opacity(fillOpacity))
            if isToday {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.primaryDeep, lineWidth: 1.5)
            }
            Text("\(dayNum)")
                .font(.system(size: 12, weight: count > 0 ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(count >= 3 ? .white : AppColors.ink0)
        }
        .frame(height: 36)
        // 사용자 보고 fix: heatmap intensity 가 VoiceOver 에 invisible — 날짜 + 착용 회수 명시.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(wearCellA11yLabel(day: day, count: count, isToday: isToday))
    }

    private func wearCellA11yLabel(day: Date, count: Int, isToday: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        let dateText = formatter.string(from: day)
        let todayPrefix = isToday ? String(localized: "stats.wear.a11y.today_prefix") + " " : ""
        if count == 0 {
            return todayPrefix + dateText + " — " + String(localized: "stats.wear.a11y.no_wear")
        }
        return todayPrefix + dateText + " — " + String(format: NSLocalizedString("stats.wear.a11y.count", comment: ""), count)
    }

    /// 주어진 anchor 가 속한 달의 1일 - 말일 모든 날짜. 1일 이전 요일 칸은 nil 패딩.
    private func monthDays(for anchor: Date) -> (days: [Date?], firstWeekdayOffset: Int) {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: anchor),
              let start = cal.date(from: cal.dateComponents([.year, .month], from: anchor)) else {
            return ([], 0)
        }
        let firstWeekday = cal.component(.weekday, from: start) - 1
        var days: [Date?] = Array(repeating: nil, count: firstWeekday)
        for d in range {
            if let date = cal.date(byAdding: .day, value: d - 1, to: start) {
                days.append(date)
            }
        }
        return (days, firstWeekday)
    }

    /// 특정 날짜의 착용 시계 개수 — pre-computed dict 에서 O(1) lookup.
    private func wearCount(on day: Date) -> Int {
        let key = Calendar.current.startOfDay(for: day)
        return wearCountByDay[key] ?? 0
    }

    private var cumulativeWearSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: String(localized: "stats.wear.cumulative.title"))
            let cumulative = cachedCumulativeByWatch
            if cumulative.isEmpty {
                Text(String(localized: "stats.wear.cumulative.empty"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink2)
                    .padding(.vertical, 10)
            } else {
                let displayCount = cumulativeExpanded ? cumulative.count : min(Self.cumulativePageSize, cumulative.count)
                let hasMore = cumulative.count > Self.cumulativePageSize
                VStack(spacing: 6) {
                    ForEach(Array(cumulative.prefix(displayCount)), id: \.watch.id) { row in
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
                            Text(String(format: NSLocalizedString("stats.wear.days_value", comment: ""), row.days))
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppColors.accent)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppColors.paper1)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    if hasMore {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { cumulativeExpanded.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Text(cumulativeExpanded
                                     ? String(localized: "common.collapse")
                                     : String(format: NSLocalizedString("common.show_more_count", comment: ""), cumulative.count - Self.cumulativePageSize))
                                    .font(.system(size: 13, weight: .semibold))
                                Image(systemName: cumulativeExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(AppColors.ink2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
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
        // Round 23 (Sora): thisMonthEntries 가 매 body re-render 마다 평가됨 + moodDonut 안에서 2번 사용
        //   + moodCounts() 가 또 호출 → Dictionary(grouping:) 폭주. 한 번만 평가하도록 let 으로 hoist.
        let monthly = thisMonthEntries
        let counts = monthly.isEmpty ? [] : Dictionary(grouping: monthly, by: { $0.mood })
            .map { MoodCount(mood: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
        return VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: String(localized: "stats.mood_breakdown"))
            if monthly.isEmpty {
                Text(String(localized: "stats.empty.mood"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink3)
                    .padding(.vertical, 30)
                    .frame(maxWidth: .infinity)
            } else {
                ZStack {
                    Chart(counts, id: \.mood) { item in
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
                        Text("\(monthly.count)")
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
                    // 사용자 보고 fix: 글로벌 indigo tint 가 menu chevron 까지 적용 → 라벨(gold) 와 색 어긋남.
                    .tint(AppColors.accent)
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
                averageRateCard(rate: summary.average, count: summary.count, stddev: summary.stddev)
            }
        }
    }

    private struct AverageRateSummary { let average: Double; let count: Int; let stddev: Double }
    private func averageRateSummary() -> AverageRateSummary {
        let filtered = selectedWatchForPosition.map { w in
            measurements.filter { $0.watch?.id == w.id }
        } ?? measurements
        guard !filtered.isEmpty else { return AverageRateSummary(average: 0, count: 0, stddev: 0) }
        let rates = filtered.map { $0.rateSecondsPerDay }
        let mean = rates.reduce(0, +) / Double(rates.count)
        // 사용자 보고 fix: "분석" 부제 promise vs 단순 평균 카드만 — 분산(stddev) chip 추가로 정보 밀도 ↑.
        let variance = rates.reduce(0.0) { acc, r in acc + (r - mean) * (r - mean) } / Double(rates.count)
        let stddev = variance.squareRoot()
        return AverageRateSummary(average: mean, count: filtered.count, stddev: stddev)
    }

    /// 웨이브2-C: figures-first hero — 큰 mono 카운터 + 골드 악센트 + 조용한 stddev 칩 + linen 여백.
    private func averageRateCard(rate: Double, count: Int, stddev: Double = 0) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 큰 mono 숫자 — CounterText 로 카운트업, rateColor 유지.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                CounterText(
                    value: rate,
                    format: "%+.1f",
                    font: .system(size: avgRateSize, weight: .medium, design: .monospaced)
                )
                .foregroundStyle(rateColor(rate))
                Text(String(localized: "unit.seconds_per_day"))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColors.accentDark)   // 골드 악센트(hero).
            }
            Text(String(format: NSLocalizedString("stats.average_rate.subtitle", comment: ""), count))
                .font(.system(size: 12))
                .foregroundStyle(AppColors.ink2)
            if count >= 2 {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 10))
                    Text(String(format: NSLocalizedString("stats.average_rate.stddev", comment: ""), stddev))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(AppColors.ink2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColors.paper2)
                .clipShape(Capsule())
                .padding(.top, 2)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxeCard(cornerRadius: AppRadius.lg)
    }

    private func rateColor(_ r: Double) -> Color {
        let a = abs(r)
        if a <= 6 { return AppColors.success }
        if a <= 20 { return AppColors.warning }
        return AppColors.danger
    }

    // MARK: - 스트림 D: 분석 (이상탐지 + AI 추세 요약)

    /// 분석 대상 시계 — picker 로 고른 시계가 있으면 그것, 없으면 가장 최근 측정의 시계.
    /// (averageRateSection 의 selectedWatchForPosition picker 와 자연스럽게 연동.)
    private var analysisWatch: Watch? {
        if let w = selectedWatchForPosition { return w }
        return measurements.first?.watch   // @Query 가 timestamp 역순 → 최신.
    }

    /// 선택된 시계의 측정만 시간순 필터. 분석 입력.
    private func measurements(for watch: Watch) -> [WatchMeasurement] {
        measurements.filter { $0.watch?.id == watch.id }
    }

    @ViewBuilder
    private var analysisSection: some View {
        if let watch = analysisWatch {
            let watchMeasurements = measurements(for: watch)
            VStack(alignment: .leading, spacing: 12) {
                if let anomaly = AnomalyDetector.detectLatest(measurements: watchMeasurements) {
                    AnomalyAlertCard(anomaly: anomaly)
                }
                if let metrics = TrendDiagnosisService.metrics(watch: watch, measurements: watchMeasurements) {
                    AITrendSummaryCard(watch: watch, metrics: metrics)
                }
            }
        }
    }
}

// MARK: - AnomalyAlertCard (StatsView 전용)

/// 단일 시계 이상탐지 결과 카드. 신규 측정이 과거 분포 대비 급변일 때만 표시.
/// StatsView 한정(다른 측정 화면 금지). 측정 데이터 외부 전송 0.
private struct AnomalyAlertCard: View {
    let anomaly: AnomalyDetector.Anomaly

    private var titleKey: String {
        switch anomaly.reason {
        case .suspectMagnetization:  return "anomaly.reason.magnetization.title"
        case .suspectShock:          return "anomaly.reason.shock.title"
        case .suspectBeatErrorSpike: return "anomaly.reason.beat_error.title"
        }
    }
    private var bodyKey: String {
        switch anomaly.reason {
        case .suspectMagnetization:  return "anomaly.reason.magnetization.body"
        case .suspectShock:          return "anomaly.reason.shock.body"
        case .suspectBeatErrorSpike: return "anomaly.reason.beat_error.body"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.warning)
                Text(String(localized: "anomaly.eyebrow"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(AppColors.accentDark)
                Spacer()
            }
            Text(String(localized: String.LocalizationValue(titleKey)))
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(AppColors.ink0)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: String.LocalizationValue(bodyKey)))
                .font(.system(size: 13))
                .foregroundStyle(AppColors.ink1)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            // 과거 평균 → 신규 측정 변화 요약 (사용자 friendly).
            Text(String(format: NSLocalizedString("anomaly.delta", comment: ""),
                        anomaly.baselineRate, anomaly.latestRate))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColors.ink2)
            Text(String(localized: "anomaly.disclaimer"))
                .font(.system(size: 10))
                .foregroundStyle(AppColors.ink3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.warning.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.warning.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - AITrendSummaryCard (StatsView 전용)

/// on-device AI 추세 요약 카드. TrendDiagnosisService.TrendMetrics → 1문단 자연어.
/// AppleIntelligenceVerdictService.trendVerdict 호출(가용 시), 불가/OFF 시 rule 폴백. 측정 데이터 외부 전송 0.
private struct AITrendSummaryCard: View {
    let watch: Watch
    let metrics: TrendDiagnosisService.TrendMetrics

    @Environment(UserPreferences.self) private var preferences
    @State private var verdict: AppleIntelligenceVerdictService.Verdict?
    @State private var isLoading = true

    private var isAI: Bool { verdict?.source == .appleIntelligence }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().scaleEffect(0.6)
                    Text(String(localized: "aitrend.source.loading"))
                } else {
                    Image(systemName: isAI ? "sparkles" : "chart.line.uptrend.xyaxis")
                        .font(.system(size: 10))
                    Text(String(localized: isAI ? "aitrend.source.ai" : "aitrend.source.rule"))
                }
                Spacer()
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(isAI ? AppColors.accentDark : AppColors.ink2)

            if let v = verdict {
                Text(v.headline)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(AppColors.ink0)
                    .fixedSize(horizontal: false, vertical: true)
                if !v.body.isEmpty {
                    Text(v.body)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.ink1)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if isLoading {
                Text(String(localized: "aitrend.loading.body"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink3)
            }
            Text(String(localized: isAI ? "aitrend.disclaimer.ai" : "aitrend.disclaimer.rule"))
                .font(.system(size: 10))
                .foregroundStyle(AppColors.ink3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        // metrics 또는 시계 변경 시 재로딩.
        .task(id: metrics) { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        let aiEnabled = preferences.aiVerdictEnabled
        // 5초 timeout — 무한 로딩 방지(AIDiagnosisCard 패턴).
        let verdictTask = Task { @MainActor in
            await AppleIntelligenceVerdictService.shared.trendVerdict(
                metrics: metrics, watch: watch, aiEnabled: aiEnabled
            )
        }
        let timeoutTask = Task { @MainActor () -> AppleIntelligenceVerdictService.Verdict in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            return AppleIntelligenceVerdictService.shared.ruleBasedTrendVerdict(metrics: metrics)
        }
        let v = await withTaskGroup(of: AppleIntelligenceVerdictService.Verdict.self) { group in
            group.addTask { await verdictTask.value }
            group.addTask { await timeoutTask.value }
            let first = await group.next()
                ?? AppleIntelligenceVerdictService.shared.ruleBasedTrendVerdict(metrics: metrics)
            group.cancelAll()
            verdictTask.cancel()
            timeoutTask.cancel()
            return first
        }
        verdict = v
        isLoading = false
    }
}
