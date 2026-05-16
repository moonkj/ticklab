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
    @State private var selected: Tab = .collection

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
    /// Round 140 (Hyemi/Min H1 Critical): 측정 진행 중 탭 전환 시 epoch 증가가 측정 silent 폐기 유발.
    /// MeasurementViewModel.start/stop 이 notification post → 측정 중에는 epoch 증가 차단.
    @State private var measurementInProgress: Bool = false
    /// 사용자 보고 fix: 4 분산 sheet 호스트를 shell 레벨로 통합 — iPad multi-window race 차단 + 신규 진입점 추가 cost 감소.
    @State private var purchaseRouter = PurchaseRouter()

    enum Tab: Hashable {
        case collection
        case today
        case journal
        case stats
    }

    var body: some View {
        TabView(selection: Binding(
            get: { selected },
            set: { newTab in
                if newTab != selected {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                // Round 140 (Hyemi/Min H1 Critical): 측정 진행 중에는 deep state 보존 → epoch 증가 차단.
                // Round 19 (Hyemi): path reset 도 같이 guard — 이전엔 측정 중에도 NavigationPath 가 비워져
                //   detail context 사라지던 버그 (epoch reset 만 차단되고 path 는 그대로 reset 됐었음).
                let allowReset = !measurementInProgress
                switch newTab {
                case .collection:
                    if allowReset {
                        collectionPath = NavigationPath()
                        collectionEpoch &+= 1
                    }
                case .today:
                    if allowReset {
                        todayPath = NavigationPath()
                        todayEpoch &+= 1
                    }
                case .journal:
                    if allowReset {
                        journalPath = NavigationPath()
                        journalEpoch &+= 1
                    }
                case .stats:
                    if allowReset {
                        statsPath = NavigationPath()
                        statsEpoch &+= 1
                    }
                }
                selected = newTab
            }
        )) {
            CollectionView(path: $collectionPath)
                .id(collectionEpoch)
                .tabItem {
                    Label(String(localized: "tab.collection"), systemImage: "rectangle.grid.2x2")
                }
                .tag(Tab.collection)

            TodayView(path: $todayPath)
                .id(todayEpoch)
                .tabItem {
                    Label(String(localized: "tab.today"), systemImage: "sun.max")
                }
                .tag(Tab.today)

            JournalFeedView(path: $journalPath)
                .id(journalEpoch)
                .tabItem {
                    Label(String(localized: "tab.journal"), systemImage: "book.closed")
                }
                .tag(Tab.journal)

            StatsView(path: $statsPath)
                .id(statsEpoch)
                .tabItem {
                    Label(String(localized: "tab.stats"), systemImage: "chart.pie")
                }
                .tag(Tab.stats)
        }
        // 사용자 보고 fix: 글로벌 accent gold 가 alert 버튼까지 propagate → 가독성 ↓ (#C9A961 on white ~2.8:1).
        //   탭바 selected color 만 indigo 로 바꾸면 alert 도 indigo 로 또렷해짐. 명시적 .tint(accent) 오버라이드는 유지됨.
        .tint(AppColors.primaryDeep)
        .environment(\.purchaseRouter, purchaseRouter)
        // shell-level paywall — 한 번에 하나만 띄움. 4 분산 sheet 대체.
        .sheet(isPresented: $purchaseRouter.isPresenting) {
            PurchaseView()
                .environment(preferences)
        }
        // Round 140 (H1): MeasurementViewModel 의 start/end notification 받아 epoch reset 차단.
        .onReceive(NotificationCenter.default.publisher(for: .ticklabMeasurementDidStart)) { _ in
            measurementInProgress = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .ticklabMeasurementDidEnd)) { _ in
            measurementInProgress = false
        }
    }
}
