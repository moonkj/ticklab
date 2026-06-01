import XCTest
@testable import WatchAccuracyPro

/// UserPreferences — UserPreferencesTests 가 안 다루는 나머지 setter(didSet → UserDefaults 영속).
/// UserDefaults.standard 백킹이므로 touch 한 키는 tearDown 에서 복원한다.
/// UserPreferences 는 @Observable 이지만 @MainActor 아님 — 클래스 어노테이션 불필요.
final class UserPreferencesExtraTests: XCTestCase {

    private let defaults = UserDefaults.standard

    private let touchedKeys = [
        "ticklab.iCloudSyncEnabled",
        "ticklab.autoUpdateMovementDB",
        "ticklab.useCoreMLBeatDetector",
        "ticklab.isPro",
        "ticklab.journalReminderEnabled",
        "ticklab.randomPickEnabled",
        "ticklab.randomPickHour",
        "ticklab.randomPickMinute",
        "ticklab.keepScreenOnDuringMeasurement",
        "ticklab.magneticFieldMeasurementEnabled",
        "ticklab.pinEnabled",
        "ticklab.overhaulReminderEnabled",
        "ticklab.brandLeagueOptIn",
        "ticklab.rotationNudgeEnabled",
    ]
    private var snapshot: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        snapshot = [:]
        for key in touchedKeys { snapshot[key] = defaults.object(forKey: key) }
    }

    override func tearDown() {
        for key in touchedKeys {
            if let value = snapshot[key], let value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        snapshot = [:]
        super.tearDown()
    }

    func test_remaining_bool_setters_persist() {
        let prefs = UserPreferences()

        prefs.iCloudSyncEnabled = true
        XCTAssertTrue(defaults.bool(forKey: "ticklab.iCloudSyncEnabled"))

        prefs.autoUpdateMovementDB = true
        XCTAssertTrue(defaults.bool(forKey: "ticklab.autoUpdateMovementDB"))

        prefs.useCoreMLBeatDetector = true
        XCTAssertTrue(defaults.bool(forKey: "ticklab.useCoreMLBeatDetector"))

        prefs.isPro = true
        XCTAssertTrue(defaults.bool(forKey: "ticklab.isPro"))

        prefs.journalReminderEnabled = false
        XCTAssertFalse(defaults.bool(forKey: "ticklab.journalReminderEnabled"))

        prefs.randomPickEnabled = false
        XCTAssertFalse(defaults.bool(forKey: "ticklab.randomPickEnabled"))

        prefs.keepScreenOnDuringMeasurement = false
        XCTAssertFalse(defaults.bool(forKey: "ticklab.keepScreenOnDuringMeasurement"))

        prefs.magneticFieldMeasurementEnabled = true
        XCTAssertTrue(defaults.bool(forKey: "ticklab.magneticFieldMeasurementEnabled"))

        prefs.pinEnabled = true
        XCTAssertTrue(defaults.bool(forKey: "ticklab.pinEnabled"))

        prefs.overhaulReminderEnabled = false
        XCTAssertFalse(defaults.bool(forKey: "ticklab.overhaulReminderEnabled"))

        prefs.brandLeagueOptIn = false
        XCTAssertFalse(defaults.bool(forKey: "ticklab.brandLeagueOptIn"))

        prefs.rotationNudgeEnabled = false
        XCTAssertFalse(defaults.bool(forKey: "ticklab.rotationNudgeEnabled"))
    }

    func test_remaining_int_setters_persist() {
        let prefs = UserPreferences()
        prefs.randomPickHour = 6
        prefs.randomPickMinute = 30
        XCTAssertEqual(defaults.integer(forKey: "ticklab.randomPickHour"), 6)
        XCTAssertEqual(defaults.integer(forKey: "ticklab.randomPickMinute"), 30)
    }

    func test_setter_then_getter_round_trip_instance_values() {
        let prefs = UserPreferences()
        prefs.pinEnabled = true
        XCTAssertTrue(prefs.pinEnabled)
        prefs.randomPickHour = 5
        XCTAssertEqual(prefs.randomPickHour, 5)
        prefs.brandLeagueOptIn = false
        XCTAssertFalse(prefs.brandLeagueOptIn)
    }
}
