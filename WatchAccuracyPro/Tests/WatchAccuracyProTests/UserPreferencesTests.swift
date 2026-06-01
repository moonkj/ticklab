import XCTest
@testable import WatchAccuracyPro

/// 커버리지 보강 — UserPreferences 의 didSet setters(UserDefaults 영속) + UserMode enum alias init.
/// 기존 전용 테스트 없음. UserDefaults.standard 백킹이므로 touch 한 키는 tearDown 에서 복원한다.
///
/// UserPreferences 는 @Observable 이지만 @MainActor 아님 — 클래스 어노테이션 불필요.
/// init 이 항상 userMode 를 .pro 로 강제하고 NotificationCenter observer 를 등록하므로
/// 인스턴스 기반 테스트는 그 사실을 전제로 한다.
final class UserPreferencesTests: XCTestCase {

    private let defaults = UserDefaults.standard

    /// 테스트가 만지는 키 전부 — tearDown 에서 원래 값 복원.
    private let touchedKeys = [
        "ticklab.onboardingComplete",
        "ticklab.silentModeDefault",
        "ticklab.appLockEnabled",
        "ticklab.aiVerdictEnabled",
        "ticklab.journalReminderHour",
        "ticklab.journalReminderMinute",
        "ticklab.overhaulReminderYears",
        "ticklab.rotationNudgeDays",
        "ticklab.lastSeenWhatsNewVersion",
        "ticklab.useSimplifiedDSP",
        "ticklab.hapticsEnabled"
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

    // MARK: - UserMode enum alias init (legacy raw value 흡수)

    func test_userMode_init_accepts_legacy_aliases() {
        XCTAssertEqual(UserMode(rawValue: "novice"), .novice)
        XCTAssertEqual(UserMode(rawValue: "beginner"), .novice, "레거시 beginner → novice")
        XCTAssertEqual(UserMode(rawValue: "pro"), .pro)
        XCTAssertEqual(UserMode(rawValue: "expert"), .pro, "레거시 expert → pro")
        XCTAssertNil(UserMode(rawValue: "garbage"), "알 수 없는 값은 nil")
    }

    func test_userMode_allCases_is_exactly_two() {
        XCTAssertEqual(UserMode.allCases, [.novice, .pro])
    }

    func test_userMode_raw_values_stable() {
        XCTAssertEqual(UserMode.novice.rawValue, "novice")
        XCTAssertEqual(UserMode.pro.rawValue, "pro")
    }

    // MARK: - init 강제 마이그레이션 (userMode → .pro)

    func test_init_forces_pro_mode_and_persists() {
        let prefs = UserPreferences()
        XCTAssertEqual(prefs.userMode, .pro, "init 은 항상 .pro 로 마이그레이션")
        XCTAssertEqual(defaults.string(forKey: "ticklab.userMode"), "pro")
    }

    // MARK: - Bool setter didSet 영속

    func test_bool_setters_persist_to_userDefaults() {
        let prefs = UserPreferences()
        prefs.hasCompletedOnboarding = true
        XCTAssertTrue(defaults.bool(forKey: "ticklab.onboardingComplete"))
        prefs.hasCompletedOnboarding = false
        XCTAssertFalse(defaults.bool(forKey: "ticklab.onboardingComplete"))

        prefs.appLockEnabled = true
        XCTAssertTrue(defaults.bool(forKey: "ticklab.appLockEnabled"))

        prefs.silentModeDefault = false
        XCTAssertFalse(defaults.bool(forKey: "ticklab.silentModeDefault"))

        prefs.aiVerdictEnabled = false
        XCTAssertFalse(defaults.bool(forKey: "ticklab.aiVerdictEnabled"))

        prefs.useSimplifiedDSP = false
        XCTAssertFalse(defaults.bool(forKey: "ticklab.useSimplifiedDSP"))

        prefs.hapticsEnabled = false
        XCTAssertFalse(defaults.bool(forKey: "ticklab.hapticsEnabled"))
    }

    // MARK: - Int setter didSet 영속

    func test_int_setters_persist_to_userDefaults() {
        let prefs = UserPreferences()
        prefs.journalReminderHour = 7
        prefs.journalReminderMinute = 45
        XCTAssertEqual(defaults.integer(forKey: "ticklab.journalReminderHour"), 7)
        XCTAssertEqual(defaults.integer(forKey: "ticklab.journalReminderMinute"), 45)

        prefs.overhaulReminderYears = 5
        XCTAssertEqual(defaults.integer(forKey: "ticklab.overhaulReminderYears"), 5)

        prefs.rotationNudgeDays = 14
        XCTAssertEqual(defaults.integer(forKey: "ticklab.rotationNudgeDays"), 14)
    }

    // MARK: - String setter didSet 영속

    func test_string_setter_persists_to_userDefaults() {
        let prefs = UserPreferences()
        prefs.lastSeenWhatsNewVersion = "2026.06"
        XCTAssertEqual(defaults.string(forKey: "ticklab.lastSeenWhatsNewVersion"), "2026.06")
    }

    // MARK: - 인스턴스 값이 setter 후 일관되게 읽힘 (computed get == 저장된 stored)

    func test_setter_then_getter_round_trip() {
        let prefs = UserPreferences()
        prefs.overhaulReminderYears = 6
        XCTAssertEqual(prefs.overhaulReminderYears, 6)
        prefs.journalReminderHour = 9
        XCTAssertEqual(prefs.journalReminderHour, 9)
        prefs.lastSeenWhatsNewVersion = "vX"
        XCTAssertEqual(prefs.lastSeenWhatsNewVersion, "vX")
    }
}
