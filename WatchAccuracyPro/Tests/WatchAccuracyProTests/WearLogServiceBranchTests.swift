import SwiftData
import XCTest
@testable import WatchAccuracyPro

/// 커버리지 보강 — 기존 WearLogServiceTests 가 안 다루는 WearLogService 분기.
///   · ensureTodayWearOnMeasure (생성 / no-op)
///   · dailyCounts (일자별 카운트, 빈 결과)
///   · cumulativeByWatch (시계별 누적, 정렬)
///   · consumePendingWearToggle (pending 있지만 측정 없음 → no-op)
///
/// 기존 WearLogServiceTests 의 setUp 패턴(in-memory ModelContainer, @MainActor)을 그대로 미러링.
@MainActor
final class WearLogServiceBranchTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let appGroupKey = "ticklab.pendingWearToggleAt"

    override func setUpWithError() throws {
        let schema = Schema([Watch.self, WatchMeasurement.self, WearLog.self,
                             JournalEntry.self, ServiceLog.self, SpecCard.self])
        container = try ModelContainer(for: schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
        UserDefaults.standard.removeObject(forKey: appGroupKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: appGroupKey)
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - ensureTodayWearOnMeasure

    func test_ensureTodayWearOnMeasure_creates_log_when_none() {
        let watch = Watch(brand: "Grand Seiko", model: "SBGA211")
        context.insert(watch)
        try? context.save()

        XCTAssertFalse(WearLogService.isWornToday(watch, in: context))
        WearLogService.ensureTodayWearOnMeasure(watch, in: context)
        XCTAssertTrue(WearLogService.isWornToday(watch, in: context))
        XCTAssertEqual(WearLogService.wearCount(for: watch, in: context), 1)
    }

    func test_ensureTodayWearOnMeasure_is_noop_when_already_worn() {
        let watch = Watch(brand: "Cartier", model: "Tank")
        context.insert(watch)
        try? context.save()

        _ = WearLogService.toggleToday(watch, in: context)  // 이미 오늘 기록 존재
        WearLogService.ensureTodayWearOnMeasure(watch, in: context)
        // 중복 생성 안 됨 — 여전히 1.
        XCTAssertEqual(WearLogService.wearCount(for: watch, in: context), 1)
    }

    // MARK: - dailyCounts

    func test_dailyCounts_returns_requested_number_of_days() {
        let watch = Watch(brand: "Longines", model: "Spirit")
        context.insert(watch)
        try? context.save()
        _ = WearLogService.toggleToday(watch, in: context)

        let counts = WearLogService.dailyCounts(days: 7, in: context)
        XCTAssertEqual(counts.count, 7, "7일 요청 → 7개 버킷")
        // 마지막 버킷(오늘)에 1개 카운트.
        XCTAssertEqual(counts.last?.count, 1)
        // 이전 날들은 0.
        XCTAssertEqual(counts.first?.count, 0)
    }

    func test_dailyCounts_dates_are_ascending() {
        let watch = Watch(brand: "Oris", model: "Aquis")
        context.insert(watch)
        try? context.save()
        _ = WearLogService.toggleToday(watch, in: context)

        let counts = WearLogService.dailyCounts(days: 5, in: context)
        for i in 1..<counts.count {
            XCTAssertGreaterThan(counts[i].date, counts[i - 1].date, "날짜는 오름차순")
        }
    }

    func test_dailyCounts_empty_when_no_logs() {
        let counts = WearLogService.dailyCounts(days: 3, in: context)
        XCTAssertEqual(counts.count, 3)
        XCTAssertTrue(counts.allSatisfy { $0.count == 0 }, "기록 없으면 모두 0")
    }

    // MARK: - cumulativeByWatch

    func test_cumulativeByWatch_empty_when_no_logs() {
        XCTAssertTrue(WearLogService.cumulativeByWatch(in: context).isEmpty)
    }

    func test_cumulativeByWatch_counts_per_watch() {
        let a = Watch(brand: "A-brand", model: "A1")
        let b = Watch(brand: "B-brand", model: "B1")
        context.insert(a)
        context.insert(b)
        try? context.save()
        _ = WearLogService.toggleToday(a, in: context)
        _ = WearLogService.toggleToday(b, in: context)

        let result = WearLogService.cumulativeByWatch(in: context)
        XCTAssertEqual(result.count, 2, "두 시계 모두 누적에 포함")
        XCTAssertTrue(result.allSatisfy { $0.days == 1 })
    }

    // MARK: - consumePendingWearToggle (분기: pending 없음 / 측정 없음)

    func test_consumePendingWearToggle_noop_without_pending_flag() {
        // pending flag 미설정 → 즉시 return (no-op). 크래시 없음.
        let watch = Watch(brand: "Hamilton", model: "Khaki")
        context.insert(watch)
        try? context.save()
        WearLogService.consumePendingWearToggle(in: context)
        XCTAssertFalse(WearLogService.isWornToday(watch, in: context))
    }

    func test_consumePendingWearToggle_noop_when_no_measurement_exists() {
        // App Group suite 에 pending 설정했지만 측정 기록이 전혀 없으면 toggle 대상 없음 → no-op.
        let appGroupID = "group.com.ticklab.watchaccuracypro"
        let suite = UserDefaults(suiteName: appGroupID)
        suite?.set(Date().timeIntervalSince1970, forKey: appGroupKey)
        defer { suite?.removeObject(forKey: appGroupKey) }

        let watch = Watch(brand: "Sinn", model: "556")
        context.insert(watch)
        try? context.save()
        // WatchMeasurement 없음 → latest fetch nil → 조용히 종료.
        WearLogService.consumePendingWearToggle(in: context)
        XCTAssertFalse(WearLogService.isWornToday(watch, in: context))
        // pending flag 는 소비(clear)됐어야 한다 (early clear).
        XCTAssertNil(suite?.object(forKey: appGroupKey))
    }
}
