import XCTest
@testable import WatchAccuracyPro

/// 모델 레이어 enum / value type 의 순수 computed property·rawValue·initializer 커버리지.
/// 네트워크·ModelContext 불필요한 부분만.
final class ValueModelEnumTests: XCTestCase {

    // MARK: - Position

    func test_position_rawValues_match_codes() {
        XCTAssertEqual(Position.dialUp.rawValue, "DU")
        XCTAssertEqual(Position.dialDown.rawValue, "DD")
        XCTAssertEqual(Position.crownUp.rawValue, "CU")
        XCTAssertEqual(Position.crownDown.rawValue, "CD")
        XCTAssertEqual(Position.crownLeft.rawValue, "PL")
        XCTAssertEqual(Position.crownRight.rawValue, "PR")
        XCTAssertEqual(Position.unknown.rawValue, "UNKNOWN")
    }

    func test_position_init_from_rawValue() {
        XCTAssertEqual(Position(rawValue: "DU"), .dialUp)
        XCTAssertNil(Position(rawValue: "nope"))
    }

    func test_position_localizedNames_nonEmpty_and_distinct() {
        let names = Position.allCases.map(\.localizedName)
        XCTAssertFalse(names.contains(where: \.isEmpty))
        XCTAssertEqual(Set(names).count, names.count)
    }

    // MARK: - MicrophoneType

    func test_microphoneType_localizationKeys() {
        XCTAssertEqual(MicrophoneType.builtin.localizationKey, "audio.input.builtin")
        XCTAssertEqual(MicrophoneType.wired.localizationKey, "audio.input.wired")
        XCTAssertEqual(MicrophoneType.bluetooth.localizationKey, "audio.input.bluetooth")
        XCTAssertEqual(MicrophoneType.external.localizationKey, "audio.input.external")
    }

    // MARK: - MeasurementMetadata

    func test_metadata_default_initializer() {
        let m = MeasurementMetadata()
        XCTAssertEqual(m.position, .unknown)
        XCTAssertEqual(m.ambientNoiseDB, 0)
        XCTAssertEqual(m.deviceModel, "")
        XCTAssertEqual(m.microphoneType, .builtin)
        XCTAssertNil(m.temperatureCelsius)
        XCTAssertNil(m.snrDB)
        XCTAssertNil(m.powerReserveEstimate)
        XCTAssertNil(m.ntpOffsetMs)
    }

    func test_metadata_codable_roundtrip_preserves_all_fields() throws {
        let original = MeasurementMetadata(
            position: .crownLeft,
            temperatureCelsius: 19.5,
            ambientNoiseDB: 41,
            snrDB: 12.3,
            powerReserveEstimate: 0.8,
            deviceModel: "iPhone 16 Pro",
            microphoneType: .wired,
            ntpOffsetMs: -7.5
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MeasurementMetadata.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_metadata_equatable() {
        let a = MeasurementMetadata(position: .dialUp, ambientNoiseDB: 30)
        let b = MeasurementMetadata(position: .dialUp, ambientNoiseDB: 30)
        let c = MeasurementMetadata(position: .dialDown, ambientNoiseDB: 30)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - ServiceType

    func test_serviceType_recommendedIntervalMonths() {
        XCTAssertEqual(ServiceType.fullOverhaul.recommendedIntervalMonths, 60)
        XCTAssertEqual(ServiceType.partialService.recommendedIntervalMonths, 36)
        XCTAssertEqual(ServiceType.checkup.recommendedIntervalMonths, 12)
        XCTAssertEqual(ServiceType.waterTest.recommendedIntervalMonths, 24)
        XCTAssertEqual(ServiceType.batteryReplace.recommendedIntervalMonths, 24)
        XCTAssertNil(ServiceType.crystalReplace.recommendedIntervalMonths)
        XCTAssertNil(ServiceType.crownGasket.recommendedIntervalMonths)
        XCTAssertNil(ServiceType.bracelet.recommendedIntervalMonths)
        XCTAssertNil(ServiceType.other.recommendedIntervalMonths)
    }

    func test_serviceType_init_from_rawValue() {
        XCTAssertEqual(ServiceType(rawValue: "fullOverhaul"), .fullOverhaul)
        XCTAssertNil(ServiceType(rawValue: "nonexistent"))
    }

    func test_serviceLog_type_accessor_roundtrip() {
        let log = ServiceLog(type: .waterTest)
        XCTAssertEqual(log.typeRaw, "waterTest")
        XCTAssertEqual(log.type, .waterTest)
        log.type = .bracelet
        XCTAssertEqual(log.typeRaw, "bracelet")
        XCTAssertEqual(log.type, .bracelet)
    }

    func test_serviceLog_type_getter_falls_back_to_other() {
        let log = ServiceLog()
        log.typeRaw = "garbage"
        XCTAssertEqual(log.type, .other)
    }

    // MARK: - Mood (JournalEntry)

    func test_mood_emoji_distinct_and_nonEmpty() {
        let emojis = Mood.allCases.map(\.emoji)
        XCTAssertFalse(emojis.contains(where: \.isEmpty))
        XCTAssertEqual(Set(emojis).count, emojis.count)
    }

    func test_mood_default_is_neutral_via_init() {
        let entry = JournalEntry()
        XCTAssertEqual(entry.mood, .neutral)
        XCTAssertEqual(entry.moodRaw, "neutral")
    }

    func test_mood_accessor_roundtrip_and_fallback() {
        let entry = JournalEntry()
        entry.mood = .proud
        XCTAssertEqual(entry.moodRaw, "proud")
        XCTAssertEqual(entry.mood, .proud)
        entry.moodRaw = "invalid"
        XCTAssertEqual(entry.mood, .neutral)
    }

    func test_journalEntry_people_and_events_json_roundtrip() {
        let entry = JournalEntry()
        XCTAssertEqual(entry.people, [])
        XCTAssertEqual(entry.events, [])
        entry.people = ["아내", "동호회"]
        entry.events = ["여행"]
        XCTAssertEqual(entry.people, ["아내", "동호회"])
        XCTAssertEqual(entry.events, ["여행"])
    }

    // MARK: - PhotoRole

    func test_photoRole_id_equals_rawValue() {
        for role in PhotoRole.allCases {
            XCTAssertEqual(role.id, role.rawValue)
        }
    }

    func test_photoRole_icons_nonEmpty() {
        XCTAssertEqual(PhotoRole.hero.icon, "star.fill")
        XCTAssertFalse(PhotoRole.allCases.contains(where: { $0.icon.isEmpty }))
    }

    func test_photoRole_accessor_roundtrip_and_fallback() {
        let photo = WatchPhoto(role: .caseback, photoData: Data([0x01]))
        XCTAssertEqual(photo.roleRaw, "caseback")
        XCTAssertEqual(photo.role, .caseback)
        photo.roleRaw = "???"
        XCTAssertEqual(photo.role, .other)
    }

    // MARK: - WearTag

    func test_wearTag_id_equals_rawValue() {
        for tag in WearTag.allCases {
            XCTAssertEqual(tag.id, tag.rawValue)
        }
    }

    func test_wearTag_icons_distinct() {
        let icons = WearTag.allCases.map(\.icon)
        XCTAssertEqual(Set(icons).count, icons.count)
    }

    func test_wearLog_tags_json_roundtrip_and_day_normalization() {
        let cal = Calendar.current
        let noon = cal.date(from: DateComponents(year: 2025, month: 3, day: 4, hour: 13))!
        let log = WearLog(date: noon, tags: ["비즈니스", "포멀"])
        XCTAssertEqual(log.tags, ["비즈니스", "포멀"])
        XCTAssertEqual(log.date, cal.startOfDay(for: noon), "WearLog 는 일 단위로 normalize")
        log.tags = ["여행"]
        XCTAssertEqual(log.tags, ["여행"])
    }

    // MARK: - Strap.isNearReplacement

    func test_strap_isNearReplacement_false_without_threshold() {
        let s = Strap(name: "Leather", wearCount: 1000)
        XCTAssertFalse(s.isNearReplacement)
    }

    func test_strap_isNearReplacement_true_at_80_percent() {
        // threshold 200, 80% = 160.
        let s = Strap(name: "Leather", wearCount: 160, replaceThreshold: 200)
        XCTAssertTrue(s.isNearReplacement)
    }

    func test_strap_isNearReplacement_false_below_80_percent() {
        let s = Strap(name: "Leather", wearCount: 159, replaceThreshold: 200)
        XCTAssertFalse(s.isNearReplacement)
    }

    // MARK: - WishlistItem.savingsProgress / monthsToGoal

    func test_wishlist_savingsProgress_nil_without_target() {
        let item = WishlistItem(brand: "Rolex", model: "Sub")
        XCTAssertNil(item.savingsProgress)
    }

    func test_wishlist_savingsProgress_half() throws {
        let item = WishlistItem(brand: "Rolex", model: "Sub", targetPrice: 1000)
        item.savedAmount = 500
        XCTAssertEqual(try XCTUnwrap(item.savingsProgress), 0.5, accuracy: 1e-9)
    }

    func test_wishlist_savingsProgress_clamped_to_one() {
        let item = WishlistItem(brand: "Rolex", model: "Sub", targetPrice: 1000)
        item.savedAmount = 5000
        XCTAssertEqual(item.savingsProgress, 1.0)
    }

    func test_wishlist_monthsToGoal_rounds_up() {
        let item = WishlistItem(brand: "Rolex", model: "Sub", targetPrice: 1000)
        item.savedAmount = 100
        item.monthlyGoal = 250          // 남은 900 / 250 = 3.6 → 4
        XCTAssertEqual(item.monthsToGoal, 4)
    }

    func test_wishlist_monthsToGoal_nil_when_already_saved() {
        let item = WishlistItem(brand: "Rolex", model: "Sub", targetPrice: 1000)
        item.savedAmount = 1000
        item.monthlyGoal = 100
        XCTAssertNil(item.monthsToGoal)
    }

    func test_wishlist_monthsToGoal_nil_without_monthlyGoal() {
        let item = WishlistItem(brand: "Rolex", model: "Sub", targetPrice: 1000)
        item.savedAmount = 100
        XCTAssertNil(item.monthsToGoal)
    }
}
