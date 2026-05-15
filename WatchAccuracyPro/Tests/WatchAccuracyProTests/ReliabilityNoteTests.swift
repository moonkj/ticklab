import XCTest
@testable import WatchAccuracyPro

final class ReliabilityNoteTests: XCTestCase {
    func test_each_note_has_distinct_title_and_body_keys() {
        let cases: [ReliabilityNote] = [.coaxial, .generic, .amplitudeUnstable]
        let titles = Set(cases.map(\.titleKey))
        let bodies = Set(cases.map(\.bodyKey))
        XCTAssertEqual(titles.count, cases.count, "title 키는 모두 distinct")
        XCTAssertEqual(bodies.count, cases.count, "body 키는 모두 distinct")
    }

    func test_raw_value_matches_body_key() {
        XCTAssertEqual(ReliabilityNote.coaxial.bodyKey, ReliabilityNote.coaxial.rawValue)
        XCTAssertEqual(ReliabilityNote.generic.bodyKey, ReliabilityNote.generic.rawValue)
        XCTAssertEqual(ReliabilityNote.amplitudeUnstable.bodyKey, ReliabilityNote.amplitudeUnstable.rawValue)
    }

    func test_legacy_string_accessor_still_works() {
        // 후방 호환 — `reliabilityNoteKey` 가 enum 의 rawValue 반환.
        let result = MeasurementResult(
            bph: 28800, rateSecondsPerDay: 0, beatErrorMs: 0,
            amplitudeDegrees: nil, confidenceScore: 0, durationSeconds: 0,
            snrDB: 0, beatCount: 0, reliabilityNote: .coaxial
        )
        XCTAssertEqual(result.reliabilityNoteKey, "movement.reliability.coaxial.notice")

        let none = MeasurementResult(
            bph: 28800, rateSecondsPerDay: 0, beatErrorMs: 0,
            amplitudeDegrees: nil, confidenceScore: 0, durationSeconds: 0,
            snrDB: 0, beatCount: 0, reliabilityNote: nil
        )
        XCTAssertNil(none.reliabilityNoteKey)
    }
}
