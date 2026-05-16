import SwiftData
import SwiftUI
import UIKit

struct CollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(UserPreferences.self) private var preferences
    @Query(sort: \Watch.createdAt, order: .reverse) private var watches: [Watch]
    // WearLog 구독 — ShakePickView 등 외부에서 착용 기록 시 자동 재렌더링.
    @Query(sort: \WearLog.date, order: .reverse) private var wearLogs: [WearLog]
    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var showingWatchBox = false
    /// Round 113 (수익화 Critical): Pro 게이팅 - 무료 한계 초과 시 안내.
    @State private var showingProLimit = false
    /// shell-level paywall.
    @Environment(\.purchaseRouter) private var purchaseRouter
    /// 사용자 보고 fix: collectionSummary 가 body 마다 watches.measurements.max 호출 → 20시계×200측정=4k scan.
    ///   @State 캐시 + watches/measurement-change 시점에만 재계산.
    @State private var cachedSummary: (total: Int, healthy: Int, caution: Int, service: Int, fav: Int) = (0, 0, 0, 0, 0)
    /// Round 173: 컬렉션 카드에서 삭제 확인 alert.
    @State private var deletingWatch: Watch?
    /// Round 170: reorder sheet 표시.
    @State private var showingReorderSheet = false

    /// Round 176: RootTabView 가 주입하는 NavigationStack path. 탭 재선택 시 외부에서 리셋됨.
    /// nil 일 경우(프리뷰/스탠드얼론)에는 로컬 path 사용.
    private let externalPath: Binding<NavigationPath>?
    @State private var localPath = NavigationPath()
    private var pathBinding: Binding<NavigationPath> {
        externalPath ?? $localPath
    }

    init(path: Binding<NavigationPath>? = nil) {
        self.externalPath = path
    }

    /// 검색 query (power user 20+ 시계 대응).
    @State private var searchQuery: String = ""
    /// 즐겨찾기 필터.
    @State private var favoritesOnly: Bool = false

    /// Round 16 (Sora): row 마다 isWornToday fetch 폭주 차단. @Query wearLogs 에서
    ///   오늘자 (startOfDay) 인 watch.id 셋을 한 번 계산해 row 에 prop 으로 전달.
    private var wornTodayWatchIDs: Set<UUID> {
        let today = Calendar.current.startOfDay(for: Date())
        var ids: Set<UUID> = []
        for log in wearLogs where Calendar.current.startOfDay(for: log.date) == today {
            if let id = log.watch?.id { ids.insert(id) }
        }
        return ids
    }

    private var filtered: [Watch] {
        let sorted = watches.sorted { a, b in
            switch (a.sortOrder, b.sortOrder) {
            case let (sa?, sb?): return sa < sb
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.createdAt > b.createdAt
            }
        }
        // 검색·즐겨찾기 필터
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let searched: [Watch] = sorted.filter { w in
            if favoritesOnly && !w.isFavorite { return false }
            guard !q.isEmpty else { return true }
            return w.brand.lowercased().contains(q)
                || w.model.lowercased().contains(q)
                || (w.nickname?.lowercased().contains(q) ?? false)
                || (w.caliber?.lowercased().contains(q) ?? false)
        }
        if let primary = searched.first(where: { $0.isPrimary }) {
            return [primary] + searched.filter { $0.id != primary.id }
        }
        return searched
    }

    // Round 170: reorder 로직은 ReorderableWatchList 내부 localOrder 와 onCommit 으로 이전됨.

    /// 한 시계만 대표로 — 다른 시계의 isPrimary 는 false 로 reset.
    /// Round 19 (Min): Watch.setPrimary 헬퍼 호출 — invariant 통일.
    private func setPrimary(_ watch: Watch) {
        Watch.setPrimary(watch, in: modelContext)
    }

    var body: some View {
        NavigationStack(path: pathBinding) {
            ZStack {
                AppColors.paper0.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        if filtered.isEmpty {
                            emptyState
                        } else {
                            dashboardSummary
                            // Round 134: 대표시계 설정된 경우 — 상단 큰 카드로 별도 표시.
                            //            없으면 모든 시계가 동일 카드 형태로 리스트에 노출.
                            let primaryWatch = filtered.first(where: { $0.isPrimary })
                            let othersOnly = filtered.filter { !$0.isPrimary }
                            if let primary = primaryWatch {
                                // Round 170: padding 을 NavigationLink 외부로 → tap 영역이 visible card 만.
                                // 이전엔 .padding(.top, 8) 이 NavigationLink 안쪽에 있어서 위 8pt 도 tap 영역이었음.
                                NavigationLink(value: primary) {
                                    HeroWatchCard(watch: primary)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                                .contextMenu {
                                    Button {
                                        primary.isPrimary = false
                                        try? modelContext.save()
                                    } label: {
                                        Label(String(localized: "watch.primary.unset"), systemImage: "star.slash")
                                    }
                                    Button(role: .destructive) {
                                        deletingWatch = primary
                                    } label: {
                                        Label(String(localized: "common.delete"), systemImage: "trash")
                                    }
                                }
                            }
                            // Round 170: drag-reorder 인라인 폐기 (freeze 이슈). 단순 tap-only 카드.
                            // Reorder 는 별도 sheet 으로 분리 — 우상단 "순서 변경" 버튼.
                            if othersOnly.count >= 2 {
                                HStack {
                                    Spacer()
                                    Button {
                                        showingReorderSheet = true
                                    } label: {
                                        Label(String(localized: "collection.reorder"), systemImage: "arrow.up.arrow.down")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(AppColors.ink2)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(AppColors.paper1)
                                            .overlay(Capsule().stroke(AppColors.rule, lineWidth: 1))
                                            .clipShape(Capsule())
                                            .contentShape(Capsule())
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                            }
                            // Round 170: tap → detail, long-press → reorder sheet 열림.
                            // NavigationLink 가 long-press 가로채므로 Button 으로 명시 분리.
                            LazyVStack(spacing: 14) {
                                // Round 16 (Sora): row 마다 fetch 하지 않도록 wornTodayIds set 한 번 계산해서 주입.
                                let wornTodayIds = wornTodayWatchIDs
                                ForEach(othersOnly, id: \.id) { watch in
                                    WatchListRow(watch: watch, wornToday: wornTodayIds.contains(watch.id))
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            pathBinding.wrappedValue.append(watch)
                                        }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            // Round 62: 디자인 SSOT screens-main.jsx 의 "다음 도전" Founder-style card.
                            challengeCard
                                .padding(.horizontal, 20)
                                .padding(.top, 24)
                            footer
                        }
                    }
                }
            }
            .toolbar {
                // Round 163: 설정 버튼을 우측 끝으로 이동.
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingWatchBox = true
                        } label: {
                            Label(String(localized: "menu.watchbox"), systemImage: "shippingbox")
                        }
                        NavigationLink {
                            SpecCardListView()
                        } label: {
                            Label(String(localized: "menu.speccard"), systemImage: "rectangle.stack")
                        }
                        // Round 138 사용자 요청: 배터리 모니터 메뉴 제거 — 쿼츠 시계 detail 측정 탭에 통합되어 있음.
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(AppColors.ink1)
                    }
                    .accessibilityLabel(String(localized: "menu.watchbox"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if !preferences.isPro && watches.count >= ProEntitlement.freeWatchLimit {
                            showingProLimit = true
                        } else {
                            showingAdd = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppColors.paper0)
                            .frame(width: 32, height: 32)
                            .background(AppColors.ink0)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(String(localized: "collection.add_watch"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(AppColors.ink1)
                    }
                    .accessibilityLabel(String(localized: "tab.settings"))
                    .accessibilityIdentifier("nav.settings")
                }
            }
            .toolbarBackground(AppColors.paper0, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            // 검색 — 시계 20개+ 사용자 대응
            .searchable(text: $searchQuery,
                        placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: Text(String(localized: "collection.search.placeholder")))
            .sheet(isPresented: $showingWatchBox) {
                WatchBoxView()
            }
            .sheet(isPresented: $showingAdd) {
                AddWatchView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingReorderSheet) {
                ReorderSheet(
                    watches: filtered.filter { !$0.isPrimary },
                    onCommit: { newOrder in
                        for (idx, w) in newOrder.enumerated() {
                            w.sortOrder = Double(idx)
                        }
                        try? modelContext.save()
                    },
                    onSetPrimary: { setPrimary($0) },
                    onDelete: { deletingWatch = $0 }
                )
            }
            .navigationDestination(for: Watch.self) { watch in
                WatchDetailView(watch: watch)
            }
            // Round 113: Pro 게이팅 alert. Round 126: 업그레이드 CTA 추가.
            // 사용자 보고 fix: 업그레이드는 shell-level PurchaseRouter 로 위임 (4 분산 sheet 통합).
            .alert(String(localized: "pro.limit.watch.title"), isPresented: $showingProLimit) {
                Button(String(localized: "pro.limit.upgrade")) {
                    purchaseRouter?.intend(.watchLimit)
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "pro.limit.watch.body"))
            }
            .onAppear { refreshCollectionSummary() }
            .onChange(of: watches.count) { _, _ in refreshCollectionSummary() }
            // 측정 종료 시점에 최신 rate 반영 — body 매 render scan 제거.
            .onReceive(NotificationCenter.default.publisher(for: .ticklabMeasurementDidEnd)) { _ in
                refreshCollectionSummary()
            }
            // Round 173: 삭제 확인 alert — cascade 범위 사용자에게 알림.
            .alert(
                String(localized: "watch.delete.confirm.title"),
                isPresented: Binding(
                    get: { deletingWatch != nil },
                    set: { if !$0 { deletingWatch = nil } }
                ),
                presenting: deletingWatch
            ) { watch in
                Button(String(localized: "common.cancel"), role: .cancel) {
                    deletingWatch = nil
                }
                Button(String(localized: "common.delete"), role: .destructive) {
                    watch.deleteCascade(in: modelContext)
                    try? modelContext.save()
                    deletingWatch = nil
                }
            } message: { _ in
                Text(String(localized: "watch.delete.confirm.body"))
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "collection.eyebrow").uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(AppColors.ink2)
            Text(String(localized: "collection.title"))
                .font(.system(size: 38, weight: .medium, design: .serif).italic())
                .foregroundStyle(AppColors.ink0)
            Text(String(localized: "collection.subtitle"))
                .font(.system(size: 16, design: .serif).italic())
                .foregroundStyle(AppColors.ink2)
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // Round 170: 정렬 picker UI 제거 — 사용자 요청. 대신 카드 꾹 눌러 드래그로 순서 변경.

    private var recentEyebrow: some View {
        EyebrowLabel(text: String(localized: "collection.section.recent"), number: "01")
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    /// 페르소나 (이재현, 컬렉터) 피드백: 12개 컬렉션 dashboard.
    /// 한 줄로 "N개 중 X 정상 / Y 주의 / Z 서비스".
    /// Round 170 (사용자 요청): 클릭 시 filter 동작 제거 — 정보 표시만.
    private var dashboardSummary: some View {
        let counts = collectionSummary
        return Group {
            if counts.total >= 3 {
                HStack(spacing: 12) {
                    summaryItem(value: "\(counts.healthy)", label: NSLocalizedString("collection.status.ok", comment: ""), tone: .success)
                    Rectangle().fill(AppColors.rule).frame(width: 1, height: 18).accessibilityHidden(true)
                    summaryItem(value: "\(counts.caution)", label: NSLocalizedString("collection.status.caution", comment: ""), tone: .warning)
                    Rectangle().fill(AppColors.rule).frame(width: 1, height: 18).accessibilityHidden(true)
                    summaryItem(value: "\(counts.service)", label: NSLocalizedString("collection.status.service", comment: ""), tone: .danger)
                    if counts.fav > 0 {
                        Rectangle().fill(AppColors.rule).frame(width: 1, height: 18).accessibilityHidden(true)
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.easeOut(duration: 0.18)) { favoritesOnly.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: favoritesOnly ? "star.fill" : "star")
                                    .font(.system(size: 11))
                                    .foregroundStyle(favoritesOnly ? AppColors.accent : AppColors.ink1)
                                Text("\(counts.fav)")
                                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                                    .foregroundStyle(favoritesOnly ? AppColors.accent : AppColors.ink1)
                                Text("FAV")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .tracking(1.2)
                                    .foregroundStyle(AppColors.ink2)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(favoritesOnly ? AppColors.accent50 : Color.clear)
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "collection.filter.favorites_only"))
                    }
                    Spacer(minLength: 0)
                    Text("\(counts.total) WATCHES")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(AppColors.ink3)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(AppColors.paper1)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
    }

    private func summaryItem(value: String, label: String, tone: Chip.Tone) -> some View {
        let color: Color = {
            switch tone {
            case .success: return AppColors.success
            case .warning: return AppColors.warning
            case .danger:  return AppColors.danger
            default:       return AppColors.ink1
            }
        }()
        return HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(AppColors.ink2)
        }
    }

    private var collectionSummary: (total: Int, healthy: Int, caution: Int, service: Int, fav: Int) {
        cachedSummary
    }

    /// watches.count 또는 측정 종료 시점에만 재계산.
    private func refreshCollectionSummary() {
        var h = 0, c = 0, s = 0, f = 0
        for w in watches {
            if w.isFavorite { f += 1 }
            guard let last = w.measurements.max(by: { $0.timestamp < $1.timestamp }) else { continue }
            let absRate = abs(last.rateSecondsPerDay)
            if absRate <= 10 { h += 1 }
            else if absRate <= 20 { c += 1 }
            else { s += 1 }
        }
        cachedSummary = (watches.count, h, c, s, f)
    }

    // MARK: - Empty / Footer


    private var emptyState: some View {
        EmptyState(
            icon: "waveform",
            title: String(localized: "collection.empty.title"),
            message: String(localized: "collection.empty.subtitle"),
            cta: .init(label: String(localized: "collection.empty.cta")) {
                showingAdd = true
            }
        )
    }

    /// Round 62: 디자인 SSOT 의 challenge card — 다음 도전 progress.
    /// Round 134 BUG FIX (사용자 보고: 측정 며칠 안 했는데 7/7):
    /// "한 주 연속 측정" 의도는 일주일 동안 매일 측정 — 즉 distinct day 개수.
    /// 이전 코드는 단순 측정 횟수라서 하루에 7번 측정하면 7/7 으로 잡힘.
    private var challengeCard: some View {
        let cal = Calendar.current
        let weekDays = Set(watches.flatMap { w in
            w.measurements.compactMap { m -> Date? in
                guard cal.isDate(m.timestamp, equalTo: Date(), toGranularity: .weekOfYear) else { return nil }
                return cal.startOfDay(for: m.timestamp)
            }
        })
        let target = 7
        let done = min(weekDays.count, target)
        return HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 22))
                .foregroundStyle(AppColors.accentDark)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "collection.challenge.title"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.primaryDeep)
                // Round 104 (BUG-8): 인라인 한국어 → localize.
                Text(String(format: String(localized: "collection.challenge.progress"), done, target, max(target - done, 0)))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.primary700)
            }
            Spacer()
        }
        .padding(16)
        .background(AppColors.accent50)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.accentLight, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var footer: some View {
        // 페르소나 (cross-cutting) 피드백: hardcoded "v0.2" 와 settings 버전 drift 위험.
        // Bundle 에서 동적으로 가져옴.
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let year = Calendar.current.component(.year, from: Date())
        return Text("TICKLAB · v\(version) · \(year)")
            .font(.system(size: 9.5, weight: .regular, design: .monospaced))
            .tracking(3)
            .foregroundStyle(AppColors.ink3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }
}

// MARK: - Hero Card (첫 시계)

struct HeroWatchCard: View {
    let watch: Watch
    @Environment(\.modelContext) private var modelContext

    // Round 174: sorted() O(N log N) → max(by:) O(N).
    private var lastMeasurement: WatchMeasurement? {
        watch.measurements.max(by: { $0.timestamp < $1.timestamp })
    }
    private var rates: [Double] {
        watch.measurements
            .sorted(by: { $0.timestamp < $1.timestamp })
            .suffix(7).map { $0.rateSecondsPerDay }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Round 72: 디자인 SSOT screens-detail.jsx WatchDetailView hero — paper-cool linen bg + WatchSilhouette 180pt.
            // Round 151: photoData 있으면 사진, 없으면 silhouette (WatchListRow 와 동일 우선순위).
            ZStack(alignment: .topTrailing) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [AppColors.accent50, AppColors.paper2],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 240)
                if let img = PhotoCache.image(for: watch.id, data: watch.photoData) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 240)
                        .clipped()
                } else {
                    WatchSilhouette(watch: watch, size: 180)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if watch.isPrimary {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                        Text(String(localized: "watch.primary.badge"))
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.5)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.accent)
                    .clipShape(Capsule())
                    .padding(.top, 14)
                    .padding(.leading, 14)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                if let last = lastMeasurement {
                    ConfidenceBadge(score: last.confidenceScore)
                        .padding(14)
                }
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(watch.brand.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(2.2)
                            .foregroundStyle(AppColors.ink2)
                        Text(watch.model)
                            .font(.system(size: 20, weight: .medium, design: .serif))
                            .foregroundStyle(AppColors.ink0)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer()
                    // Round 152/70: 다마고치 mood emoji — Hero/List 동일 16pt.
                    let mood = WatchMoodService.status(of: watch, in: modelContext).mood
                    Text(mood.emoji)
                        .font(.system(size: 16))
                    // Round 151: hero card 에도 wear toggle.
                    let worn = WearLogService.isWornToday(watch, in: modelContext)
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        WearLogService.toggleToday(watch, in: modelContext)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: worn ? "checkmark.seal.fill" : "checkmark.seal")
                                .font(.system(size: 14))
                            Text(String(localized: worn ? "wear.toggle.on" : "wear.toggle.off"))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(worn ? AppColors.accent : AppColors.ink2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(worn ? AppColors.accent50 : AppColors.paper2)
                        .overlay(Capsule().stroke(worn ? AppColors.accentLight : AppColors.rule, lineWidth: 1))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    if watch.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.accent)
                    }
                }

                if let last = lastMeasurement {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "collection.last_rate").uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(2)
                                .foregroundStyle(AppColors.ink2)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(formatRate(last.rateSecondsPerDay))
                                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(rateColor(last.rateSecondsPerDay))
                                Text(String(localized: "unit.seconds_per_day"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppColors.ink2)
                            }
                        }
                        Spacer()
                        Sparkline(values: rates, width: 100, height: 28)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(String(format: NSLocalizedString("collection.runs", comment: ""), watch.measurements.count).uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(1.8)
                                .foregroundStyle(AppColors.ink2)
                            Text(timeAgo(last.timestamp))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(AppColors.ink2)
                        }
                    }
                } else {
                    Text(String(localized: "collection.no_measurements"))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.ink2)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)
        }
        .background(AppColors.paper0)
        .overlay(
            RoundedRectangle(cornerRadius: 18).stroke(AppColors.rule, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - List Row

struct WatchListRow: View {
    let watch: Watch
    /// Round 16 (Sora): parent 가 한 번 계산한 결과를 prop 으로 받음 — row 마다 fetch 방지.
    let wornToday: Bool

    init(watch: Watch, wornToday: Bool) {
        self.watch = watch
        self.wornToday = wornToday
    }

    // Round 174: sorted() O(N log N) → max(by:) O(N).
    private var lastMeasurement: WatchMeasurement? {
        watch.measurements.max(by: { $0.timestamp < $1.timestamp })
    }
    private var rates: [Double] {
        watch.measurements
            .sorted(by: { $0.timestamp < $1.timestamp })
            .suffix(7).map { $0.rateSecondsPerDay }
    }

    /// 디자인 SSOT components.jsx WatchRow classic — photo placeholder + brand caption + model title-3 + rate mono + ConfidenceBadge + forward chevron.
    /// Round 71/131: WatchSilhouette 통일 + Watch.photoData 있으면 사진 / "오늘 착용" wear toggle 추가.
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        // Round 74: SE 320pt 너비 대응 — spacing 14→10.
        HStack(spacing: 10) {
            ZStack {
                AppColors.paper2
                if let img = PhotoCache.image(for: watch.id, data: watch.photoData) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    WatchSilhouette(watch: watch, size: 60)
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(watch.brand)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.tail)
                Text(watch.model)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 8) {
                    if let last = lastMeasurement {
                        Text("\(formatRate(last.rateSecondsPerDay)) s/d")
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(AppColors.ink0)
                        ConfidenceBadge(score: last.confidenceScore, compact: true)
                    } else {
                        Chip("NEW", tone: .accent, small: true)
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Round 152: 다마고치 mood emoji (small list).
            let mood = WatchMoodService.status(of: watch, in: modelContext).mood
            Text(mood.emoji)
                .font(.system(size: 16))
            // 컴팩트 wear toggle — chevron 제거로 SE 폭 확보 (NavigationLink 가 row 전체 tap 처리).
            let worn = wornToday
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    WearLogService.toggleToday(watch, in: modelContext)
                }
            } label: {
                Image(systemName: worn ? "checkmark.seal.fill" : "checkmark.seal")
                    .font(.system(size: 22, weight: worn ? .semibold : .regular))
                    .foregroundStyle(worn ? AppColors.accent : AppColors.ink3)
                    .symbolEffect(.bounce.up, value: worn)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: worn ? "wear.toggle.on" : "wear.toggle.off"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Helpers

func formatRate(_ rate: Double) -> String {
    (rate >= 0 ? "+" : "") + String(format: "%.1f", rate)
}
func rateColor(_ rate: Double) -> Color {
    let abs = abs(rate)
    if abs <= 6 { return AppColors.success }
    if abs <= 20 { return AppColors.warning }
    return AppColors.danger
}
func timeAgo(_ ts: Date) -> String {
    let sec = Date().timeIntervalSince(ts)
    // Round 104 (BUG-9): 60초 이내 = "just now" — "never measured" 오표시 수정.
    if sec < 60 { return String(localized: "watch.row.just_now") }
    if sec < 3600 { return "\(Int(sec / 60))m" }
    if sec < 86400 { return "\(Int(sec / 3600))h" }
    return "\(Int(sec / 86400))d"
}

/// Round 170: 별도 sheet 에서 native List + .onMove 로 reorder.
/// Main view 에서는 카드 tap 만 — drag freeze 이슈 없음.
/// swipeActions 로 대표 설정 / 삭제 도 같이 처리.
private struct ReorderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let watches: [Watch]
    let onCommit: ([Watch]) -> Void
    let onSetPrimary: (Watch) -> Void
    let onDelete: (Watch) -> Void

    @State private var ordered: [Watch] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(ordered, id: \.id) { watch in
                    HStack(spacing: 12) {
                        // Round 170: 등록한 사진 있으면 사진, 없으면 silhouette.
                        ZStack {
                            AppColors.paper2
                            if let img = PhotoCache.image(for: watch.id, data: watch.photoData) {
                                Image(uiImage: img).resizable().scaledToFill()
                            } else {
                                WatchSilhouette(watch: watch, size: 36)
                            }
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(watch.brand).font(.system(size: 12)).foregroundStyle(AppColors.ink2)
                            Text(watch.model).font(.system(size: 16, weight: .medium))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            // Round 21 (Min): 진행 중 reorder 도 함께 commit — swipe delete 가 sheet 닫지
                            //   않는 동안 사용자가 옮긴 순서가 보존되도록.
                            onCommit(ordered)
                            onDelete(watch)
                            ordered.removeAll { $0.id == watch.id }
                        } label: {
                            Label(String(localized: "common.delete"), systemImage: "trash")
                        }
                        Button {
                            // Round 21 (Min): primary 변경 시 reorder 도 commit — 두 액션을 동시 적용한 사용자
                            //   기대 충족 (이전엔 setPrimary 만 살고 순서 버려짐).
                            onCommit(ordered)
                            onSetPrimary(watch)
                            dismiss()
                        } label: {
                            Label(String(localized: "watch.primary.set"), systemImage: "star")
                        }
                        .tint(AppColors.accent)
                    }
                }
                .onMove { source, dest in
                    ordered.move(fromOffsets: source, toOffset: dest)
                }
            }
            .environment(\.editMode, .constant(.active))
            .listStyle(.plain)
            .navigationTitle(String(localized: "collection.reorder.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) {
                        onCommit(ordered)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
            }
            .onAppear { ordered = watches }
        }
    }
}

#Preview {
    CollectionView()
        .modelContainer(for: [Watch.self, WatchMeasurement.self], inMemory: true)
        .environment(UserPreferences())
}
