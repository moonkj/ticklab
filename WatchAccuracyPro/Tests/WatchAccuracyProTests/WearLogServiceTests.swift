import SwiftData
import XCTest
@testable import WatchAccuracyPro

/// INFRA-1 (Sprint 2): WearLogService 핵심 로직 단위 테스트.
@MainActor
final class WearLogServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let appGroupKey = "ticklab.pendingWearToggleAt"
    private let appGroupID = "group.com.ticklab.watchaccuracypro"

    override func setUpWithError() throws {
        let schema = Schema([Watch.self, WatchMeasurement.self, WearLog.self,
                             JournalEntry.self, ServiceLog.self, SpecCard.self])
        container = try ModelContainer(for: schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
        // App Group 대신 standard defaults 사용 (test sandbox).
        UserDefaults.standard.removeObject(forKey: appGroupKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: appGroupKey)
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - toggleToday

    func test_toggleToday_adds_log_when_none() {
        let watch = Watch(brand: "Omega", model: "Speedmaster")
        context.insert(watch)
        try? context.save()

        let added = WearLogService.toggleToday(watch, in: context)
        XCTAssertTrue(added)

        let count = WearLogService.wearCount(for: watch, in: context)
        XCTAssertEqual(count, 1)
    }

    func test_toggleToday_removes_log_when_exists() {
        let watch = Watch(brand: "Rolex", model: "Submariner")
        context.insert(watch)
        try? context.save()

        _ = WearLogService.toggleToday(watch, in: context)
        let removed = WearLogService.toggleToday(watch, in: context)

        XCTAssertFalse(removed)
        XCTAssertEqual(WearLogService.wearCount(for: watch, in: context), 0)
    }

    func test_isWornToday_true_after_toggle() {
        let watch = Watch(brand: "IWC", model: "Portugieser")
        context.insert(watch)
        try? context.save()
        _ = WearLogService.toggleToday(watch, in: context)
        XCTAssertTrue(WearLogService.isWornToday(watch, in: context))
    }

    func test_isWornToday_false_before_toggle() {
        let watch = Watch(brand: "Patek", model: "Nautilus")
        context.insert(watch)
        try? context.save()
        XCTAssertFalse(WearLogService.isWornToday(watch, in: context))
    }

    // MARK: - wearCount

    func test_wearCount_zero_for_new_watch() {
        let watch = Watch(brand: "Seiko", model: "SARB065")
        context.insert(watch)
        try? context.save()
        XCTAssertEqual(WearLogService.wearCount(for: watch, in: context), 0)
    }

    // MARK: - consumePendingWearToggle

    func test_consumePendingWearToggle_does_nothing_without_pending() {
        let watch = Watch(brand: "Tudor", model: "Black Bay")
        context.insert(watch)
        let measurement = WatchMeasurement(watch: watch, rateSecondsPerDay: 2.0,
                                           beatErrorMs: 0.3, amplitudeDegrees: nil,
                                           bph: 28800, confidenceScore: 85,
                                           durationSeconds: 30)
        context.insert(measurement)
        try? context.save()

        // pending flag 없음 → toggle 안 됨.
        WearLogService.consumePendingWearToggle(in: context)
        XCTAssertFalse(WearLogService.isWornToday(watch, in: context))
    }

    /// 감사 수정: consume 은 blind toggle 이 아니라 위젯이 낙관적으로 기록한 desired 상태로 맞춘다.
    func test_consumePendingWearToggle_reconciles_to_desired_worn() {
        let watch = Watch(brand: "Grand Seiko", model: "Snowflake")
        context.insert(watch)
        context.insert(WatchMeasurement(watch: watch, rateSecondsPerDay: 1.0, beatErrorMs: 0.2,
                                        amplitudeDegrees: nil, bph: 28800, confidenceScore: 80, durationSeconds: 30))
        try? context.save()
        SharedSnapshotStore.writeWornToday(true)   // 위젯 낙관적 flip → worn
        SharedSnapshotStore.defaults?.set(Date().timeIntervalSince1970, forKey: SharedSnapshotStore.pendingWearToggleKey)
        defer {
            SharedSnapshotStore.defaults?.removeObject(forKey: SharedSnapshotStore.pendingWearToggleKey)
            SharedSnapshotStore.defaults?.removeObject(forKey: SharedSnapshotStore.wornTodayKey)
        }
        WearLogService.consumePendingWearToggle(in: context)
        XCTAssertTrue(WearLogService.isWornToday(watch, in: context), "desired worn=true → 착용 기록 생성")
    }

    func test_consumePendingWearToggle_reconciles_to_desired_unworn() {
        let watch = Watch(brand: "Zenith", model: "El Primero")
        context.insert(watch)
        context.insert(WatchMeasurement(watch: watch, rateSecondsPerDay: 1.0, beatErrorMs: 0.2,
                                        amplitudeDegrees: nil, bph: 36000, confidenceScore: 80, durationSeconds: 30))
        _ = WearLogService.toggleToday(watch, in: context)   // 이미 착용 상태
        try? context.save()
        XCTAssertTrue(WearLogService.isWornToday(watch, in: context))
        SharedSnapshotStore.writeWornToday(false)   // 위젯 낙관적 flip → unworn
        SharedSnapshotStore.defaults?.set(Date().timeIntervalSince1970, forKey: SharedSnapshotStore.pendingWearToggleKey)
        defer {
            SharedSnapshotStore.defaults?.removeObject(forKey: SharedSnapshotStore.pendingWearToggleKey)
            SharedSnapshotStore.defaults?.removeObject(forKey: SharedSnapshotStore.wornTodayKey)
        }
        WearLogService.consumePendingWearToggle(in: context)
        XCTAssertFalse(WearLogService.isWornToday(watch, in: context), "desired worn=false → 착용 해제")
    }
}
