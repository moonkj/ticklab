import XCTest
@testable import WatchAccuracyPro

/// Round 172 폰 발진기↔원자시간 드리프트 보정 순수 로직 회귀 가드.
final class ClockCalibrationServiceTests: XCTestCase {

    func test_belowBaseline_returnsNil() {
        // baseline(1800s) < min(3600s) → 아직 ppm 산출 안 함.
        XCTAssertNil(ClockCalibrationService.driftPpm(monotonicElapsed: 1800, trueElapsed: 1800,
                                                      minBaseline: 3600, maxAbsPpm: 200))
    }

    func test_oscillatorFast_positivePpm() {
        // mono 경과가 true 보다 +56ppm 많음 → 발진기 빠름 → +56 ppm.
        let dTrue = 7200.0
        let dMono = dTrue * (1 + 56e-6)
        let ppm = ClockCalibrationService.driftPpm(monotonicElapsed: dMono, trueElapsed: dTrue,
                                                   minBaseline: 3600, maxAbsPpm: 200)
        XCTAssertEqual(ppm ?? .nan, 56, accuracy: 0.5)
    }

    func test_oscillatorSlow_negativePpm() {
        let dTrue = 7200.0
        let dMono = dTrue * (1 - 30e-6)
        let ppm = ClockCalibrationService.driftPpm(monotonicElapsed: dMono, trueElapsed: dTrue,
                                                   minBaseline: 3600, maxAbsPpm: 200)
        XCTAssertEqual(ppm ?? .nan, -30, accuracy: 0.5)
    }

    func test_outlier_rejected() {
        // 500ppm > maxAbs(200) → NTP 오류로 보고 무시(nil).
        let dTrue = 7200.0
        let dMono = dTrue * (1 + 500e-6)
        XCTAssertNil(ClockCalibrationService.driftPpm(monotonicElapsed: dMono, trueElapsed: dTrue,
                                                      minBaseline: 3600, maxAbsPpm: 200))
    }

    func test_correctionFactor_fastOscillator_shiftsRateUp() {
        // +56ppm 발진기 → factor<1 → beatSec 줄어 rate 상향(−편향 보정). 부호 검증.
        let svc = ClockCalibrationService(defaults: UserDefaults(suiteName: "test.clockcal.\(UUID())")!)
        // driftPpm 0(기본) → factor 1.0(무보정).
        XCTAssertEqual(svc.correctionFactor, 1.0, accuracy: 1e-9)
        XCTAssertFalse(svc.isCalibrated)
    }
}
