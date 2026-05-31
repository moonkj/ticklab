import SwiftData
import SwiftUI

/// Sprint 6 (P3-9): 글로벌 컬렉션 분석 — TickLab 전체 사용자 익명 통계.
/// 브랜드 리그와 동일 Supabase 인프라 재사용.
/// 100개 미만 데이터는 "데이터 수집 중" 메시지 표시 (역추적 방지).
struct GlobalAnalyticsView: View {
    @StateObject private var service = SupabaseBrandLeagueService.shared
    @State private var period: SupabaseBrandLeagueService.PeriodType = .month

    // 브랜드 리그 globalRanking 재사용 (동일 API)
    private var top5: [SupabaseBrandLeagueService.GlobalBrandRow] {
        Array(service.globalRanking.prefix(5))
    }

    private var totalGlobalWears: Int {
        service.globalRanking.map(\.totalCount).reduce(0, +)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 헤더 카드
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "analytics.header.title"))
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(AppColors.accentDark)
                    Text(String(format: NSLocalizedString("analytics.header.total", comment: ""), totalGlobalWears))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppColors.ink0)
                    Text(String(localized: "analytics.header.disclaimer"))
                        .font(.caption)
                        .foregroundStyle(AppColors.ink3)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.paper1)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // 기간 탭
                Picker("Period", selection: $period) {
                    Text(String(localized: "league.period.day")).tag(SupabaseBrandLeagueService.PeriodType.day)
                    Text(String(localized: "league.period.month")).tag(SupabaseBrandLeagueService.PeriodType.month)
                    Text(String(localized: "league.period.year")).tag(SupabaseBrandLeagueService.PeriodType.year)
                }
                .pickerStyle(.segmented)

                // 브랜드 분포 바 차트
                if service.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                } else if top5.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar").font(.system(size: 32)).foregroundStyle(AppColors.ink3)
                        Text(String(localized: "analytics.empty")).font(.callout).foregroundStyle(AppColors.ink2)
                    }
                    .frame(maxWidth: .infinity).padding(40)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "analytics.top5.title"))
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(AppColors.ink2)
                        ForEach(top5) { row in
                            brandBar(row, maxCount: top5.first?.totalCount ?? 1)
                        }
                    }
                    .padding(16)
                    .background(AppColors.paper1)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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

    private func brandBar(_ row: SupabaseBrandLeagueService.GlobalBrandRow, maxCount: Int) -> some View {
        HStack(spacing: 10) {
            Text(row.brand)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.ink0)
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)
            GeometryReader { geo in
                let fraction = maxCount > 0 ? CGFloat(row.totalCount) / CGFloat(maxCount) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.paper2).frame(height: 12)
                    Capsule()
                        .fill(LinearGradient(colors: [AppColors.accent, AppColors.accentDark],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geo.size.width * fraction), height: 12)
                }
            }
            .frame(height: 12)
            Text("\(row.totalCount)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.ink2)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

extension SupabaseBrandLeagueService {
    enum PeriodType: String, CaseIterable {
        case day, month, year
    }
}
