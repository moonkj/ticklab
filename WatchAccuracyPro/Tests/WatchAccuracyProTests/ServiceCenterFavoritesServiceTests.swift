import XCTest
@testable import WatchAccuracyPro

/// ServiceCenterFavoritesService — UserDefaults 백킹 LRU 즐겨찾기(최대 20개).
/// 순수 CRUD. UserDefaults.standard 사용이므로 setUp/tearDown 에서 키를 정리/복원한다.
final class ServiceCenterFavoritesServiceTests: XCTestCase {

    private let key = "ticklab.serviceCenterFavorites"
    private let defaults = UserDefaults.standard
    private var snapshot: Any?

    override func setUp() {
        super.setUp()
        snapshot = defaults.object(forKey: key)
        defaults.removeObject(forKey: key)
    }

    override func tearDown() {
        if let snapshot {
            defaults.set(snapshot, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        snapshot = nil
        super.tearDown()
    }

    func test_all_empty_when_unset() {
        XCTAssertEqual(ServiceCenterFavoritesService.all, [])
    }

    func test_recordUsage_adds_entry() {
        ServiceCenterFavoritesService.recordUsage("Rolex Service Center")
        XCTAssertEqual(ServiceCenterFavoritesService.all, ["Rolex Service Center"])
    }

    func test_recordUsage_trims_whitespace() {
        ServiceCenterFavoritesService.recordUsage("  Omega Boutique  ")
        XCTAssertEqual(ServiceCenterFavoritesService.all, ["Omega Boutique"])
    }

    func test_recordUsage_empty_or_whitespace_is_ignored() {
        ServiceCenterFavoritesService.recordUsage("")
        ServiceCenterFavoritesService.recordUsage("    ")
        XCTAssertTrue(ServiceCenterFavoritesService.all.isEmpty)
    }

    func test_recordUsage_moves_existing_to_front_lru() {
        ServiceCenterFavoritesService.recordUsage("A")
        ServiceCenterFavoritesService.recordUsage("B")
        ServiceCenterFavoritesService.recordUsage("C")
        // 다시 A 사용 → 최상위로 이동, 중복 없음.
        ServiceCenterFavoritesService.recordUsage("A")
        XCTAssertEqual(ServiceCenterFavoritesService.all, ["A", "C", "B"])
    }

    func test_recordUsage_caps_at_twenty() {
        for i in 0..<25 {
            ServiceCenterFavoritesService.recordUsage("Center \(i)")
        }
        let all = ServiceCenterFavoritesService.all
        XCTAssertEqual(all.count, 20, "최대 20개로 cap")
        // 가장 최근(마지막 삽입)이 맨 앞.
        XCTAssertEqual(all.first, "Center 24")
        // 가장 오래된 5개는 잘려나감.
        XCTAssertFalse(all.contains("Center 0"))
        XCTAssertFalse(all.contains("Center 4"))
        XCTAssertTrue(all.contains("Center 5"))
    }

    func test_remove_deletes_entry() {
        ServiceCenterFavoritesService.recordUsage("X")
        ServiceCenterFavoritesService.recordUsage("Y")
        ServiceCenterFavoritesService.remove("X")
        XCTAssertEqual(ServiceCenterFavoritesService.all, ["Y"])
    }

    func test_remove_nonexistent_is_noop() {
        ServiceCenterFavoritesService.recordUsage("Z")
        ServiceCenterFavoritesService.remove("Nonexistent")
        XCTAssertEqual(ServiceCenterFavoritesService.all, ["Z"])
    }
}
