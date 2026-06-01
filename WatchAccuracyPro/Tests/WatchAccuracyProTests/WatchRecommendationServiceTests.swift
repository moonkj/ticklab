import SwiftData
import XCTest
@testable import WatchAccuracyPro

/// WatchRecommendationService.recommend 룰 우선순위 검증.
/// 서비스가 WearLog.watch (SwiftData 관계)를 접근하므로 인메모리 ModelContext 필요
/// (컨텍스트 없는 @Model 관계 접근은 크래시).
@MainActor
final class WatchRecommendationServiceTests: XCTestCase {
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
        container = nil; context = nil; super.tearDown()
    }

    @discardableResult
    private func insertWatch(_ brand: String, _ model: String, price: Decimal? = nil) -> Watch {
        let w = Watch(brand: brand, model: model, purchasePrice: price)
        context.insert(w)
        return w
    }

    @discardableResult
    private func insertLog(_ watch: Watch, daysAgo: Int) -> WearLog {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let log = WearLog(watch: watch, date: date)
        context.insert(log)
        return log
    }

    func test_recommend_nil_for_empty_watches() {
        XCTAssertNil(WatchRecommendationService.recommend(from: [], wearLogs: []))
    }

    func test_recommend_prefers_never_worn() throws {
        let worn = insertWatch("Rolex", "Submariner")
        let neverWorn = insertWatch("Seiko", "SARB065")
        let logs = [insertLog(worn, daysAgo: 3)]
        try context.save()

        let rec = try XCTUnwrap(WatchRecommendationService.recommend(from: [worn, neverWorn], wearLogs: logs))
        XCTAssertEqual(rec.watch.id, neverWorn.id)
        XCTAssertEqual(rec.reason, LocalizedStringResource("recommendation.reason.never_worn"))
    }

    func test_recommend_long_unworn_when_all_worn() throws {
        let recent = insertWatch("Omega", "Speedmaster")
        let old = insertWatch("Tudor", "Black Bay")
        let logs = [insertLog(recent, daysAgo: 1), insertLog(old, daysAgo: 30)]
        try context.save()

        let rec = try XCTUnwrap(WatchRecommendationService.recommend(from: [recent, old], wearLogs: logs))
        XCTAssertEqual(rec.watch.id, old.id)
        XCTAssertEqual(rec.reason, LocalizedStringResource("recommendation.reason.long_unworn"))
    }

    func test_recommend_excludes_worn_today() throws {
        let only = insertWatch("IWC", "Portugieser")
        let logs = [insertLog(only, daysAgo: 0)]
        try context.save()
        XCTAssertNil(WatchRecommendationService.recommend(from: [only], wearLogs: logs))
    }

    func test_recommend_rotation_when_all_recently_worn_no_price() throws {
        let a = insertWatch("A", "1")
        let b = insertWatch("B", "2")
        let logs = [insertLog(a, daysAgo: 2), insertLog(b, daysAgo: 1)]
        try context.save()

        let rec = try XCTUnwrap(WatchRecommendationService.recommend(from: [a, b], wearLogs: logs))
        XCTAssertEqual(rec.reason, LocalizedStringResource("recommendation.reason.rotation"))
    }

    func test_recommend_low_roi_when_priced_recently_worn() throws {
        let cheap = insertWatch("Casio", "F91W", price: 20)
        let pricey = insertWatch("AP", "RO", price: 50_000)
        // 둘 다 최근 착용(7일 미만), 가격 보유 → ROI 경로. pricey 착용 적음 → 선택.
        let logs = [insertLog(cheap, daysAgo: 1), insertLog(cheap, daysAgo: 2), insertLog(pricey, daysAgo: 3)]
        try context.save()

        let rec = try XCTUnwrap(WatchRecommendationService.recommend(from: [cheap, pricey], wearLogs: logs))
        XCTAssertEqual(rec.reason, LocalizedStringResource("recommendation.reason.low_roi"))
        XCTAssertEqual(rec.watch.id, pricey.id)
    }
}
