import SwiftData
import XCTest
@testable import WatchAccuracyPro

/// 커버리지 보강 — WatchDeletion.swift 의 context 없이 안전한 순수 헬퍼.
///   · Watch.setPrimary (isPrimary invariant, Hard Rule 9) — in-memory context 사용, cascade-delete 아님.
///   · Notification.Name 확장 raw 값.
///
/// cascade-delete (deleteCascade) 는 NotificationService/Spotlight/파일시스템 side effect 가 있어 제외.
/// in-memory ModelContainer 스키마는 ModelTests.swift 패턴을 그대로 미러링.
@MainActor
final class WatchDeletionBranchTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Watch.self, WatchMeasurement.self, SpecCard.self,
                             WearLog.self, ServiceLog.self, JournalEntry.self,
                             Strap.self, WatchPhoto.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Watch.setPrimary invariant

    func test_setPrimary_sets_target_primary() {
        let a = Watch(brand: "Omega", model: "Speedmaster")
        context.insert(a)
        try? context.save()

        let ok = Watch.setPrimary(a, in: context)
        XCTAssertTrue(ok)
        XCTAssertTrue(a.isPrimary)
    }

    func test_setPrimary_clears_other_primaries() {
        // 컬렉션 내 단 1개만 isPrimary=true 보장 (Hard Rule 9).
        let a = Watch(brand: "Rolex", model: "Submariner", isPrimary: true)
        let b = Watch(brand: "Tudor", model: "Black Bay")
        context.insert(a)
        context.insert(b)
        try? context.save()

        _ = Watch.setPrimary(b, in: context)
        XCTAssertTrue(b.isPrimary, "새 target 은 primary")
        XCTAssertFalse(a.isPrimary, "기존 primary 는 해제돼야 한다")

        // 컬렉션 전체에서 primary 는 정확히 1개.
        let primaries = (try? context.fetch(
            FetchDescriptor<Watch>(predicate: #Predicate { $0.isPrimary })
        )) ?? []
        XCTAssertEqual(primaries.count, 1)
        XCTAssertEqual(primaries.first?.id, b.id)
    }

    func test_setPrimary_idempotent_on_already_primary() {
        let a = Watch(brand: "IWC", model: "Portugieser", isPrimary: true)
        context.insert(a)
        try? context.save()

        let ok = Watch.setPrimary(a, in: context)
        XCTAssertTrue(ok)
        XCTAssertTrue(a.isPrimary)
        let primaries = (try? context.fetch(
            FetchDescriptor<Watch>(predicate: #Predicate { $0.isPrimary })
        )) ?? []
        XCTAssertEqual(primaries.count, 1)
    }

    // MARK: - Notification.Name 확장

    func test_notification_names_raw_values() {
        XCTAssertEqual(Notification.Name.ticklabWatchWillDelete.rawValue, "ticklab.watch.willDelete")
        XCTAssertEqual(Notification.Name.ticklabMeasurementDidStart.rawValue, "ticklab.measurement.didStart")
        XCTAssertEqual(Notification.Name.ticklabMeasurementDidEnd.rawValue, "ticklab.measurement.didEnd")
        XCTAssertEqual(Notification.Name.ticklabProEntitlementChanged.rawValue, "ticklab.pro.changed")
    }
}
