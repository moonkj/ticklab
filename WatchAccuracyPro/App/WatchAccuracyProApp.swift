import SwiftData
import SwiftUI

@main
struct WatchAccuracyProApp: App {
    @State private var preferences = UserPreferences()
    let container: ModelContainer

    init() {
        // Round 133 사용자 보고: 오늘/일기 탭 상단 제목이 흰색으로 보이지 않음.
        // SwiftUI 의 toolbarColorScheme 만으론 large title 색상이 시스템 default(흰색) 로 잡히는 케이스 발견.
        // UINavigationBarAppearance 로 large/inline 제목 색을 명시적으로 검은색 강제.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(AppColors.paper0)
        appearance.titleTextAttributes = [.foregroundColor: UIColor(AppColors.ink0)]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(AppColors.ink0)]
        appearance.shadowColor = .clear  // hairline 제거
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance

        let prefs = UserPreferences()
        // 1차: 디스크 store. 실패하면(Phase 2 schema 변경 + 기존 store mismatch 등) in-memory 로 폴백.
        // 폴백은 사용자가 시뮬레이터/디바이스 데이터 정리하기 전까지 임시 유지.
        let attempted: ModelContainer
        var didFallback = false
        do {
            attempted = try Self.makeContainer(iCloud: prefs.iCloudSyncEnabled, inMemory: false)
        } catch {
            print("⚠️ Disk ModelContainer failed (\(error)) — falling back to in-memory store. " +
                  "Erase the app/simulator data to recover persistent storage.")
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
        }
    }

    static func makeContainer(iCloud: Bool, inMemory: Bool) throws -> ModelContainer {
        let schema = Schema([
            Watch.self,
            WatchMeasurement.self,
            JournalEntry.self,
            ServiceLog.self,
            WearLog.self,
            SpecCard.self
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
        return try! ModelContainer(
            for: Watch.self, WatchMeasurement.self,
            JournalEntry.self, ServiceLog.self, WearLog.self, SpecCard.self,
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
        let descriptor = FetchDescriptor<WatchMeasurement>()
        guard let all = try? context.fetch(descriptor) else { return }
        var deleted = 0
        for m in all where abs(m.rateSecondsPerDay) > 300 || m.beatErrorMs > 100 {
            context.delete(m)
            deleted += 1
        }
        if deleted > 0 {
            try? context.save()
            print("ℹ️ Cleaned up \(deleted) anomalous measurements from previous build.")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(preferences)
                // Round 51: 앱 전체 light mode 강제 — paper0 배경 + 시스템 dark 텍스트 흰색 conflict 해결.
                // DialFortuneView 와 LockScreenView 는 자체 .preferredColorScheme(.dark) 로 override.
                .preferredColorScheme(.light)
        }
        .modelContainer(container)
    }
}

private struct RootView: View {
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var showFallbackAlert = UserDefaults.standard.bool(forKey: "ticklab.lastLaunchUsedInMemoryFallback")
    @State private var isUnlocked: Bool = false
    @State private var lastBackgroundedAt: Date?
    @Query private var allWatches: [Watch]

    private var needsLock: Bool {
        preferences.appLockEnabled && !isUnlocked
    }

    var body: some View {
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
                }
            } else {
                RootTabView()
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
            if newValue { isUnlocked = false }
        }
        .task {
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
            }
            // 일자 변경 시 mood 캐시 stale 가능성 → 전체 invalidate.
            if let bg = lastBackgroundedAt,
               !Calendar.current.isDate(bg, inSameDayAs: Date()) {
                WatchMoodService.invalidateAll()
            }
            lastBackgroundedAt = nil
        @unknown default: break
        }
    }
}
