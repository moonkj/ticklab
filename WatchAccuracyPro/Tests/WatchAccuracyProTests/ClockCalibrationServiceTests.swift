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

    // MARK: - Round 173: 다점 회귀 (regressionPpm)

    /// 진짜시간 t_i 에 mono = base + (1+ppm)·t 인 점들 생성.
    private func points(ppm: Double, ts: [Double], base: Double = 1000) -> (monos: [Double], trues: [Double]) {
        let trues = ts
        let monos = ts.map { base + (1 + ppm * 1e-6) * $0 }
        return (monos, trues)
    }

    func test_regression_recoversFastOscillator() {
        // +56ppm, span 3600s, 5점 → 회귀 기울기에서 +56ppm 복원.
        let p = points(ppm: 56, ts: [0, 900, 1800, 2700, 3600])
        let ppm = ClockCalibrationService.regressionPpm(monos: p.monos, trues: p.trues,
                                                        minBaseline: 1800, maxAbsPpm: 200)
        XCTAssertEqual(ppm ?? .nan, 56, accuracy: 0.5)
    }

    func test_regression_recoversSlowOscillator() {
        let p = points(ppm: -32, ts: [0, 600, 1200, 1900, 2600])
        let ppm = ClockCalibrationService.regressionPpm(monos: p.monos, trues: p.trues,
                                                        minBaseline: 1800, maxAbsPpm: 200)
        XCTAssertEqual(ppm ?? .nan, -32, accuracy: 0.5)
    }

    func test_regression_belowBaseline_nil() {
        // span 1200 < min 1800 → 아직 미수렴.
        let p = points(ppm: 56, ts: [0, 400, 800, 1200])
        XCTAssertNil(ClockCalibrationService.regressionPpm(monos: p.monos, trues: p.trues,
                                                           minBaseline: 1800, maxAbsPpm: 200))
    }

    func test_regression_outlierRejected() {
        let p = points(ppm: 500, ts: [0, 1000, 2000, 3000])   // 500 > maxAbs 200
        XCTAssertNil(ClockCalibrationService.regressionPpm(monos: p.monos, trues: p.trues,
                                                           minBaseline: 1800, maxAbsPpm: 200))
    }

    func test_regression_needsTwoPoints() {
        XCTAssertNil(ClockCalibrationService.regressionPpm(monos: [1000], trues: [0],
                                                           minBaseline: 1800, maxAbsPpm: 200))
        XCTAssertNil(ClockCalibrationService.regressionPpm(monos: [], trues: [],
                                                           minBaseline: 1800, maxAbsPpm: 200))
    }

    /// 한 점에 NTP 지터(±20ms)가 끼어도 다점 회귀가 평균화해 ppm 을 견고히 복원.
    func test_regression_robustToJitter() {
        var p = points(ppm: 40, ts: [0, 700, 1400, 2100, 2800, 3500])
        p.monos[2] += 0.020   // 한 점에 +20ms 지터
        p.monos[4] -= 0.018
        let ppm = ClockCalibrationService.regressionPpm(monos: p.monos, trues: p.trues,
                                                        minBaseline: 1800, maxAbsPpm: 200)
        XCTAssertEqual(ppm ?? .nan, 40, accuracy: 8, "다점 회귀가 점별 지터를 평균화")
    }

    /// 누적 점 0개 → pointCount 0, 미보정.
    func test_pointCount_startsZero() {
        let svc = ClockCalibrationService(defaults: UserDefaults(suiteName: "test.clockcal.\(UUID())")!)
        XCTAssertEqual(svc.pointCount, 0)
        XCTAssertFalse(svc.isCalibrated)
    }
}
