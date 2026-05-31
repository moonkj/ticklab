import SwiftData
import SwiftUI

/// Sprint 6 (P3-9): 글로벌 컬렉션 분석 — 브랜드 리그와 차별화된 "나 vs 글로벌" 비교 인사이트.
///
/// BrandLeagueView 차이:
///   - 경쟁/순위 게임이 아닌 패턴 분석 화면
///   - 내 착용 비율 vs 글로벌 점유율 비교
///   - % 점유율 표시 (카운트 아닌 비중)
///   - "내 브랜드는 글로벌 몇 위?" 개인화 인사이트
///   - 로컬 무브먼트 타입 분포 (Supabase 없이 온디바이스)
struct GlobalAnalyticsView: View {
    @StateObject private var service = SupabaseBrandLeagueService.shared
    @Query(sort: \Watch.createdAt) private var watches: [Watch]
    @Query(sort: \WearLog.date, order: .reverse) private var wearLogs: [WearLog]
    @State private var period: SupabaseBrandLeagueService.PeriodType = .month

    private var totalGlobalWears: Int { service.globalRanking.map(\.totalCount).reduce(0, +) }

    // 내 이번 기간 착용 수 (로컬)
    private var myWears: Int {
        let cutoff = periodCutoff
        return wearLogs.filter { $0.date >= cutoff }.count
    }

    private var periodCutoff: Date {
        let cal = Calendar.current; let now = Date()
        switch period {
        case .day:   return cal.startOfDay(for: now)
        case .month: return cal.date(byAdding: .month, value: -1, to: now) ?? now
        case .year:  return cal.date(byAdding: .year,  value: -1, to: now) ?? now
        }
    }

    // 내 컬렉션 브랜드들의 글로벌 순위
    private var myBrands: Set<String> { Set(watches.map(\.brand)) }

    private var myBrandRankings: [(brand: String, rank: Int, share: Double)] {
        let total = totalGlobalWears
        return service.globalRanking
            .enumerated()
            .filter { myBrands.contains($0.element.brand) }
            .map { i, row in
                let share = total > 0 ? Double(row.totalCount) / Double(total) * 100 : 0
                return (brand: row.brand, rank: i + 1, share: share)
            }
    }

    // 온디바이스 무브먼트 타입 분포
    private var movementDistribution: [(type: WatchMovementType, count: Int)] {
        var counts: [WatchMovementType: Int] = [:]
        for w in watches { counts[w.movementType, default: 0] += 1 }
        return WatchMovementType.allCases
            .map { (type: $0, count: counts[$0] ?? 0) }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 기간 피커
                Picker("Period", selection: $period) {
                    Text(String(localized: "league.period.day")).tag(SupabaseBrandLeagueService.PeriodType.day)
                    Text(String(localized: "league.period.month")).tag(SupabaseBrandLeagueService.PeriodType.month)
                    Text(String(localized: "league.period.year")).tag(SupabaseBrandLeagueService.PeriodType.year)
                }
                .pickerStyle(.segmented)

                // 나 vs 글로벌 비교 카드
                if totalGlobalWears > 0 {
                    vsCard
                }

                // 글로벌 브랜드 점유율 (% 기반)
                if service.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                } else if service.globalRanking.isEmpty {
                    EmptyState(icon: "chart.bar",
                               title: String(localized: "analytics.empty.title"),
                               message: String(localized: "analytics.empty"))
                } else {
                    globalShareSection
                }

                // 내 컬렉션 브랜드 글로벌 순위 (개인화)
                if !myBrandRankings.isEmpty {
                    myBrandsSection
                }

                // 온디바이스 무브먼트 타입 분포 (로컬 데이터)
                if !movementDistribution.isEmpty {
                    movementSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 40)
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .navigationTitle(String(localized: "analytics.nav.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: period.rawValue) {
            await service.fetchRanking(periodType: period.rawValue)
        }
        .refreshable {
            await service.fetchRanking(periodType: period.rawValue)
        }
    }

    // MARK: - 나 vs 글로벌

    private var vsCard: some View {
        HStack(spacing: 0) {
            vsColumn(
                label: String(localized: "analytics.vs.me"),
                value: "\(myWears)",
                unit: String(localized: "analytics.vs.unit"),
                color: AppColors.accentDark
            )
            Divider().frame(height: 60)
            vsColumn(
                label: String(localized: "analytics.vs.global"),
                value: formatCount(totalGlobalWears),
                unit: String(localized: "analytics.vs.unit"),
                color: AppColors.ink2
            )
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func vsColumn(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(AppColors.ink3)
            Text(value)
                // 타이포 SSOT: 숫자=monospaced 통일 (이전 rounded → mono).
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(unit)
                .font(.caption)
                .foregroundStyle(AppColors.ink3)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 글로벌 브랜드 점유율 (%)

    private var globalShareSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(String(localized: "analytics.share.title"),
                          sub: String(localized: "analytics.share.subtitle"))
            ForEach(Array(service.globalRanking.prefix(7).enumerated()), id: \.element.brand) { i, row in
                let share = totalGlobalWears > 0 ? Double(row.totalCount) / Double(totalGlobalWears) * 100 : 0
                let isMine = myBrands.contains(row.brand)
                shareBar(rank: i + 1, brand: row.brand, share: share, highlight: isMine)
            }
            Text(String(format: NSLocalizedString("analytics.disclaimer", comment: ""), service.globalRanking.count))
                .font(.caption2)
                .foregroundStyle(AppColors.ink3)
        }
        .padding(16)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func shareBar(rank: Int, brand: String, share: Double, highlight: Bool) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(rank <= 3 ? AppColors.accentDark : AppColors.ink3)
                .frame(width: 20, alignment: .center)
            Text(brand)
                .font(.system(size: 13, weight: highlight ? .bold : .regular))
                .foregroundStyle(highlight ? AppColors.accentDark : AppColors.ink0)
                .frame(width: 90, alignment: .leading)
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.paper2).frame(height: 10)
                    Capsule()
                        .fill(highlight
                            ? LinearGradient(colors: [AppColors.accent, AppColors.accentDark],
                                             startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [AppColors.ink3.opacity(0.5), AppColors.ink3.opacity(0.3)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * CGFloat(share / 100)), height: 10)
                }
            }
            .frame(height: 10)
            Text(String(format: "%.1f%%", share))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(highlight ? AppColors.accentDark : AppColors.ink3)
                .frame(width: 44, alignment: .trailing)
        }
    }

    // MARK: - 내 컬렉션 브랜드 글로벌 순위

    private var myBrandsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(String(localized: "analytics.mybrands.title"),
                          sub: String(localized: "analytics.mybrands.subtitle"))
            ForEach(myBrandRankings, id: \.brand) { item in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.success)
                        .font(.system(size: 14))
                    Text(item.brand)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.ink0)
                    Spacer()
                    Text(String(format: NSLocalizedString("analytics.mybrands.rank", comment: ""), item.rank))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.accentDark)
                    Text(String(format: "%.1f%%", item.share))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppColors.ink3)
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(colors: [AppColors.accent50, AppColors.paper1],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.accent.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 온디바이스 무브먼트 타입 분포

    private var movementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(String(localized: "analytics.movement.title"),
                          sub: String(localized: "analytics.movement.subtitle"))
            let total = movementDistribution.map(\.count).reduce(0, +)
            ForEach(movementDistribution, id: \.type) { item in
                let pct = total > 0 ? Double(item.count) / Double(total) * 100 : 0
                HStack(spacing: 10) {
                    Text(item.type.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.ink0)
                        .frame(width: 70, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(AppColors.paper2).frame(height: 10)
                            Capsule()
                                .fill(AppColors.accentDark.opacity(0.7))
                                .frame(width: max(6, geo.size.width * CGFloat(pct / 100)), height: 10)
                        }
                    }
                    .frame(height: 10)
                    Text("\(item.count)개 (\(Int(pct))%)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppColors.ink3)
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.ink0)
            Text(sub)
                .font(.caption)
                .foregroundStyle(AppColors.ink3)
        }
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

extension SupabaseBrandLeagueService {
    enum PeriodType: String, CaseIterable {
        case day, month, year
    }
}
