import SwiftData
import SwiftUI

/// Screen 24 — Brand League.
/// 전체 TickLab 사용자 기반 글로벌 브랜드 착용 랭킹 (Supabase).
struct BrandLeagueView: View {
    @Query private var watches: [Watch]
    @Query(sort: \WearLog.date, order: .reverse) private var wearLogs: [WearLog]
    @StateObject private var service = SupabaseBrandLeagueService.shared
    @State private var period: Period = .week

    // MARK: - Period

    enum Period: String, CaseIterable {
        case day, week, month, year
        var label: String {
            switch self {
            case .day:   return String(localized: "league.period.day")
            case .week:  return String(localized: "league.period.week")
            case .month: return String(localized: "league.period.month")
            case .year:  return String(localized: "league.period.year")
            }
        }
        var supabaseType: String { rawValue }
    }

    // MARK: - Brand color

    private static let BRAND_COLOR: [String: Color] = [
        "Rolex":       Color(red: 0.0,   green: 0.376, blue: 0.224),
        "Omega":       Color(red: 0.639, green: 0.0,   blue: 0.0),
        "Seiko":       Color(red: 0.0,   green: 0.231, blue: 0.478),
        "Grand Seiko": Color(red: 0.451, green: 0.0,   blue: 0.137),
        "Tudor":       Color(red: 0.545, green: 0.0,   blue: 0.0),
        "Cartier":     Color(red: 0.69,  green: 0.0,   blue: 0.173),
        "Tissot":      Color(red: 0.741, green: 0.039, blue: 0.039),
        "Hamilton":    Color(red: 0.0,   green: 0.231, blue: 0.502),
        "Breitling":   Color(red: 0.831, green: 0.6,   blue: 0.0),
        "IWC":         Color(red: 0.122, green: 0.220, blue: 0.392),
        "TAG Heuer":   Color(red: 0.812, green: 0.0,   blue: 0.0),
        "Citizen":     Color(red: 0.0,   green: 0.341, blue: 0.62),
        "Oris":        Color(red: 0.51,  green: 0.157, blue: 0.137),
        "JLC":         Color(red: 0.122, green: 0.220, blue: 0.392),
        "Patek":       Color(red: 0.545, green: 0.435, blue: 0.165),
        "AP":          Color(red: 0.10,  green: 0.10,  blue: 0.10),
    ]

    private static func brandColor(_ brand: String) -> Color {
        if let c = BRAND_COLOR[brand] { return c }
        // DB에 없는 브랜드: 브랜드명 해시 기반 고정 색상
        let hue = Double(brand.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFFFFFF }) / Double(Int.max)
        return Color(hue: hue.truncatingRemainder(dividingBy: 1.0),
                     saturation: 0.6, brightness: 0.45)
    }

    // MARK: - My data

    private var myTeam: String? {
        // 가장 많이 착용한 브랜드
        var counts: [String: Int] = [:]
        for log in wearLogs { if let b = log.watch?.brand { counts[b, default: 0] += 1 } }
        return counts.max(by: { $0.value < $1.value })?.key ?? watches.first?.brand
    }

    private var myCountForPeriod: [String: Int] {
        let cutoff: Date = {
            let cal = Calendar.current; let now = Date()
            switch period {
            case .day:   return cal.startOfDay(for: now)
            case .week:  return cal.date(byAdding: .day,   value: -7,  to: now) ?? now
            case .month: return cal.date(byAdding: .month, value: -1,  to: now) ?? now
            case .year:  return cal.date(byAdding: .year,  value: -1,  to: now) ?? now
            }
        }()
        var dict: [String: Int] = [:]
        for log in wearLogs.filter({ $0.date >= cutoff }) {
            if let b = log.watch?.brand { dict[b, default: 0] += 1 }
        }
        return dict
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                tabRow
                if service.isLoading && service.globalRanking.isEmpty {
                    loadingView
                } else if service.globalRanking.isEmpty {
                    emptyState
                } else {
                    newsCard
                    if service.globalRanking.count >= 2 { podium }
                    if let team = myTeam { myTeamCard(brand: team) }
                    rankingSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 80)
            .padding(.top, 12)
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .navigationTitle(String(localized: "league.nav.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: period.rawValue) {
            await service.fetchRanking(periodType: period.supabaseType)
        }
        .task(id: wearLogs.count) {
            await service.uploadBrandCounts(computedBrandCounts())
            await service.fetchRanking(periodType: period.supabaseType)
        }
        .refreshable {
            await service.uploadBrandCounts(computedBrandCounts())
            await service.fetchRanking(periodType: period.supabaseType)
        }
    }

    // MARK: - Tab

    private var tabRow: some View {
        HStack(spacing: 6) {
            ForEach(Period.allCases, id: \.self) { p in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.easeOut(duration: 0.15)) { period = p }
                } label: {
                    Text(p.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(period == p ? .white : AppColors.ink0)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(period == p ? AppColors.primaryDeep : AppColors.paper2)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(period == p ? .isSelected : [])
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(AppColors.accent)
                .scaleEffect(1.2)
            Text(String(localized: "league.loading"))
                .font(.system(size: 13))
                .foregroundStyle(AppColors.ink3)
        }
        .padding(60)
    }

    // MARK: - Empty

    private var emptyState: some View {
        EmptyState(
            icon: "chart.bar.xaxis",
            title: String(localized: "league.empty.title"),
            message: service.lastError != nil
                ? String(localized: "league.error.body")
                : String(localized: "league.empty.body")
        )
    }

    // MARK: - News Card

    private var newsCard: some View {
        let top    = service.globalRanking.first
        let second = service.globalRanking.dropFirst().first
        return HStack(alignment: .top, spacing: 12) {
            Circle().fill(AppColors.accent).frame(width: 36, height: 36)
                .overlay(Image(systemName: "megaphone.fill")
                    .font(.system(size: 15)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(period.label) \(String(localized: "league.news.suffix"))".uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2).foregroundStyle(AppColors.accentDark)
                if let top {
                    if let second, second.totalCount > 0 {
                        let ratio = String(format: "%.1f", Double(top.totalCount) / Double(second.totalCount))
                        Text(String(format: NSLocalizedString("league.news.headline", comment: ""),
                                    top.brand, period.label, second.brand, ratio))
                            .font(.system(size: 14)).foregroundStyle(AppColors.ink0)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(String(format: NSLocalizedString("league.news.solo", comment: ""),
                                    top.brand, period.label, top.totalCount))
                            .font(.system(size: 14)).foregroundStyle(AppColors.ink0)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(LinearGradient(colors: [AppColors.accent50, .white],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.accentLight, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Podium

    // 메달 색상 — 동점이면 브랜드 고유 색상 사용
    private static let gold   = Color(red: 0.85, green: 0.70, blue: 0.22)
    private static let silver = Color(red: 0.70, green: 0.70, blue: 0.72)
    private static let bronze = Color(red: 0.72, green: 0.45, blue: 0.20)

    private var podium: some View {
        let arr = service.globalRanking
        let n = min(arr.count, 3)
        guard n >= 1 else { return AnyView(EmptyView()) }

        // 동점 여부 계산 — 동일 count 면 같은 rank
        let ranks: [Int] = (0..<n).map { i in
            var r = 1
            for j in 0..<i { if arr[j].totalCount > arr[i].totalCount { r += 1 } }
            return r
        }
        let allTied = Set(ranks).count == 1

        // 포디움 배치: [2위, 1위, 3위] 순서
        let podiumIndices: [Int] = n >= 3 ? [1, 0, 2] : n == 2 ? [1, 0] : [0]
        let barHeights: [CGFloat] = [100, 130, 80]
        let displayRanks = [2, 1, 3]

        return AnyView(
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(podiumIndices.enumerated()), id: \.offset) { slot, dataIdx in
                    let b = arr[dataIdx]
                    let actualRank = ranks[dataIdx]
                    // 높이 = 순위 기준 (동점이면 동일 높이)
                    let barHeight: CGFloat = {
                        switch actualRank {
                        case 1: return 130
                        case 2: return 100
                        default: return 80
                        }
                    }()

                    // 순위별 바 색상 — 동점이면 브랜드 색, 구분이면 금/은/동
                    let barColor: Color = {
                        if allTied { return Self.brandColor(b.brand) }
                        switch displayRanks[slot] {
                        case 1: return Self.gold
                        case 2: return Self.silver
                        default: return Self.bronze
                        }
                    }()

                    VStack(spacing: 4) {
                        brandInitialBadge(b.brand, color: Self.brandColor(b.brand), size: 36)
                        Text(b.brand)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColors.ink0)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(format(b.totalCount))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppColors.ink2)
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [barColor, barColor.opacity(0.75)],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .frame(maxWidth: .infinity)
                            .frame(height: barHeight)
                            .overlay(
                                trophyView(rank: actualRank)
                            )
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 6)
        )
    }

    // MARK: - My Team Card

    private func myTeamCard(brand: String) -> some View {
        let arr  = service.globalRanking
        let idx  = arr.firstIndex(where: { $0.brand == brand })
        let rank = (idx ?? arr.count) + 1
        let globalCount = idx.map { arr[$0].totalCount } ?? 0
        let myCount = myCountForPeriod[brand] ?? 0
        return HStack(spacing: 12) {
            brandInitialBadge(brand, color: Self.brandColor(brand), size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "league.myteam"))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2).foregroundStyle(AppColors.accentDark)
                Text(String(format: NSLocalizedString("league.myteam.rank_value", comment: ""), brand, rank))
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(AppColors.ink0)
                HStack(spacing: 8) {
                    Label("\(myCount)\(String(localized: "league.myteam.my_count"))",
                          systemImage: "person.fill")
                        .font(.system(size: 11)).foregroundStyle(AppColors.ink2)
                    Text("·").foregroundStyle(AppColors.ink3)
                    Label(format(globalCount) + String(localized: "league.myteam.global_count"),
                          systemImage: "globe")
                        .font(.system(size: 11)).foregroundStyle(AppColors.ink2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(LinearGradient(colors: [AppColors.accent50.opacity(0.6), .white],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.accent, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Ranking Section

    /// Round 15 (Doyoon): 기존 O(N²) per-row rank 계산 → 단일 패스로 precompute.
    /// 50 brand 기준 2500 비교 → 50 비교 (50x 감소).
    private var precomputedRanks: [Int] {
        let arr = service.globalRanking
        guard !arr.isEmpty else { return [] }
        var ranks = [Int](repeating: 1, count: arr.count)
        var currentRank = 1
        for i in 1..<arr.count {
            if arr[i].totalCount < arr[i - 1].totalCount {
                currentRank = i + 1
            }
            ranks[i] = currentRank
        }
        return ranks
    }

    private var rankingSection: some View {
        let ranks = precomputedRanks
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "league.ranking.all"))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2).foregroundStyle(AppColors.ink2)
                Spacer()
                if service.isLoading {
                    ProgressView().scaleEffect(0.7).tint(AppColors.accent)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(service.globalRanking.enumerated()), id: \.element.brand) { i, b in
                    let isMyTeam = myTeam == b.brand
                    let rank: Int = i < ranks.count ? ranks[i] : (i + 1)
                    HStack(spacing: 12) {
                        Text("\(rank)")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(i < 3 ? AppColors.accentDark : AppColors.ink3)
                            .frame(width: 22, alignment: .center)
                        brandInitialBadge(b.brand, color: Self.brandColor(b.brand), size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(b.brand)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.ink0)
                            if isMyTeam {
                                Text(String(localized: "league.myteam.badge"))
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(1)
                                    .foregroundStyle(AppColors.accentDark)
                            }
                        }
                        Spacer()
                        Text(format(b.totalCount))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColors.ink0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(isMyTeam ? AppColors.accent50 : .clear)
                    if i < service.globalRanking.count - 1 {
                        Divider().padding(.leading, 68)
                    }
                }
            }
            .background(AppColors.paper1)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            // 마지막 업데이트 시각
            if let cached = service.rankingCache["\(period.rawValue)_\(SupabaseBrandLeagueService.periodKey(type: period.rawValue))"] {
                Text(String(format: NSLocalizedString("league.last_updated", comment: ""),
                             cached.at.formatted(.relative(presentation: .named))))
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.ink3)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func trophyView(rank: Int) -> some View {
        let color: Color = rank == 1 ? Self.gold : rank == 2 ? Self.silver : Self.bronze
        return Image(systemName: "trophy.fill")
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }

    // MARK: - Brand Count Computation (뷰 레벨에서 직접 계산 — @Query 관계 로딩 보장)

    private func computedBrandCounts() -> [(brand: String, type: String, key: String, count: Int)] {
        let now = Date()
        let cal = Calendar.current
        let periods: [(type: String, cutoff: Date)] = [
            ("day",   cal.startOfDay(for: now)),
            ("week",  cal.date(byAdding: .day,   value: -7,  to: now) ?? now),
            ("month", cal.date(byAdding: .month, value: -1,  to: now) ?? now),
            ("year",  cal.date(byAdding: .year,  value: -1,  to: now) ?? now),
        ]
        var result: [(brand: String, type: String, key: String, count: Int)] = []
        for (pt, cutoff) in periods {
            let pk = SupabaseBrandLeagueService.periodKey(type: pt, date: now)
            var brandCounts: [String: Int] = [:]
            // @Query wearLogs 에서 직접 집계 — 이 뷰 레벨에서는 watch?.brand 가 정확
            for log in wearLogs where log.date >= cutoff {
                if let brand = log.watch?.brand, !brand.isEmpty {
                    brandCounts[brand, default: 0] += 1
                }
            }
            for (brand, count) in brandCounts {
                result.append((brand: brand, type: pt, key: pk, count: count))
            }
        }
        return result
    }

    // MARK: - Helpers

    private func brandInitialBadge(_ brand: String, color: Color, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(color)
            Text(String(brand.prefix(2)).uppercased())
                .font(.system(size: size * 0.32, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private func format(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000     { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
}

#Preview {
    NavigationStack { BrandLeagueView() }
        .modelContainer(for: [Watch.self, WearLog.self], inMemory: true)
}
