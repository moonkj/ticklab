import CoreSpotlight
import SwiftData
import SwiftUI

/// TickLab v3 main shell — 4-tab structure.
/// Round 92 (사용자 요청): 설정 탭 제거 (Collection 상단 우측 톱니로 접근). 대신 "오늘" 탭 신설.
/// 4축: Collection / Today (오늘의 시계+운세) / Journal / Stats.
///
/// Round 176 (사용자 UX 요청, Hyemi 통합):
/// 탭 전환 시 각 탭의 NavigationStack path 를 리셋 — 컬렉션 탭에서 시계 상세 열어 둔 상태로
/// 다른 탭 갔다가 돌아오면 시계 목록(루트) 부터 다시 시작.
/// 같은 탭을 재선택해도 루트로 복귀.
struct RootTabView: View {
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var flags = FeatureFlags.shared
    @State private var selected: Tab = .collection
    /// 운영 ID(관리자) 활성 — 앱 상단에 "관리자 모드" 배너 표시.
    @AppStorage("ticklab.admin.actingAsTickLab") private var actingAsTickLab = false
    /// 관리자 배지 — 신고 건수(종 아이콘) 표시용.
    @State private var reportCount = 0
    /// 공지 — 활성 공지 하단 시트. item-기반 시트(nil=숨김)라 빈 시트 race 없음.
    @State private var activeAnnouncement: Community.Announcement?

    // Round 176: 각 탭의 NavigationStack path — Binding 으로 child view 에 주입.
    @State private var collectionPath = NavigationPath()
    @State private var todayPath = NavigationPath()
    @State private var journalPath = NavigationPath()
    @State private var statsPath = NavigationPath()
    // Round 138 사용자 보고: NavigationPath 만 reset 으로는 `NavigationLink { ... }` (path 안 쓰는)
    // 형태의 push 가 reset 안 됨. .id() epoch 으로 view 강제 재생성해 deep state 까지 모두 root 으로.
    @State private var collectionEpoch: Int = 0
    @State private var todayEpoch: Int = 0
    @State private var journalEpoch: Int = 0
    @State private var statsEpoch: Int = 0
    @State private var communityEpoch: Int = 0
    /// Round 140 (Hyemi/Min H1 Critical): 측정 진행 중 탭 전환 시 epoch 증가가 측정 silent 폐기 유발.
    /// MeasurementViewModel.start/stop 이 notification post → 측정 중에는 epoch 증가 차단.
    @State private var measurementInProgress: Bool = false
    /// 커스텀 탭바 — 키보드 올라오면 숨김(시스템 탭바와 동일 거동).
    @State private var keyboardUp: Bool = false
    /// 사용자 보고 fix: 4 분산 sheet 호스트를 shell 레벨로 통합 — iPad multi-window race 차단 + 신규 진입점 추가 cost 감소.
    @State private var purchaseRouter = PurchaseRouter()
    /// 신기능 안내 시트 — 버전당 1회, 기존 사용자 전용.
    @State private var showWhatsNew = false

    enum Tab: Hashable {
        case collection
        case today
        case journal
        case stats
        case community
    }

    /// 커스텀 탭바에 노출할 탭 순서(커뮤니티는 플래그 ON 일 때만).
    private var tabList: [Tab] {
        var t: [Tab] = [.collection, .today, .journal, .stats]
        if flags.communityEnabled { t.append(.community) }
        return t
    }

    /// 탭 선택 — 햅틱 + (측정 중 아니면) path/epoch 리셋(같은 탭 재탭 = pop to root). 커스텀 탭바가 호출.
    private func select(_ newTab: Tab) {
        if newTab != selected {
            UISelectionFeedbackGenerator().selectionChanged()
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
        }
        // Round 140: 측정 진행 중에는 deep state 보존 → epoch 증가/ path reset 차단.
        let allowReset = !measurementInProgress
        switch newTab {
        case .collection:
            if allowReset { collectionPath = NavigationPath(); collectionEpoch &+= 1 }
        case .today:
            if allowReset { todayPath = NavigationPath(); todayEpoch &+= 1 }
        case .journal:
            if allowReset { journalPath = NavigationPath(); journalEpoch &+= 1 }
        case .stats:
            if allowReset { statsPath = NavigationPath(); statsEpoch &+= 1 }
        case .community:
            if allowReset { communityEpoch &+= 1 }
        }
        selected = newTab
    }

    var body: some View {
        TabView(selection: $selected) {
            CollectionView(path: $collectionPath)
                .id(collectionEpoch)
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label {
                        Text(String(localized: "tab.collection"))
                    } icon: {
                        Image(uiImage: TabBarIcons.collection)
                    }
                }
                .tag(Tab.collection)

            TodayView(path: $todayPath)
                .id(todayEpoch)
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label {
                        Text(String(localized: "tab.today"))
                    } icon: {
                        Image(uiImage: TabBarIcons.today)
                    }
                }
                .tag(Tab.today)

            JournalFeedView(path: $journalPath)
                .id(journalEpoch)
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label {
                        Text(String(localized: "tab.journal"))
                    } icon: {
                        Image(uiImage: TabBarIcons.journal)
                    }
                }
                .tag(Tab.journal)

            StatsView(path: $statsPath)
                .id(statsEpoch)
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label {
                        Text(String(localized: "tab.stats"))
                    } icon: {
                        Image(uiImage: TabBarIcons.stats)
                    }
                }
                .tag(Tab.stats)

            // 커뮤니티 — FeatureFlags.communityEnabled ON 일 때만 노출(백엔드 배포 후).
            if flags.communityEnabled {
                CommunityFeedView()
                    .id(communityEpoch)
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem {
                        Label {
                            Text(String(localized: "community.tab.title"))
                        } icon: {
                            Image(uiImage: TabBarIcons.community)
                        }
                    }
                    .tag(Tab.community)
            }
        }
        // 사용자 보고 fix: 글로벌 accent gold 가 alert 버튼까지 propagate → 가독성 ↓ (#C9A961 on white ~2.8:1).
        //   탭바 selected color 만 indigo 로 바꾸면 alert 도 indigo 로 또렷해짐. 명시적 .tint(accent) 오버라이드는 유지됨.
        //   다크모드: indigo 는 어두운 배경에서 안 보임 → interactiveTint(light=indigo, dark=gold) 로 적응형화.
        .tint(AppColors.interactiveTint)
        // 커스텀 애니메이션 탭바 — 콘텐츠 위에 floating 오버레이(콘텐츠가 글라스 뒤로 흐르며 굴절 → 네이티브 액체 질감).
        // 시스템 탭바는 각 탭에서 .toolbar(.hidden) 처리. overlay 는 safe area 존중 → 홈 인디케이터 위.
        .overlay(alignment: .bottom) {
            if !keyboardUp {
                AnimatedTabBar(tabs: tabList, selected: selected, onSelect: select)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardUp = false
        }
        // 관리자(운영 ID) 활성 시 작은 플로팅 배지로 표시 — 상단 버튼을 가리지 않게
        // 오버레이(레이아웃 비점유) + allowsHitTesting(false)(탭 통과). 탭바 위에 위치.
        .overlay(alignment: .bottomTrailing) {
            if actingAsTickLab {
                HStack(spacing: 6) {
                    Image(systemName: reportCount > 0 ? "bell.badge.fill" : "bell")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red)
                    if reportCount > 0 {
                        Text("\(reportCount)")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(.red))
                    }
                    Text(String(localized: "announce.admin.badge"))
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.red.opacity(0.55), lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                .padding(.trailing, 12)
                .padding(.bottom, 64)
                .allowsHitTesting(false)
                // 탭 전환/배지 등장 시 신고 건수 갱신.
                .task(id: selected) {
                    reportCount = await CommunityService.shared.fetchReportCount()
                }
            }
        }
        .environment(\.purchaseRouter, purchaseRouter)
        // 공지 — 활성 공지가 있고 오늘 안 본 경우 하단 시트로.
        // id: actingAsTickLab → 관리자↔사용자 전환 시 즉시 재확인(관리자가 만든 공지를 사용자 모드에서 바로 보게).
        .task(id: actingAsTickLab) { await checkAnnouncement() }
        // 포그라운드 복귀 시 재확인 — 실사용자는 앱 재실행 없이도 새 공지를 받아야 함.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await checkAnnouncement() } }
        }
        .sheet(item: $activeAnnouncement) { a in
            AnnouncementBottomSheet(announcement: a) { dontShowToday in
                if dontShowToday { AnnouncementDismiss.dismissToday(a.id) }
                activeAnnouncement = nil
            }
        }
        // shell-level paywall — 한 번에 하나만 띄움. 4 분산 sheet 대체.
        .sheet(isPresented: $purchaseRouter.isPresenting) {
            PurchaseView()
                .environment(preferences)
        }
        // 신기능 안내(what's-new) — 발견성 강화. 버전당 1회, 페이월과 충돌 방지 위해 약간 지연.
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewSheet()
                .environment(preferences)
        }
        .onAppear {
            guard WhatsNew.shouldShow(preferences) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if !purchaseRouter.isPresenting && WhatsNew.shouldShow(preferences) {
                    showWhatsNew = true
                }
            }
        }
        // Round 140 (H1): MeasurementViewModel 의 start/end notification 받아 epoch reset 차단.
        .onReceive(NotificationCenter.default.publisher(for: .ticklabMeasurementDidStart)) { _ in
            measurementInProgress = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .ticklabMeasurementDidEnd)) { _ in
            measurementInProgress = false
        }
        // 발견성(R6): Spotlight 결과 탭 → 해당 시계 상세로 딥링크.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let idStr = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let id = UUID(uuidString: idStr),
                  let watch = (try? modelContext.fetch(FetchDescriptor<Watch>()))?.first(where: { $0.id == id })
            else { return }
            // selected 직접 set → 탭 전환 시 path 리셋 로직 우회. 그 후 append 로 상세 push.
            selected = .collection
            collectionPath.append(watch)
        }
    }

    private func checkAnnouncement() async {
        // 스플래시(로딩) 종료 후에만 공지 표시 — 로딩화면 위에 팝업이 뜨는 것 방지.
        //   RootTabView 는 스플래시 오버레이 밑에서 먼저 렌더되므로, 게이트가 풀릴 때까지 대기.
        var waitedMs = 0
        while LaunchGate.shouldShowSplash && waitedMs < 6000 {
            try? await Task.sleep(nanoseconds: 150_000_000); waitedMs += 150
        }
        // 스플래시/온보딩→컬렉션 전환이 끝나고 화면이 안정된 뒤 표시(전환 중 노출 방지).
        try? await Task.sleep(nanoseconds: 500_000_000)
        // 이미 시트 표시 중이면 재요청·재표시 안 함(포그라운드 재진입 중복 방지).
        guard activeAnnouncement == nil else { return }
        // 출시 프로모 공지(앱 내장·백엔드 불필요) 우선 — 모든 사용자에게 하루 1회.
        if LaunchPromo.isActive, !AnnouncementDismiss.isDismissedToday(LaunchPromo.announcementID) {
            activeAnnouncement = Self.promoAnnouncement()
            return
        }
        // 백엔드 공지 — 관리자 모드에선 본인이 만든 공지로 방해받지 않게 사용자 모드에서만.
        guard !actingAsTickLab else { return }
        guard let a = await CommunityService.shared.fetchActiveAnnouncement() else { return }
        if !AnnouncementDismiss.isDismissedToday(a.id) {
            activeAnnouncement = a
        }
    }

    /// 앱 내장 프로모 공지 — 본문은 시트가 promo id 를 감지해 전용 레이아웃으로 렌더(아래 body 는 미사용 placeholder).
    static func promoAnnouncement() -> Community.Announcement {
        Community.Announcement(
            id: LaunchPromo.announcementID,
            body: "",
            startsAt: nil,
            endsAt: LaunchPromo.proFreeUntil,
            active: true,
            createdAt: Date()
        )
    }
}

/// 공지 "오늘 하루 보지 않기" — 공지 id별 dismiss 날짜 저장(UserDefaults).
enum AnnouncementDismiss {
    private static let key = "ticklab.ann.dismissed"
    private static func today() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }
    static func dismissToday(_ id: String) {
        var d = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        d[id] = today()
        UserDefaults.standard.set(d, forKey: key)
    }
    static func isDismissedToday(_ id: String) -> Bool {
        let d = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        return d[id] == today()
    }
}

/// 공지 콘텐츠 자연 높이 측정용 — 시트 detent 를 콘텐츠에 맞춤.
private struct AnnouncementHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// 공지 하단 시트 — 내용 + "오늘 하루 보지 않기" 체크 + 닫기. (관리자 패널 프로모 미리보기에서도 재사용 → internal)
struct AnnouncementBottomSheet: View {
    let announcement: Community.Announcement
    let onClose: (Bool) -> Void
    @State private var dontShowToday = false
    @State private var measuredContent: CGFloat = 0

    private var isPromo: Bool { announcement.id == LaunchPromo.announcementID }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group { if isPromo { promoContent } else { standardContent } }
                    .background(GeometryReader { g in
                        Color.clear.preference(key: AnnouncementHeightKey.self, value: g.size.height)
                    })
            }
            Divider().background(.white.opacity(0.15))
            footer
        }
        .background(AppColors.primaryDeep)
        .onPreferenceChange(AnnouncementHeightKey.self) { measuredContent = $0 }
        // 콘텐츠 높이에 맞춰 시트 크기 자동(footer 포함). 화면 초과 시에만 스크롤.
        .presentationDetents(measuredContent > 0 ? [.height(measuredContent + 64)] : [.fraction(0.55)])
        .presentationDragIndicator(.visible)
    }

    // MARK: 일반 공지(백엔드)
    private var standardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "megaphone.fill")
                .font(.system(size: 28)).foregroundStyle(AppColors.accent)
                .padding(.top, 28)
            Text(String(localized: "announce.eyebrow")).font(.system(size: 12, weight: .bold)).tracking(3).foregroundStyle(.white.opacity(0.6))
            Text(announcement.body)
                .font(.system(size: 16)).foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    // MARK: 출시 프로모 광고
    private var promoPerks: [String] {
        [String(localized: "promo.perk.unlimited"),
         String(localized: "promo.perk.ai"),
         String(localized: "promo.perk.share")]
    }

    private var promoContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                Circle().fill(AppColors.accent.opacity(0.25)).frame(width: 74, height: 74).blur(radius: 8)
                LinearGradient(colors: [AppColors.accentLight, AppColors.accentDark], startPoint: .top, endPoint: .bottom)
                    .frame(width: 60, height: 60).clipShape(Circle())
                Image(systemName: "gift.fill").font(.system(size: 26)).foregroundStyle(AppColors.primaryDeep)
            }
            .padding(.top, 28)
            Text(String(localized: "promo.announce.eyebrow"))
                .font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(AppColors.accent)
            Text(String(format: String(localized: "promo.announce.title"), LaunchPromo.endDateText))
                .font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "promo.announce.body"))
                .font(.system(size: 15)).foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(promoPerks, id: \.self) { perk in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(AppColors.accent)
                        Text(perk).font(.system(size: 14)).foregroundStyle(.white.opacity(0.92))
                    }
                }
            }
            .padding(.top, 4)
            Text(String(format: String(localized: "promo.announce.period"), LaunchPromo.endDateText))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.accent)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(AppColors.accent.opacity(0.12)).clipShape(Capsule())
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var footer: some View {
        HStack {
            Button { dontShowToday.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: dontShowToday ? "checkmark.square.fill" : "square")
                        .foregroundStyle(dontShowToday ? AppColors.accent : .white.opacity(0.6))
                    Text(String(localized: "announce.dismiss.today")).font(.system(size: 14)).foregroundStyle(.white.opacity(0.85))
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button(String(localized: isPromo ? "promo.announce.cta" : "common.close")) { onClose(dontShowToday) }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isPromo ? AppColors.accent : .white)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }
}
