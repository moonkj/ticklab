import SwiftData
import SwiftUI

/// Sprint 4 (P2-17): TickLab Wrapped — 연간 리포트 슬라이드쇼.
///
/// Round 174 (UX 재설계): Spotify Wrapped 급 몰입형 스토리텔링.
/// 페르소나 도출 결과로 페이지 재구성 —
///   표지 → 착용량(데이터 너드) → 최애 시계 → 브랜드/컬렉션(컬렉터)
///   → 착용 패턴(요일·달·streak, 데이터 너드) → 정확도(워치메이커)
///   → 추억·태그(캐주얼) → 마무리.
/// 테마: 남색 배경(primaryDeep) + 흰 텍스트 풀스크린 카드. 페이지별 gradient accent 로 고급화.
struct WrappedView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var page: Int = 0
    @State private var data: WrappedReportData?
    @State private var appeared = false

    private let year: Int

    init(year: Int = Calendar.current.component(.year, from: Date())) {
        self.year = year
    }

    var body: some View {
        ZStack {
            AppColors.primaryDeep.ignoresSafeArea()
            if let data {
                TabView(selection: $page) {
                    coverPage(data).tag(0)
                    wearsPage(data).tag(1)
                    watchPage(data).tag(2)
                    collectionPage(data).tag(3)
                    patternPage(data).tag(4)
                    measurePage(data).tag(5)
                    memoriesPage(data).tag(6)
                    closingPage(data).tag(7)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .animation(.easeInOut(duration: 0.35), value: page)
            } else {
                ProgressView().tint(.white)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // Round 173 (사용자 보고): 상단 nav 바를 본문 남색(primaryDeep)과 통일 — 흰 배경에 흰 버튼이 안 보이던 문제 해소.
        .toolbarBackground(AppColors.primaryDeep, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.8))
                        .font(.system(size: 22))
                }
            }
        }
        .task {
            // 무거운 집계는 generate 에서 1회만 — 페이지 전환은 순수 렌더링이라 60fps 유지.
            data = WrappedReportData.generate(year: year, context: context)
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    // MARK: - Pages

    /// 표지 — 다이얼 글로우 + 연도.
    private func coverPage(_ d: WrappedReportData) -> some View {
        wrappedCard(glow: AppColors.accent) {
            VStack(spacing: 18) {
                Text("⌚")
                    .font(.system(size: 72))
                    .shadow(color: AppColors.accent.opacity(0.6), radius: 24)
                EyebrowWhite(String(localized: "wrapped.cover.eyebrow"))
                Text(String(format: NSLocalizedString("wrapped.cover.title", comment: ""), d.year))
                    .font(.system(size: 40, weight: .black, design: .serif))
                    .italic()
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(String(localized: "wrapped.cover.subtitle"))
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                Text(String(localized: "wrapped.cover.swipe"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 12)
            }
        }
    }

    /// 착용량 — 큰 숫자 + 총 착용일(데이터 너드).
    private func wearsPage(_ d: WrappedReportData) -> some View {
        wrappedCard(glow: AppColors.info) {
            VStack(spacing: 14) {
                statLabel(String(localized: "wrapped.wears.label"))
                bigNumber("\(d.totalWears)")
                Text(String(localized: "wrapped.wears.unit"))
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.8))
                if d.totalWearDays > 0 {
                    metricRow(
                        icon: "calendar",
                        label: String(localized: "wrapped.weardays.label"),
                        value: String(format: NSLocalizedString("wrapped.weardays.value", comment: ""), d.totalWearDays)
                    )
                }
            }
        }
    }

    /// 최애 시계 — 가장 많이 찬 시계 + 신규 영입.
    private func watchPage(_ d: WrappedReportData) -> some View {
        wrappedCard(glow: AppColors.accent) {
            VStack(spacing: 14) {
                if let most = d.mostWornWatch {
                    statLabel(String(localized: "wrapped.mostworn.label"))
                    Text(most.watch.brand)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.accentLight)
                    Text(most.watch.model)
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    bigNumber("\(most.count)")
                    Text(String(localized: "wrapped.wears.unit"))
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    emptyHint("wrapped.empty.wears")
                }
                if d.newWatchesAdded > 0 {
                    metricRow(
                        icon: "sparkles",
                        label: String(localized: "wrapped.newwatches.label"),
                        value: String(format: NSLocalizedString("wrapped.newwatches.value", comment: ""), d.newWatchesAdded)
                    )
                }
            }
        }
    }

    /// 컬렉션/브랜드 다양성 (컬렉터 페르소나).
    private func collectionPage(_ d: WrappedReportData) -> some View {
        wrappedCard(glow: AppColors.accentDark) {
            VStack(spacing: 14) {
                statLabel(String(localized: "wrapped.brands.label"))
                bigNumber("\(d.brandCount)")
                Text(String(localized: "wrapped.brands.unit"))
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.8))
                if let top = d.topBrand {
                    Divider().background(.white.opacity(0.25)).padding(.vertical, 6)
                    statLabel(String(localized: "wrapped.topbrand.label"))
                    Text(top.name)
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundStyle(AppColors.accent)
                        .multilineTextAlignment(.center)
                }
                if d.brandCount == 0 { emptyHint("wrapped.empty.wears") }
            }
        }
    }

    /// 착용 패턴 — 요일/달/streak (데이터 너드 페르소나).
    private func patternPage(_ d: WrappedReportData) -> some View {
        wrappedCard(glow: AppColors.primary500) {
            VStack(spacing: 18) {
                EyebrowWhite(String(localized: "wrapped.pattern.eyebrow"))
                if let wd = d.topWeekday {
                    bigText(Self.weekdayName(wd.weekday))
                    statLabel(String(localized: "wrapped.topweekday.label"))
                }
                Divider().background(.white.opacity(0.25)).padding(.vertical, 2)
                HStack(spacing: 28) {
                    if let bm = d.busiestMonth {
                        miniStat(
                            value: Self.monthName(bm.month),
                            label: String(localized: "wrapped.busiest.label")
                        )
                    }
                    if d.longestStreak > 0 {
                        miniStat(
                            value: String(format: NSLocalizedString("wrapped.streak.value", comment: ""), d.longestStreak),
                            label: String(localized: "wrapped.streak.label")
                        )
                    }
                }
                if d.topWeekday == nil && d.busiestMonth == nil { emptyHint("wrapped.empty.wears") }
            }
        }
    }

    /// 정확도 (워치메이커 페르소나) — 가장 정확한 시계 + 평균 rate + COSC 통과.
    private func measurePage(_ d: WrappedReportData) -> some View {
        wrappedCard(glow: AppColors.success) {
            VStack(spacing: 14) {
                statLabel(String(localized: "wrapped.measurements.label"))
                bigNumber("\(d.totalMeasurements)")
                if let best = d.bestAccuracyWatch {
                    Divider().background(.white.opacity(0.25)).padding(.vertical, 4)
                    statLabel(String(localized: "wrapped.bestaccuracy.label"))
                    Text(best.watch.model)
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(String(format: "%+.1f s/d", best.avgRate))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(abs(best.avgRate) <= 6 ? AppColors.success : AppColors.warning)
                }
                if let avg = d.avgRateSecondsPerDay {
                    HStack(spacing: 28) {
                        miniStat(
                            value: String(format: "%+.1f", avg),
                            label: String(localized: "wrapped.avgrate.label")
                        )
                        if d.totalMeasurements > 0 {
                            miniStat(
                                value: "\(d.coscPassCount)",
                                label: String(localized: "wrapped.cosc.label")
                            )
                        }
                    }
                    .padding(.top, 6)
                }
                if d.totalMeasurements == 0 { emptyHint("wrapped.empty.measure") }
            }
        }
    }

    /// 추억·태그 (캐주얼 생활기록러 페르소나).
    private func memoriesPage(_ d: WrappedReportData) -> some View {
        wrappedCard(glow: AppColors.accentLight) {
            VStack(spacing: 16) {
                Text("✨").font(.system(size: 44))
                if d.highlightCount > 0 {
                    statLabel(String(localized: "wrapped.highlights.label"))
                    bigNumber("\(d.highlightCount)")
                    Text(String(localized: "wrapped.highlights.unit"))
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.75))
                }
                if !d.tagBreakdown.isEmpty {
                    Divider().background(.white.opacity(0.25)).padding(.vertical, 4)
                    statLabel(String(localized: "wrapped.toptag.label"))
                    tagChips(d.tagBreakdown)
                }
                if d.highlightCount == 0 && d.tagBreakdown.isEmpty { emptyHint("wrapped.empty.memories") }
            }
        }
    }

    /// 마무리 — 내년 기대 + 공유 유도.
    private func closingPage(_ d: WrappedReportData) -> some View {
        wrappedCard(glow: AppColors.accent) {
            VStack(spacing: 16) {
                Text("🎉").font(.system(size: 56))
                Text(String(format: NSLocalizedString("wrapped.closing.title", comment: ""), d.year + 1))
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .italic()
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(String(localized: "wrapped.closing.subtitle"))
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                ShareLink(item: shareSummary(d)) {
                    Label(String(localized: "wrapped.share.button"), systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.primaryDeep)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(.white)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
                Text("TickLab")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Reusable subviews

    private func metricRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.55))
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 8)
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 26, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
    }

    /// 태그 비중 칩 — 상위 3개를 횟수와 함께 표시.
    private func tagChips(_ tags: [(tag: String, count: Int)]) -> some View {
        let maxCount = max(tags.first?.count ?? 1, 1)
        return VStack(spacing: 8) {
            ForEach(Array(tags.prefix(3).enumerated()), id: \.offset) { _, item in
                HStack(spacing: 10) {
                    Text(WearTag.displayName(for: item.tag))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 90, alignment: .leading)
                    GeometryReader { geo in
                        Capsule()
                            .fill(AppColors.accent)
                            .frame(width: max(8, geo.size.width * CGFloat(item.count) / CGFloat(maxCount)))
                    }
                    .frame(height: 10)
                    Text("\(item.count)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 28, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: 280)
    }

    private func emptyHint(_ key: String.LocalizationValue) -> some View {
        Text(String(localized: key))
            .font(.system(size: 15))
            .foregroundStyle(.white.opacity(0.65))
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }

    // MARK: - Helpers

    /// 페이지 카드 — 상단에 은은한 radial glow 로 페이지별 색 personality 부여.
    private func wrappedCard<Content: View>(glow: Color, @ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            RadialGradient(
                colors: [glow.opacity(0.35), .clear],
                center: .top, startRadius: 0, endRadius: 380
            )
            .ignoresSafeArea()
            VStack {
                Spacer()
                content()
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
        }
    }

    private func bigNumber(_ text: String) -> some View {
        Text(text)
            // 타이포 SSOT: 숫자=monospaced 통일.
            .font(.system(size: 76, weight: .black, design: .monospaced))
            .foregroundStyle(.white)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }

    private func bigText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 44, weight: .black, design: .serif))
            .foregroundStyle(.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }

    private func statLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(2)
            .foregroundStyle(.white.opacity(0.6))
    }

    /// 흰색 eyebrow — gold tick + 대문자 라벨.
    private struct EyebrowWhite: View {
        let text: String
        init(_ text: String) { self.text = text }
        var body: some View {
            HStack(spacing: 8) {
                Rectangle().fill(AppColors.accent).frame(width: 18, height: 1)
                Text(text.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.75))
                Rectangle().fill(AppColors.accent).frame(width: 18, height: 1)
            }
        }
    }

    // MARK: - Formatting helpers

    /// Calendar.weekday(1=일...7=토) → 현지화 요일명.
    private static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.standaloneWeekdaySymbols   // index 0 = 일요일
        let idx = (weekday - 1) % symbols.count
        return symbols.indices.contains(idx) ? symbols[idx] : "\(weekday)"
    }

    /// 1...12 → 현지화 월명.
    private static func monthName(_ month: Int) -> String {
        let symbols = Calendar.current.standaloneMonthSymbols
        let idx = month - 1
        return symbols.indices.contains(idx) ? symbols[idx] : "\(month)"
    }

    /// 공유 텍스트 — 측정값 미포함의 가벼운 요약 (사용자 주도 공유, Hard Rule #8 결과 카드와 동일 성격).
    private func shareSummary(_ d: WrappedReportData) -> String {
        var lines: [String] = []
        lines.append(String(format: NSLocalizedString("wrapped.cover.title", comment: ""), d.year))
        lines.append(String(format: NSLocalizedString("wrapped.share.wears", comment: ""), d.totalWears))
        if let most = d.mostWornWatch {
            lines.append(String(format: NSLocalizedString("wrapped.share.fav", comment: ""), "\(most.watch.brand) \(most.watch.model)"))
        }
        lines.append("— TickLab")
        return lines.joined(separator: "\n")
    }
}

#Preview {
    NavigationStack {
        WrappedView()
            .modelContainer(for: [Watch.self, WatchMeasurement.self, WearLog.self], inMemory: true)
    }
}
