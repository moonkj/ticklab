import SwiftData
import XCTest
@testable import WatchAccuracyPro

/// PURE date-based 커버리지: WeeklyCheckService.summary — 측정 경과일 기준 점검 대기 분류.
/// w.measurements(릴레이션십)을 순회하므로 in-memory ModelContext 필요.
/// WeeklyCheckService 는 @MainActor enum → 클래스도 @MainActor.
@MainActor
final class WeeklyCheckServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Watch.self, WatchMeasurement.self, WearLog.self,
                             JournalEntry.self, ServiceLog.self, SpecCard.self])
        container = try ModelContainer(for: schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    private func daysAgo(_ d: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -d, to: Date())!
    }

    @discardableResult
    private func insertWatch(brand: String, model: String,
                             movement: WatchMovementType) -> Watch {
        let w = Watch(brand: brand, model: model, movementType: movement)
        context.insert(w)
        return w
    }

    private func addMeasurement(to watch: Watch, daysAgo days: Int) {
        let m = WatchMeasurement(watch: watch, timestamp: daysAgo(days),
                                 rateSecondsPerDay: 0, beatErrorMs: 0,
                                 bph: 28_800, confidenceScore: 90, durationSeconds: 30)
        context.insert(m)
        watch.measurements.append(m)
    }

    // MARK: - staleDays constant

    func test_staleDays_isSeven() {
        XCTAssertEqual(WeeklyCheckService.staleDays, 7)
    }

    // MARK: - neverMeasured

    func test_mechanicalNeverMeasured_goesToNeverMeasured() throws {
        let w = insertWatch(brand: "Omega", model: "Speedmaster", movement: .automatic)
        try context.save()

        let summary = WeeklyCheckService.summary(watches: [w])
        XCTAssertEqual(summary.neverMeasured.count, 1)
        XCTAssertEqual(summary.needsCheck.count, 0)
        XCTAssertEqual(summary.total, 1)
    }

    // MARK: - quartz excluded entirely

    func test_quartzWatch_excluded_evenIfNeverMeasured() throws {
        let q = insertWatch(brand: "Casio", model: "F-91W", movement: .quartz)
        try context.save()

        let summary = WeeklyCheckService.summary(watches: [q])
        XCTAssertEqual(summary.neverMeasured.count, 0, "쿼츠는 점검 대상 아님")
        XCTAssertEqual(summary.needsCheck.count, 0)
        XCTAssertEqual(summary.total, 0)
    }

    // MARK: - needsCheck threshold

    func test_measuredOverSevenDaysAgo_needsCheck() throws {
        let w = insertWatch(brand: "Rolex", model: "Sub", movement: .automatic)
        addMeasurement(to: w, daysAgo: 10)
        try context.save()

        let summary = WeeklyCheckService.summary(watches: [w])
        XCTAssertEqual(summary.needsCheck.count, 1)
        XCTAssertEqual(summary.neverMeasured.count, 0)
    }

    func test_measuredRecently_notInAnyBucket() throws {
        let w = insertWatch(brand: "Tudor", model: "BB58", movement: .automatic)
        addMeasurement(to: w, daysAgo: 2)
        try context.save()

        let summary = WeeklyCheckService.summary(watches: [w])
        XCTAssertEqual(summary.needsCheck.count, 0)
        XCTAssertEqual(summary.neverMeasured.count, 0)
        XCTAssertEqual(summary.total, 0)
    }

    func test_onlyLatestMeasurementCounts() throws {
        // 오래된 측정과 최근 측정이 둘 다 있으면 최신 기준 → 점검 불필요.
        let w = insertWatch(brand: "Seiko", model: "SPB", movement: .automatic)
        addMeasurement(to: w, daysAgo: 30)
        addMeasurement(to: w, daysAgo: 1)
        try context.save()

        let summary = WeeklyCheckService.summary(watches: [w])
        XCTAssertEqual(summary.needsCheck.count, 0, "최신 측정이 최근이면 점검 불필요")
    }

    // MARK: - needsCheck sort order (oldest first)

    func test_needsCheck_sortedOldestFirst() throws {
        let recent = insertWatch(brand: "A", model: "recent", movement: .automatic)
        addMeasurement(to: recent, daysAgo: 8)
        let oldest = insertWatch(brand: "B", model: "oldest", movement: .manual)
        addMeasurement(to: oldest, daysAgo: 40)
        try context.save()

        let summary = WeeklyCheckService.summary(watches: [recent, oldest])
        XCTAssertEqual(summary.needsCheck.count, 2)
        // 오래된 순 → 가장 오래된(40일) 측정이 먼저.
        XCTAssertEqual(summary.needsCheck.first?.model, "oldest")
        XCTAssertEqual(summary.needsCheck.last?.model, "recent")
    }

    // MARK: - mixed collection total

    func test_mixedCollection_totalCombinesBuckets() throws {
        let never = insertWatch(brand: "X", model: "never", movement: .automatic)
        let stale = insertWatch(brand: "Y", model: "stale", movement: .manual)
        addMeasurement(to: stale, daysAgo: 14)
        let quartz = insertWatch(brand: "Z", model: "quartz", movement: .quartz)
        let fresh = insertWatch(brand: "W", model: "fresh", movement: .automatic)
        addMeasurement(to: fresh, daysAgo: 1)
        try context.save()

        let summary = WeeklyCheckService.summary(watches: [never, stale, quartz, fresh])
        XCTAssertEqual(summary.neverMeasured.count, 1)
        XCTAssertEqual(summary.needsCheck.count, 1)
        XCTAssertEqual(summary.total, 2)  // never + stale (quartz·fresh 제외)
    }

    func test_emptyInput_emptySummary() {
        let summary = WeeklyCheckService.summary(watches: [])
        XCTAssertEqual(summary.total, 0)
    }
}
