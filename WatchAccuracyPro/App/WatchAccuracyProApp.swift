import SwiftData
import SwiftUI
import UserNotifications

@main
struct WatchAccuracyProApp: App {
    @State private var preferences: UserPreferences
    let container: ModelContainer

    init() {
        // Round 14 (Doyoon): @State var preferences + let prefs = UserPreferences() 두 instance 의
        //   divergent state 위험 — 단일 instance 만 만들고 @State 와 container init 양쪽에 공유.
        let prefs = UserPreferences()
        _preferences = State(initialValue: prefs)
        // Round 19 (사용자 보고: "오늘의 시계 뽑기 알람 안 옴"):
        //   foreground 시 알림 banner 가 보이지 않던 원인 — UNUserNotificationCenterDelegate 미등록.
        //   willPresent 에서 [.banner, .sound, .list] 반환해야 노출됨.
        UNUserNotificationCenter.current().delegate = TickLabNotificationDelegate.shared
        // 사용자 보고: 풀와인딩 안내 토스트가 직전 빌드의 인라인 dismiss 로 24h 차단됨.
        //   일회성 migration: timestamp reset → 새 modal 카드 1회 표시 후 정상 정책 적용.
        if !UserDefaults.standard.bool(forKey: "ticklab.windingHintMigrationV2Done") {
            UserDefaults.standard.removeObject(forKey: "ticklab.windingHintShownAt")
            UserDefaults.standard.set(true, forKey: "ticklab.windingHintMigrationV2Done")
        }
        // Round 133 사용자 보고: 오늘/일기 탭 상단 제목이 흰색으로 보이지 않음.
        // SwiftUI 의 toolbarColorScheme 만으론 large title 색상이 시스템 default(흰색) 로 잡히는 케이스 발견.
        // UINavigationBarAppearance 로 large/inline 제목 색을 명시적으로 검은색 강제.
        // 밤의 워치 다크 테마: paper0/ink0 가 적응형 UIColor 이므로 그대로 넘기면
        //   nav bar 도 라이트/다크에 따라 자동으로 배경·제목색을 전환한다(스냅샷 금지).
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.059, green: 0.067, blue: 0.094, alpha: 1)  // #0F1118
                : UIColor(red: 0.980, green: 0.980, blue: 0.969, alpha: 1)  // #FAFAF7
        }
        let titleColor = UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1)  // #F2F2F7
                : UIColor(red: 0.102, green: 0.106, blue: 0.180, alpha: 1)  // #1A1B2E
        }
        appearance.titleTextAttributes = [.foregroundColor: titleColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: titleColor]
        appearance.shadowColor = .clear  // hairline 제거
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance

        // 1차: 디스크 store. 실패하면(Phase 2 schema 변경 + 기존 store mismatch 등) in-memory 로 폴백.
        // 폴백은 사용자가 시뮬레이터/디바이스 데이터 정리하기 전까지 임시 유지.
        let attempted: ModelContainer
        var didFallback = false
        do {
            // Apple guideline 2.3.1 fix: CloudKit entitlement 없는 상태에서 iCloud 활성화 시 crash.
            //   Phase 1 은 항상 local 만 사용. iCloud 토글은 Phase 3 에 entitlement 추가 후 활성화.
            attempted = try Self.makeContainer(iCloud: false, inMemory: false)
        } catch {
            #if DEBUG
            print("⚠️ Disk ModelContainer failed (\(error)) — falling back to in-memory store. " +
                  "Erase the app/simulator data to recover persistent storage.")
            #endif
            didFallback = true
            attempted = (try? Self.makeContainer(iCloud: false, inMemory: true))
                ?? Self.emergencyInMemoryContainer()
        }
        container = attempted
        // Round 2 (Hyemi/Min): 폴백 발생 시 사용자에게 알림.
        // Round 38 (사용자 답답함): 매 launch fallback 이면 매번 alert 뜨던 버그.
        // 한 번 ack 한 사용자는 다시 안 띄움 ("ticklab.fallbackAcknowledged" 영구).
        let ackedPreviously = UserDefaults.standard.bool(forKey: "ticklab.fallbackAcknowledged")
        UserDefaults.standard.set(didFallback && !ackedPreviously, forKey: "ticklab.lastLaunchUsedInMemoryFallback")
        // Round 141 (Min H8): 동기 cleanup 이 cold launch UI block → 비동기로 이전.
        let cleanupContainer = container
        Task.detached(priority: .utility) {
            Self.cleanupAnomalousMeasurements(in: cleanupContainer)
        }

        let autoOTA = UserDefaults.standard.object(forKey: "ticklab.autoUpdateMovementDB") as? Bool ?? false
        if autoOTA, !Self.isRunningInsideXCTest {
            Task.detached(priority: .background) {
                try? await MovementDBOTAService.shared.updateIfAvailable()
            }
        }
        // Round 149 (Hyemi 7 C1+C2 Critical): listener 동기 attach + currentEntitlements 즉시 replay.
        // 동기 호출로 Transaction.updates 와의 race 최소화. restore() 가 refunded/revoked entitlement 검증.
        if !Self.isRunningInsideXCTest {
            ProEntitlement.shared.startTransactionListener()
            Task.detached(priority: .userInitiated) {
                await ProEntitlement.shared.restore()
            }
            // Sprint 2 (P0-5.1): MetricKit 구독 시작 — hang/crash diagnostic 수집.
            MetricKitSubscriber.shared.start()
        }
    }

    static func makeContainer(iCloud: Bool, inMemory: Bool) throws -> ModelContainer {
        let schema = Schema([
            Watch.self,
            WatchMeasurement.self,
            JournalEntry.self,
            ServiceLog.self,
            WearLog.self,
            SpecCard.self,
            Strap.self,        // Sprint 5 (P3-1)
            WatchPhoto.self,   // Sprint 7 (P2-4)
            WishlistItem.self  // Sprint 9 (P2-19)
        ])
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if iCloud {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private("iCloud.com.ticklab.watchaccuracypro")
            )
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// makeContainer 의 in-memory 모드가 throw 하면 호출 — 의도적으로 실패하지 않게 강제 unwrap 직전 한 번 더 시도.
    private static func emergencyInMemoryContainer() -> ModelContainer {
        let cfg = ModelConfiguration(isStoredInMemoryOnly: true)
        // makeContainer 와 동일한 9개 모델 등록 — 누락 시(Strap/WatchPhoto/WishlistItem) 해당 화면에서
        //   'model not found in schema' 크래시. 비상 컨테이너도 풀 스키마로 맞춘다.
        return try! ModelContainer(
            for: Watch.self, WatchMeasurement.self,
            JournalEntry.self, ServiceLog.self, WearLog.self, SpecCard.self,
            Strap.self, WatchPhoto.self, WishlistItem.self,
            configurations: cfg
        )
    }

    /// XCTest 가 호스팅한 경우 BGTaskScheduler 등록을 건너뛰기 위한 휴리스틱.
    private static var isRunningInsideXCTest: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
    }

    /// 이전 빌드의 BPH 추정 버그로 저장된 비현실적 측정 정리.
    /// rate |s/d| > 300 또는 beat error > 100ms 인 측정 삭제.
    /// (실 시계는 |rate| ≤ 60 s/d, beat error ≤ 5 ms 가 정상.)
    private static func cleanupAnomalousMeasurements(in container: ModelContainer) {
        let context = ModelContext(container)
        // Round 14 (Sora): no-predicate full fetch + in-memory scan → SwiftData predicate push-down.
        // 5000 row 시 cold launch I/O 대폭 감소.
        let descriptor = FetchDescriptor<WatchMeasurement>(
            predicate: #Predicate { $0.rateSecondsPerDay > 300 || $0.rateSecondsPerDay < -300 || $0.beatErrorMs > 100 }
        )
        guard let anomalies = try? context.fetch(descriptor), !anomalies.isEmpty else { return }
        for m in anomalies {
            context.delete(m)
        }
        try? context.save()
        #if DEBUG
        print("ℹ️ Cleaned up \(anomalies.count) anomalous measurements from previous build.")
        #endif
    }

    /// 밤의 워치 테마 선택 → SwiftUI colorScheme. system=nil(기기 설정 따름).
    /// 다크 테마 완성 전까지: FeatureFlags.darkModeEnabled OFF 면 시스템이 다크여도 항상 라이트 강제.
    private var preferredColorScheme: ColorScheme? {
        guard FeatureFlags.shared.darkModeEnabled else { return .light }
        switch preferences.appearance {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(preferences)
                .preferredColorScheme(preferredColorScheme)
                // 매우 큰 Dynamic Type 에서 layout 깨짐 방지 — accessibility3 까지 허용.
                .dynamicTypeSize(.xSmall ... .accessibility3)
        }
        .modelContainer(container)
    }
}

/// 콜드스타트 스플래시 1회 게이트(in-memory). process lifetime 동안 단 한 번만 true.
/// 웜 재진입(scenePhase active 복귀)에서는 이미 false → 스플래시 skip.
/// 콜드스타트 스플래시 게이트(앱 전역). RootTabView 가 공지를 스플래시 종료 후로 미루는 데 참조 → internal.
enum LaunchGate {
    static var shouldShowSplash = true
}

private struct RootView: View {
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var showFallbackAlert = UserDefaults.standard.bool(forKey: "ticklab.lastLaunchUsedInMemoryFallback")
    @State private var isUnlocked: Bool = false
    @State private var lastBackgroundedAt: Date?
    // 콜드스타트 1회 스플래시 — LaunchGate 의 process-wide flag 를 view 진입 시 1회 캡처.
    @State private var showSplash = LaunchGate.shouldShowSplash
    @Query(sort: \Watch.createdAt, order: .reverse) private var allWatches: [Watch]

    private var needsLock: Bool {
        preferences.appLockEnabled && !isUnlocked
    }

    var body: some View {
        mainContent
            .overlay {
                if showSplash {
                    LaunchBridgeView {
                        LaunchGate.shouldShowSplash = false
                        showSplash = false
                    }
                    .transition(.opacity.combined(with: .scale(scale: 1.08)))
                    .zIndex(10)
                }
            }
            // 앱 잠금 활성 + 비활성/백그라운드(앱스위처·Control Center) 시 민감정보(시리얼·구매가 등)를
            //   멀티태스킹 스냅샷에서 가린다. .active 복귀하면 사라지고, 필요 시 잠금화면이 이어받음.
            .overlay {
                if preferences.appLockEnabled && scenePhase != .active && !showSplash {
                    ZStack {
                        AppColors.primaryDeep.ignoresSafeArea()
                        Image(systemName: "lock.fill")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(AppColors.accent)
                    }
                    .zIndex(30)
                }
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if needsLock {
                // Round 157: 와이어프레임 W_LOCK — cold-start / background 복귀 시 표시.
                LockScreenView {
                    isUnlocked = true
                }
                .transition(.opacity)
            } else if !preferences.hasCompletedOnboarding {
                // Round 40 v3 pivot: 5단계 Welcome flow.
                WelcomeFlowView {
                    preferences.hasCompletedOnboarding = true
                    UserDefaults.standard.set(true, forKey: "ticklab.modeChosenOnce")
                    // 신규 사용자는 현재 버전으로 캐치업 → what's-new 안내를 보지 않음(기존 사용자 전용).
                    WhatsNew.markSeen(preferences)
                }
            } else {
                ZStack(alignment: .top) {
                    RootTabView()
                    // Sprint 2 (P0-2.2): 오프라인 시 상단 배너 노출.
                    OfflineBanner()
                        .animation(.easeInOut(duration: 0.2), value: NetworkMonitor.shared.isConnected)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhase(newPhase)
        }
        .alert(
            String(localized: "alert.store_fallback.title"),
            isPresented: $showFallbackAlert
        ) {
            Button(String(localized: "common.done"), role: .cancel) {
                UserDefaults.standard.set(false, forKey: "ticklab.lastLaunchUsedInMemoryFallback")
                UserDefaults.standard.set(true, forKey: "ticklab.fallbackAcknowledged")
            }
        } message: {
            Text(String(localized: "alert.store_fallback.message"))
        }
        .onChange(of: preferences.appLockEnabled) { _, newValue in
            // 토글을 켰을 때 즉시 unlock 상태 reset → lock 화면 등장.
            if newValue { isUnlocked = false; AppLockService.shared.relock() }
        }
        .task {
            // Round 172 (clock 보정): 최초 실행에 앵커(NTP↔monotonic) 설정. 이후 foreground 마다 갱신.
            await ClockCalibrationService.shared.calibrateNow()
            // 접속 누계 — 콜드 런치 1회 기록(운영 대시보드 집계용). 커뮤니티 활성 시에만.
            if FeatureFlags.shared.communityEnabled {
                Task { await CommunityService.shared.logAccess() }
            }
            // Round 152: launch 시 알림 재예약.
            // - 랜덤 시계 픽: 매일 단발 알림 → 매 launch 마다 새 watch 로 다시 예약.
            // - 수동감기 / Quartz 배터리: 기존 시계 설정에 따라 재예약 (idempotent — 같은 identifier 면 덮어씀).
            if preferences.randomPickEnabled {
                NotificationService.scheduleRandomPick(
                    watches: allWatches,
                    hour: preferences.randomPickHour,
                    minute: preferences.randomPickMinute,
                    enabled: true
                )
            }
            for w in allWatches {
                if w.movementType == .manual && w.windReminderEnabled {
                    NotificationService.scheduleWindReminder(for: w)
                }
                if w.movementType == .quartz && w.batteryReminderEnabled {
                    NotificationService.scheduleBatteryReminder(for: w)
                }
            }
            // Round 100 (QA Critical C1): journal reminder 앱 시작 시 재예약.
            // Round 129 (실기기 H9): 하드코딩 21:00 → preferences 저장값 사용.
            if preferences.journalReminderEnabled {
                NotificationService.scheduleJournalReminder(
                    enabled: true,
                    hour: preferences.journalReminderHour,
                    minute: preferences.journalReminderMinute
                )
            }
            // 사용자 요청: 오버홀 정비 리마인더 — launch 시 모든 시계 재스케줄.
            NotificationService.rescheduleAllOverhaulReminders(
                watches: allWatches,
                years: preferences.overhaulReminderYears,
                enabled: preferences.overhaulReminderEnabled,
                in: modelContext
            )
            // 로테이션 넛지(R6: 死코드 배선) — N일 미착용 시계 있으면 내일 9시 1회 알림(≤1개·비반복).
            // rotationNudgeEnabled 토글(기본 ON·Settings 제어) 게이트. 캘린더 권한 강제 안 함.
            if preferences.rotationNudgeEnabled {
                let wears = (try? modelContext.fetch(FetchDescriptor<WearLog>())) ?? []
                RotationNudgeService.scheduleIfNeeded(
                    watches: allWatches,
                    wearLogs: wears,
                    nudgeDays: preferences.rotationNudgeDays
                )
            }
        }
    }

    /// Round 157: 백그라운드 60초 이상이면 재 lock.
    /// Round 169: foreground 복귀 시 mood 캐시 무효화 (날짜 바뀌었을 수 있음).
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            if lastBackgroundedAt == nil { lastBackgroundedAt = Date() }
        case .active:
            if preferences.appLockEnabled,
               let bg = lastBackgroundedAt,
               Date().timeIntervalSince(bg) > 60 {
                isUnlocked = false
                AppLockService.shared.relock()   // 서비스 플래그도 동기화(자동 락)
            }
            // 일자 변경 시 mood 캐시 stale 가능성 → 전체 invalidate.
            if let bg = lastBackgroundedAt,
               !Calendar.current.isDate(bg, inSameDayAs: Date()) {
                WatchMoodService.invalidateAll()
            }
            // Sprint 2 (P1-1): 위젯에서 큐잉된 wear toggle 처리.
            WearLogService.consumePendingWearToggle(in: modelContext)
            // Sprint 13 (F3): On This Day 추억 알림 검사 (1일 1회 내부 제한).
            let wears = (try? modelContext.fetch(FetchDescriptor<WearLog>())) ?? []
            OnThisDayService.checkAndNotify(watches: allWatches, wearLogs: wears)
            // Round 172 (clock 보정): 앱 foreground 마다 NTP↔monotonic 점 누적 → 측정 안 해도
            //   사용할수록 발진기 드리프트 baseline 이 차서 rate 보정이 정확해진다.
            Task { await ClockCalibrationService.shared.calibrateNow() }
            // '현재 활동' presence — 앱 포그라운드마다 본인 하트비트(커뮤니티 활성 시).
            //   기존엔 커뮤니티 피드 열 때만 찍혀 '앱 실행 중인데 0명' 발생 → 포그라운드로 보강.
            if FeatureFlags.shared.communityEnabled {
                Task { await CommunityService.shared.heartbeat() }
                // 백그라운드에서 '의미 있는 시간(>3s)' 후 복귀 = 접속 1회. 콜드 런치는 .task 에서 별도 기록.
                //   런치 중 잠깐 .inactive→.active 깜빡임(<1s)은 제외해 콜드런치 이중 집계 방지.
                if let bg = lastBackgroundedAt, Date().timeIntervalSince(bg) > 3 {
                    Task { await CommunityService.shared.logAccess() }
                }
            }
            lastBackgroundedAt = nil
        @unknown default: break
        }
    }
}
