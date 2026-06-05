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
    /// UX 고도화: 등록 없이 빠른 측정(transient) 진입.
    @State private var showQuickMeasure = false
    @State private var showingSettings = false
    @State private var showingWatchBox = false
    /// 커뮤니티 활동 알림(내 글 좋아요·새 팔로워) — 종 배지.
    @State private var showingNotifications = false
    @State private var notifCount = 0
    /// Round 113 (수익화 Critical): Pro 게이팅 - 무료 한계 초과 시 안내.
    @State private var showingProLimit = false
    /// shell-level paywall.
    @Environment(\.purchaseRouter) private var purchaseRouter
    /// 사용자 보고 fix: collectionSummary 가 body 마다 watches.measurements.max 호출 → 20시계×200측정=4k scan.
    ///   @State 캐시 + watches/measurement-change 시점에만 재계산.
    @State private var cachedSummary: (total: Int, healthy: Int, caution: Int, service: Int) = (0, 0, 0, 0)
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
    /// Sprint 4 (P3-10): 고급 필터 — 시계 5개 이상 보유 시 표시.
    @State private var filterMovementType: WatchMovementType? = nil
    @State private var showAdvancedFilter: Bool = false
    /// Sprint 8 (UX): 정렬 옵션 (5개 이상 보유 시).
    enum SortOption: String, CaseIterable {
        case custom      // 사용자 순서 (기본)
        case brand       // 브랜드 가나다
        case recentWear  // 최근 착용순
        case name        // 모델명
        case unmeasured  // 미측정 먼저 (헤비 컬렉터 리뷰)
        case accuracy    // 최근 정확도순 (|rate| 작은 순)
        var label: LocalizedStringResource {
            switch self {
            case .custom:     return "sort.custom"
            case .brand:      return "sort.brand"
            case .recentWear: return "sort.recent_wear"
            case .name:       return "sort.name"
            case .unmeasured: return "sort.unmeasured"
            case .accuracy:   return "sort.accuracy"
            }
        }
    }
    @State private var sortOption: SortOption = .custom
    /// Sprint 12 (UX1): 측정 단축 sheet 대상 시계.
    @State private var measureWatch: Watch?
    /// Sprint 13 (F5): 일괄 선택 모드 (5개+).
    @State private var selectMode: Bool = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showingBulkDeleteAlert: Bool = false

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
        let sorted: [Watch] = {
            switch sortOption {
            case .custom:
                return watches.sorted {
                    switch ($0.sortOrder, $1.sortOrder) {
                    case let (sa?, sb?): return sa < sb
                    case (_?, nil): return true
                    case (nil, _?): return false
                    case (nil, nil): return $0.createdAt > $1.createdAt
                    }
                }
            case .brand:
                return watches.sorted { $0.brand.localizedCompare($1.brand) == .orderedAscending }
            case .name:
                return watches.sorted { $0.model.localizedCompare($1.model) == .orderedAscending }
            case .recentWear:
                let lastWorn: [UUID: Date] = Dictionary(
                    wearLogs.compactMap { log -> (UUID, Date)? in
                        guard let id = log.watch?.id else { return nil }
                        return (id, log.date)
                    },
                    uniquingKeysWith: { max($0, $1) }
                )
                return watches.sorted {
                    (lastWorn[$0.id] ?? .distantPast) > (lastWorn[$1.id] ?? .distantPast)
                }
            case .unmeasured:
                // 측정 적은 순(미측정 먼저) → 점검 우선순위.
                return watches.sorted { $0.measurements.count < $1.measurements.count }
            case .accuracy:
                // 최근 측정 |rate| 작은 순(정확한 것 먼저). 미측정은 뒤로.
                func absRate(_ w: Watch) -> Double {
                    guard let last = w.measurements.max(by: { $0.timestamp < $1.timestamp }) else {
                        return .greatestFiniteMagnitude
                    }
                    return abs(last.rateSecondsPerDay)
                }
                return watches.sorted { absRate($0) < absRate($1) }
            }
        }()
        // 검색 필터
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let searched: [Watch] = sorted.filter { w in
            // Sprint 4 (P3-10): 무브먼트 타입 필터
            if let mt = filterMovementType, w.movementType != mt { return false }
            guard !q.isEmpty else { return true }
            return w.brand.lowercased().contains(q)
                || w.model.lowercased().contains(q)
                || (w.nickname?.lowercased().contains(q) ?? false)
                || (w.caliber?.lowercased().contains(q) ?? false)
                || (w.referenceNumber?.lowercased().contains(q) ?? false)
                || (w.purchaseLocation?.lowercased().contains(q) ?? false)
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

    /// 삭제 확인 메시지(시계명 포함) — body 타입체커 부하 분리.
    private func deleteConfirmBody(_ watch: Watch) -> String {
        let name = "\(watch.brand) \(watch.model)".trimmingCharacters(in: .whitespaces)
        return String(format: NSLocalizedString("watch.delete.confirm.body", comment: ""), name)
    }

    var body: some View {
        NavigationStack(path: pathBinding) {
            ZStack {
                AppColors.paper0.ignoresSafeArea()
                VStack(spacing: 0) {
                    // 제목·버튼을 같은 최상단 영역으로 — 헤더 고정 + 우상단 액션 오버레이.
                    header
                    filterSortRow
                    // Sprint 4 (P3-10): 고급 필터 패널
                    if showAdvancedFilter && watches.count >= 5 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                filterChip(
                                    label: String(localized: "collection.filter.all"),
                                    isSelected: filterMovementType == nil
                                ) { filterMovementType = nil }
                                ForEach(WatchMovementType.allCases, id: \.self) { mt in
                                    filterChip(
                                        label: mt.displayName,
                                        isSelected: filterMovementType == mt
                                    ) { filterMovementType = filterMovementType == mt ? nil : mt }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .background(AppColors.paper1)
                        .overlay(alignment: .bottom) {
                            Divider()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Sprint 5 (P3-12): 시즌 이벤트 배너
                        SeasonalEventBanner()
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
                                    HeroWatchCard(watch: primary, onMeasure: { measureWatch = primary })
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
                                HStack(spacing: 8) {
                                    Spacer()
                                    // Sprint 13 (F5): 일괄 선택 진입 (5개+).
                                    if watches.count >= 5 {
                                        Button {
                                            withAnimation { selectMode.toggle(); selectedIDs.removeAll() }
                                        } label: {
                                            Label(String(localized: selectMode ? "common.done" : "collection.select"),
                                                  systemImage: selectMode ? "checkmark.circle" : "checkmark.circle.badge.questionmark")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(selectMode ? AppColors.accent : AppColors.ink2)
                                                .padding(.horizontal, 14).padding(.vertical, 10)
                                                .background(AppColors.paper1)
                                                .overlay(Capsule().stroke(selectMode ? AppColors.accentLight : AppColors.rule, lineWidth: 1))
                                                .clipShape(Capsule())
                                        }
                                    }
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
                                    if selectMode {
                                        // Sprint 13 (F5): 선택 모드 — tap=선택 토글, navigation 비활성.
                                        Button {
                                            toggleSelect(watch.id)
                                        } label: {
                                            WatchListRow(watch: watch, wornToday: wornTodayIds.contains(watch.id))
                                                .overlay(alignment: .topTrailing) {
                                                    Image(systemName: selectedIDs.contains(watch.id) ? "checkmark.circle.fill" : "circle")
                                                        .font(.system(size: 22))
                                                        .foregroundStyle(selectedIDs.contains(watch.id) ? AppColors.accent : AppColors.ink3)
                                                        .padding(10)
                                                        // 접근성: 선택 상태는 버튼 .isSelected trait 로 음성 안내 — 아이콘은 시각 전용
                                                        .accessibilityHidden(true)
                                                }
                                                .opacity(selectedIDs.contains(watch.id) ? 1 : 0.7)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityAddTraits(selectedIDs.contains(watch.id) ? .isSelected : [])
                                    } else {
                                        PressableCard {
                                            pathBinding.wrappedValue.append(watch)
                                        } content: {
                                            WatchListRow(watch: watch, wornToday: wornTodayIds.contains(watch.id))
                                        }
                                        // 인터랙션 진단(R1): 비대표 카드에 삭제/대표설정 경로가 없어
                                        //   시계 1~2개 사용자는 삭제를 못 찾음. long-press contextMenu 로 노출.
                                        .contextMenu {
                                            Button {
                                                for w in watches { w.isPrimary = false }
                                                watch.isPrimary = true
                                                try? modelContext.save()
                                            } label: {
                                                Label(String(localized: "watch.primary.set"), systemImage: "star")
                                            }
                                            Button(role: .destructive) {
                                                deletingWatch = watch
                                            } label: {
                                                Label(String(localized: "common.delete"), systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            // Sprint 11 (사용자 요청): 컬렉션 가치를 시계 목록 아래로 이동.
                            if watches.contains(where: { $0.purchasePrice != nil }) {
                                CollectionValueCard(watches: watches)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 20)
                            }
                            // Round 62: 디자인 SSOT screens-main.jsx 의 "다음 도전" Founder-style card.
                            challengeCard
                                .padding(.horizontal, 20)
                                .padding(.top, 24)
                            footer
                        }
                    }
                }
                } // end ScrollView (Sprint 4 outer VStack)
                // Sprint 13 (F5): 선택 모드 하단 일괄작업 바.
                if selectMode {
                    bulkActionBar
                }
            } // end ZStack
            // 제목을 제일 상단으로 — 내비바 숨김. 검색은 헤더 영역 인라인 필드로 이동(4탭 통일).
            .toolbar(.hidden, for: .navigationBar)
            // 발견성(R6): 컬렉션 진입 시 Spotlight 색인 갱신 — iOS 검색에서 시계 찾기.
            .onAppear { WatchSpotlightIndexer.index(watches) }
            .sheet(isPresented: $showingWatchBox) {
                WatchBoxView()
                    .environment(preferences)
            }
            .sheet(isPresented: $showingAdd) {
                AddWatchView()
            }
            // Sprint 12 (UX1): 측정 단축 sheet — NavigationStack 래핑(측정 화면 push 전제 충족).
            .sheet(item: $measureWatch) { w in
                NavigationStack {
                    MeasurementView(watch: w, preferences: preferences)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(String(localized: "common.close")) { measureWatch = nil }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingNotifications) {
                CommunityNotificationsView()
            }
            .task { await refreshNotifBadge() }
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
            } message: { watch in
                Text(deleteConfirmBody(watch))
            }
        }
    }

    // MARK: - Header

    /// 하이브리드 C: 공용 EditorialPageHeader 로 4탭 헤더 톤 통일(수제 복제 제거).
    /// 제목·버튼을 같은 최상단 영역으로 — 우상단에 더보기·추가·설정 오버레이.
    private var header: some View {
        EditorialPageHeader(
            eyebrow: String(localized: "collection.eyebrow"),
            title: String(localized: "collection.title"),
            subtitle: String(localized: "collection.subtitle")
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .overlay(alignment: .topTrailing) {
            headerActionButtons
                .padding(.trailing, 14)
                .padding(.top, 2)
        }
    }

    /// 제목 영역 우상단 — 더보기 · 추가 · 설정(우측 끝). 기존 내비바 toolbar 에서 이전.
    /// 아이콘 크기·프레임을 커뮤니티 헤더와 동일하게 통일(40x40, symbol 18).
    private var headerActionButtons: some View {
        HStack(spacing: 0) {
            Button { openNotifications() } label: {
                Image(systemName: notifCount > 0 ? "bell.badge.fill" : "bell")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(notifCount > 0 ? AppColors.accent : AppColors.ink1)
                    .symbolRenderingMode(notifCount > 0 ? .multicolor : .monochrome)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel(String(localized: "collection.notifications"))
            Menu {
                Button { showingWatchBox = true } label: {
                    Label(String(localized: "menu.watchbox"), systemImage: "shippingbox")
                }
                NavigationLink { SpecCardListView() } label: {
                    Label(String(localized: "menu.speccard"), systemImage: "rectangle.stack")
                }
                NavigationLink { WishlistView() } label: {
                    Label(String(localized: "menu.wishlist"), systemImage: "heart")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(AppColors.ink1)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel(String(localized: "collection.more_menu"))
            Button {
                if !preferences.isPro && watches.count >= ProEntitlement.freeWatchLimit {
                    showingProLimit = true
                } else {
                    showingAdd = true
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(AppColors.ink0)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel(String(localized: "collection.add_watch"))
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(AppColors.ink1)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel(String(localized: "tab.settings"))
            .accessibilityIdentifier("nav.settings")
        }
    }

    /// 종 탭 — 즉시 배지 클리어("확인하면 없어지고") + 알림 목록 시트.
    private func openNotifications() {
        CommunityService.shared.markNotificationsSeen()
        notifCount = 0
        showingNotifications = true
    }

    /// 미확인 알림 수 갱신 — 컬렉션 진입 시.
    private func refreshNotifBadge() async {
        notifCount = await CommunityService.shared.unseenNotificationCount()
    }

    /// 검색·필터·정렬 — 5개 이상 보유 시 헤더 아래 줄.
    /// 검색은 내비바 .searchable 대체(제목을 최상단으로 올리기 위해 인라인으로 이동).
    @ViewBuilder
    private var filterSortRow: some View {
        if watches.count >= 5 {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.ink3)
                    TextField(String(localized: "collection.search.placeholder"), text: $searchQuery)
                        .font(.system(size: 14))
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.ink3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.paper1)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(AppColors.rule, lineWidth: 1))
                Button {
                    withAnimation { showAdvancedFilter.toggle() }
                } label: {
                    Image(systemName: filterMovementType != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(filterMovementType != nil ? AppColors.accent : AppColors.ink2)
                }
                .accessibilityLabel(String(localized: "collection.filter.label"))
                Menu {
                    ForEach(SortOption.allCases, id: \.self) { opt in
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { sortOption = opt }
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            Label(String(localized: opt.label),
                                  systemImage: sortOption == opt ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: sortOption == .custom ? "arrow.up.arrow.down" : "arrow.up.arrow.down.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(sortOption == .custom ? AppColors.ink2 : AppColors.accent)
                }
                .accessibilityLabel(String(localized: sortOption.label))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
        }
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
                    Spacer(minLength: 0)
                    Text(String(format: String(localized: "collection.dashboard.total_watches"), counts.total))
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

    private var collectionSummary: (total: Int, healthy: Int, caution: Int, service: Int) {
        cachedSummary
    }

    /// watches.count 또는 측정 종료 시점에만 재계산.
    private func refreshCollectionSummary() {
        var h = 0, c = 0, s = 0
        for w in watches {
            guard let last = w.measurements.max(by: { $0.timestamp < $1.timestamp }) else { continue }
            let absRate = abs(last.rateSecondsPerDay)
            if absRate <= 10 { h += 1 }
            else if absRate <= 20 { c += 1 }
            else { s += 1 }
        }
        cachedSummary = (watches.count, h, c, s)
    }

    // MARK: - Empty / Footer


    // MARK: - Sprint 13 (F5) 일괄 작업

    private func toggleSelect(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private var bulkActionBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 16) {
                Text(String(format: NSLocalizedString("collection.selected_count", comment: ""), selectedIDs.count))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                Spacer()
                // 일괄 삭제
                Button {
                    showingBulkDeleteAlert = true
                } label: {
                    Image(systemName: "trash").font(.system(size: 18)).foregroundStyle(AppColors.danger)
                        // 접근성: 아이콘 전용 버튼 최소 44pt 터치 영역 (아이콘 크기 유지)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .disabled(selectedIDs.isEmpty)
                .accessibilityLabel(String(localized: "common.delete"))
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { Divider() }
        }
        .ignoresSafeArea(edges: .bottom)
        .alert(String(localized: "collection.bulk_delete.title"), isPresented: $showingBulkDeleteAlert) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "common.delete"), role: .destructive) { bulkDelete() }
        } message: {
            Text(String(format: NSLocalizedString("collection.bulk_delete.message", comment: ""), selectedIDs.count))
        }
    }

    private func bulkDelete() {
        // Jay Critical: deleteCascade 헬퍼 필수 (Strap/WatchPhoto orphan 방지).
        for w in watches where selectedIDs.contains(w.id) {
            w.deleteCascade(in: modelContext)
        }
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { selectMode = false; selectedIDs.removeAll() }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? AppColors.primaryDeep : AppColors.ink2)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected
                    ? LinearGradient(colors: [AppColors.accent, AppColors.accentDark],
                                     startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [AppColors.paper2, AppColors.paper2],
                                     startPoint: .leading, endPoint: .trailing))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        EmptyState(
            icon: "waveform",
            title: String(localized: "collection.empty.title"),
            message: String(localized: "collection.empty.subtitle"),
            cta: .init(label: String(localized: "collection.empty.cta")) {
                showingAdd = true
            }
        )
        // UX 고도화: 등록 없이 먼저 정확도 맛보기(입문자 첫경험 마찰↓).
        .overlay(alignment: .bottom) {
            Button { showQuickMeasure = true } label: {
                HStack(spacing: 6) {
                    ConceptGlyph(systemName: "waveform", size: 15, color: AppColors.accentDark)
                    Text(String(localized: "collection.empty.quick_measure",
                                defaultValue: "등록 없이 빠른 측정 해보기"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.accentDark)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .overlay(Capsule().stroke(AppColors.accent.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 72)
        }
        .quickMeasureSheet(isPresented: $showQuickMeasure, preferences: preferences) {
            showingAdd = true
        }
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
                .accessibilityHidden(true)  // 접근성: 장식용 — 옆 챌린지 텍스트가 의미 전달
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "collection.challenge.title"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                // Round 104 (BUG-8): 인라인 한국어 → localize.
                Text(String(format: String(localized: "collection.challenge.progress"), done, target, max(target - done, 0)))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink1)
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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.1"
        return Text("TICKLAB · v\(version)")
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
    /// Sprint 12 (UX1): 측정 단축 진입 콜백. nil 이면 버튼 숨김.
    var onMeasure: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    /// 착용 시 태그 피커(어떤 자리) — 다른 카드와 동일.
    @State private var showingTagPicker: Bool = false
    @State private var recentWearLog: WearLog?

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
            // 웨이브2-C: 사진을 주인공으로 — 하단 에디토리얼 캡션 바를 사진 위 scrim 으로 합침.
            heroPhoto
            // 단일 primary 메트릭 라인(rate readout + 스파크라인).
            primaryMetricLine
                .padding(.horizontal, 18)
                .padding(.top, 18)
            // mood / wear / measure 컨트롤 — 더 조용한 secondary 행(여백 확대).
            secondaryControlRow
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 18)
        }
        // 웨이브2-C: hero 카드만 luxeCard + .high 로 띄움.
        .luxeCard(cornerRadius: 22, elevated: true)
        .sheet(isPresented: $showingTagPicker) {
            if let log = recentWearLog {
                WearTagPickerView(wearLog: log)
            }
        }
    }

    // MARK: - Hero photo + editorial caption

    /// 사진 + 하단 에디토리얼 캡션 바(브랜드 eyebrow + 세리프 모델명 + 약한 scrim).
    private var heroPhoto: some View {
        ZStack(alignment: .topTrailing) {
            // Round 72/151: photoData 있으면 사진, 없으면 silhouette.
            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [AppColors.accent50, AppColors.paper2],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let img = PhotoCache.image(for: watch.id, data: watch.photoData) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    WatchSilhouette(watch: watch, size: 180)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            // 사용자 결정: 대표 사진 4:3 전체 표시(잘림 없음) — 업로드 크롭과 동일 비율 → WYSIWYG.
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) { captionBar }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))

            // 우상단 — 대표 배지 / 신뢰도 배지.
            VStack(alignment: .trailing, spacing: 8) {
                if watch.isPrimary {
                    HStack(spacing: 4) {
                        ConceptGlyph(systemName: "star.fill", size: 12)
                            .accessibilityHidden(true)  // 접근성: 옆 "대표" 텍스트가 의미 전달 — 장식용
                        Text(String(localized: "watch.primary.badge"))
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.5)
                    }
                    .foregroundStyle(AppColors.primaryDeep)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(AppGradients.goldFoil)
                    .clipShape(Capsule())
                }
                if let last = lastMeasurement {
                    ConfidenceBadge(score: last.confidenceScore)
                }
            }
            .padding(14)
        }
    }

    /// 사진 하단 scrim + 에디토리얼 캡션(브랜드 eyebrow + 세리프 모델명).
    private var captionBar: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(watch.brand.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.6)
                .foregroundStyle(.white.opacity(0.82))
            Text(watch.model)
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 36)
        .padding(.bottom, 16)
        .background(
            // 약한 scrim — 하단에서 위로 옅게 어두워짐(사진 가독성, 사진은 그대로 주인공).
            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    // MARK: - Primary metric line

    /// 단일 primary 메트릭 라인 — rate readout + 스파크라인 + run/recency.
    @ViewBuilder
    private var primaryMetricLine: some View {
        if let last = lastMeasurement {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "collection.last_rate").uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(AppColors.ink2)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatRate(last.rateSecondsPerDay))
                            .font(.system(size: 26, weight: .medium, design: .monospaced))
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

    // MARK: - Secondary controls

    /// 더 조용한 secondary 행 — mood emoji + 착용 토글 + 측정/배터리. hairline 으로 metric 과 분리.
    private var secondaryControlRow: some View {
        let mood = WatchMoodService.status(of: watch, in: modelContext).mood
        let worn = WearLogService.isWornToday(watch, in: modelContext)
        return VStack(spacing: 14) {
            Rectangle()
                .fill(AppColors.rule)
                .frame(height: 0.5)
                .accessibilityHidden(true)
            HStack(spacing: 10) {
                // Round 152/70: 다마고치 mood emoji.
                Text(mood.emoji)
                    .font(.system(size: 16))
                Spacer()
                // Round 151: hero card 에도 wear toggle.
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    // 사용자 보고: 대표 시계도 착용 시 태그 피커("어떤 자리") 표시 — 다른 카드와 동일.
                    let added = WearLogService.toggleToday(watch, in: modelContext)
                    if added {
                        let today = Calendar.current.startOfDay(for: Date())
                        let watchID = watch.id
                        let desc = FetchDescriptor<WearLog>(
                            predicate: #Predicate { $0.watch?.id == watchID && $0.date == today }
                        )
                        recentWearLog = (try? modelContext.fetch(desc))?.first
                        if recentWearLog != nil {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showingTagPicker = true
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        ConceptGlyph(systemName: worn ? "checkmark.seal.fill" : "checkmark.seal", size: 14)
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
                // 스마트워치: 측정 대신 배터리 잔량 배지(완충 N일 기준).
                if watch.isSmartwatch {
                    SmartwatchBatteryBadge(percent: watch.batteryPercent)
                } else if let onMeasure, watch.movementType != .quartz {
                    // Sprint 12 (UX1): 측정 단축 — 기계식만, 콜백 있을 때.
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        onMeasure()
                    } label: {
                        HStack(spacing: 5) {
                            ConceptGlyph(systemName: "mic", size: 14, color: .white)
                                .accessibilityHidden(true)  // 접근성: 옆 "측정" 텍스트가 의미 전달 — 장식용
                            Text(String(localized: "measurement.button.start_short"))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(AppColors.accentDark)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Conditional Searchable (Sprint 11)

/// 시계 5개 이상일 때만 .searchable 적용. 소수 보유 사용자에겐 검색칸 숨김.
struct ConditionalSearchable: ViewModifier {
    let isActive: Bool
    @Binding var text: String
    let prompt: String
    func body(content: Content) -> some View {
        if isActive {
            content.searchable(text: $text,
                               placement: .navigationBarDrawer(displayMode: .automatic),
                               prompt: Text(prompt))
        } else {
            content
        }
    }
}

// MARK: - List Row

struct WatchListRow: View {
    let watch: Watch
    /// Round 16 (Sora): parent 가 한 번 계산한 결과를 prop 으로 받음 — row 마다 fetch 방지.
    let wornToday: Bool
    /// Sprint 4 (P2-18): 착용 토글 후 tag picker 표시.
    @State private var showingTagPicker: Bool = false
    @State private var recentWearLog: WearLog?

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

    /// 3-1 (R21): "마지막 측정 N일 전" — 측정 recency 가시화 + 측정 권유. 이력 없으면 측정 유도 문구.
    private var lastMeasuredText: String {
        guard let last = lastMeasurement else {
            return String(localized: "collection.card.measure_prompt")
        }
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: last.timestamp),
                                      to: cal.startOfDay(for: Date())).day ?? 0
        if days <= 0 { return String(localized: "collection.card.measured_today") }
        return String(format: NSLocalizedString("collection.card.measured_days_ago", comment: ""), days)
    }

    /// 디자인 SSOT components.jsx WatchRow classic — photo placeholder + brand caption + model title-3 + rate mono + ConfidenceBadge + forward chevron.
    /// Round 71/131: WatchSilhouette 통일 + Watch.photoData 있으면 사진 / "오늘 착용" wear toggle 추가.
    @Environment(\.modelContext) private var modelContext

    // Sprint 3 (P3-7): 다이얼 색상 추출 — @State 캐시로 매 렌더 CIAreaAverage 방지.
    @State private var extractedColor: Color? = nil

    private func extractColorIfNeeded() {
        guard extractedColor == nil, let data = watch.photoData else { return }
        let watchID = watch.id
        // Sprint 11 (Sora #2): 디코딩까지 백그라운드 — main thread 동기 디코드 제거.
        Task.detached(priority: .utility) {
            guard let img = PhotoCache.image(for: watchID, data: data),
                  let cg = img.cgImage else { return }
            let color = DialColorExtractor.averageColor(from: cg)
            await MainActor.run { self.extractedColor = color }
        }
    }

    var body: some View {
        // Round 74: SE 320pt 너비 대응 — spacing 14→10.
        HStack(spacing: 10) {
            ZStack {
                if let accent = extractedColor {
                    LinearGradient(
                        colors: [accent.opacity(0.7), accent.opacity(0.3)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                } else {
                    AppColors.paper2
                }
                if watch.photoData != nil {
                    WatchPhotoView(id: watch.id, data: watch.photoData) {
                        WatchSilhouette(watch: watch, size: 60)
                    }
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
                    if watch.isSmartwatch {
                        SmartwatchBatteryBadge(percent: watch.batteryPercent, compact: true)
                    } else if let last = lastMeasurement {
                        Text("\(formatRate(last.rateSecondsPerDay)) \(String(localized: "unit.seconds_per_day"))")
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(AppColors.ink0)
                        ConfidenceBadge(score: last.confidenceScore, compact: true)
                    } else {
                        Chip(String(localized: "collection.chip.new"), tone: .accent, small: true)
                    }
                }
                .padding(.top, 2)
                // 3-1: 마지막 측정 N일 전 (측정 없으면 측정 권유 문구). 스마트워치는 측정 비대상이라 숨김.
                if !watch.isSmartwatch {
                    Text(lastMeasuredText)
                        .font(.system(size: 11))
                        .foregroundStyle(lastMeasurement == nil ? AppColors.accent : AppColors.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
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
                    let added = WearLogService.toggleToday(watch, in: modelContext)
                    // Sprint 4 (P2-18): 착용 추가 시에만 tag picker 표시.
                    if added {
                        let today = Calendar.current.startOfDay(for: Date())
                        let watchID = watch.id
                        let desc = FetchDescriptor<WearLog>(
                            predicate: #Predicate { $0.watch?.id == watchID && $0.date == today }
                        )
                        recentWearLog = (try? modelContext.fetch(desc))?.first
                        if recentWearLog != nil {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showingTagPicker = true
                            }
                        }
                    }
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
            .sheet(isPresented: $showingTagPicker) {
                if let log = recentWearLog {
                    WearTagPickerView(wearLog: log)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .cardShadow(.low)  // Sprint 9 UX
        .onAppear { extractColorIfNeeded() }
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
