import XCTest
@testable import WatchAccuracyPro

/// ConfidenceScorer — ConfidenceScorerTests 가 안 다루는 분기.
///   · duration 10~30s / 30~60s 부분 점수 구간 · SNR 중간 구간 linear · duration<10 무점수
///   · ConfidenceReason localizationKey / icon / CaseIterable 접근자
final class ConfidenceScorerExtraTests: XCTestCase {

    // MARK: - duration 구간별 부분 점수

    func test_duration_10_to_30_band_partial() {
        // duration 20s: 5 + 5*(20-10)/20 = 7.5점. SNR/BPH/beat 0 → 총 ≈ 8(반올림).
        let score = ConfidenceScorer.score(.init(
            snrDB: 0, durationSeconds: 20,
            bphAutocorrelationConfidence: 0, beatCount: 0, beatErrorMs: nil
        ))
        XCTAssertEqual(score, 8, "duration 20s → 7.5점 반올림 8")
    }

    func test_duration_exactly_10_gets_base_five() {
        // duration 10s: 5 + 5*(10-10)/20 = 5점.
        let score = ConfidenceScorer.score(.init(
            snrDB: 0, durationSeconds: 10,
            bphAutocorrelationConfidence: 0, beatCount: 0, beatErrorMs: nil
        ))
        XCTAssertEqual(score, 5)
    }

    func test_duration_below_10_no_points() {
        // duration 9s: 어떤 duration 가산 분기도 안 탐 → 0점.
        let score = ConfidenceScorer.score(.init(
            snrDB: 0, durationSeconds: 9,
            bphAutocorrelationConfidence: 0, beatCount: 0, beatErrorMs: nil
        ))
        XCTAssertEqual(score, 0)
    }

    func test_duration_30_to_60_band_partial() {
        // duration 45s: 10 + 7*(45-30)/30 = 13.5점.
        let score = ConfidenceScorer.score(.init(
            snrDB: 0, durationSeconds: 45,
            bphAutocorrelationConfidence: 0, beatCount: 0, beatErrorMs: nil
        ))
        XCTAssertEqual(score, 14, "duration 45s → 13.5점 반올림 14")
    }

    // MARK: - SNR 중간 구간 linear (snrLow 10 < snr < snrHigh 22)

    func test_snr_midrange_linear_component() {
        // SNR 16dB: 20 * (16-10)/(22-10) = 20 * 0.5 = 10점. 그 외 0.
        let score = ConfidenceScorer.score(.init(
            snrDB: 16, durationSeconds: 0,
            bphAutocorrelationConfidence: 0, beatCount: 0, beatErrorMs: nil
        ))
        XCTAssertEqual(score, 10, "SNR 16dB → 중간 구간 linear 10점")
    }

    func test_snr_at_or_below_low_threshold_no_points() {
        // SNR 10dB(=snrLow) 는 ' > snrLow' 가 아니므로 0점.
        let score = ConfidenceScorer.score(.init(
            snrDB: 10, durationSeconds: 0,
            bphAutocorrelationConfidence: 0, beatCount: 0, beatErrorMs: nil
        ))
        XCTAssertEqual(score, 0)
    }

    // MARK: - bphAutocorrelationConfidence clamp 음수

    func test_negative_bph_confidence_clamped_to_zero() {
        let score = ConfidenceScorer.score(.init(
            snrDB: 0, durationSeconds: 0,
            bphAutocorrelationConfidence: -0.5, beatCount: 0, beatErrorMs: nil
        ))
        XCTAssertEqual(score, 0, "음수 bph confidence 는 0 으로 clamp")
    }

    // MARK: - ConfidenceReason 접근자

    func test_reason_localizationKeys() {
        XCTAssertEqual(ConfidenceReason.lowSNR.localizationKey, "confidence.reason.lowSNR")
        XCTAssertEqual(ConfidenceReason.shortDuration.localizationKey, "confidence.reason.shortDuration")
        XCTAssertEqual(ConfidenceReason.bphUncertain.localizationKey, "confidence.reason.bphUncertain")
    }

    func test_reason_icons() {
        XCTAssertEqual(ConfidenceReason.lowSNR.icon, "speaker.wave.2")
        XCTAssertEqual(ConfidenceReason.shortDuration.icon, "clock")
        XCTAssertEqual(ConfidenceReason.bphUncertain.icon, "waveform.badge.magnifyingglass")
    }

    func test_reason_allCases_and_rawValues() {
        XCTAssertEqual(ConfidenceReason.allCases.count, 3)
        XCTAssertEqual(ConfidenceReason.lowSNR.rawValue, "lowSNR")
        XCTAssertEqual(ConfidenceReason(rawValue: "shortDuration"), .shortDuration)
        XCTAssertNil(ConfidenceReason(rawValue: "bogus"))
    }
}
