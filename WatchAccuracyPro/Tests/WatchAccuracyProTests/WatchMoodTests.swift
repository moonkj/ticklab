import XCTest
@testable import WatchAccuracyPro

/// WatchMoodService.Mood 의 순수 enum 로직만 검증.
/// status()/computeStatus() 는 ModelContext 필요 → 의도적으로 제외.
@MainActor
final class WatchMoodTests: XCTestCase {

    func test_all_moods_have_nonempty_emoji_and_label() {
        for mood in WatchMoodService.Mood.allCases {
            XCTAssertFalse(mood.emoji.isEmpty, "\(mood) emoji 비어있음")
            XCTAssertFalse(mood.label.isEmpty, "\(mood) label 비어있음")
        }
    }

    func test_energy_values_are_within_gauge_range() {
        for mood in WatchMoodService.Mood.allCases {
            XCTAssertGreaterThanOrEqual(mood.energy, 0, "\(mood) energy < 0")
            XCTAssertLessThanOrEqual(mood.energy, 100, "\(mood) energy > 100")
        }
    }

    func test_energy_exact_values() {
        XCTAssertEqual(WatchMoodService.Mood.energetic.energy, 100)
        XCTAssertEqual(WatchMoodService.Mood.happy.energy, 70)
        XCTAssertEqual(WatchMoodService.Mood.sleepy.energy, 40)
        XCTAssertEqual(WatchMoodService.Mood.dormant.energy, 10)
        XCTAssertEqual(WatchMoodService.Mood.lowBattery.energy, 15)
        XCTAssertEqual(WatchMoodService.Mood.needsWind.energy, 25)
    }

    func test_energy_ordering_reflects_activity() {
        // 활동성 높은 순으로 energy 가 단조 감소.
        XCTAssertGreaterThan(WatchMoodService.Mood.energetic.energy, WatchMoodService.Mood.happy.energy)
        XCTAssertGreaterThan(WatchMoodService.Mood.happy.energy, WatchMoodService.Mood.sleepy.energy)
        XCTAssertGreaterThan(WatchMoodService.Mood.sleepy.energy, WatchMoodService.Mood.dormant.energy)
    }

    func test_raw_values_are_stable() {
        XCTAssertEqual(WatchMoodService.Mood.energetic.rawValue, "energetic")
        XCTAssertEqual(WatchMoodService.Mood.lowBattery.rawValue, "lowBattery")
        XCTAssertEqual(WatchMoodService.Mood.needsWind.rawValue, "needsWind")
        XCTAssertEqual(WatchMoodService.Mood.allCases.count, 6)
    }
}
