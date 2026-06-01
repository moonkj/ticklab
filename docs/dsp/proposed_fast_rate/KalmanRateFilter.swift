import Foundation

// MARK: - KalmanRateFilter
// 기계식 시계 rate(초/일)를 beat event마다 온라인으로 추정하는 1D Kalman 필터.
// 기존 RateCalculator의 batch window 평균화를 대체하는 제안.
// (제안 — docs/dsp/proposed_fast_rate, 미통합. 검토용 보관.)

struct KalmanRateFilter {

    // MARK: - Noise parameters (empirically tuned)

    /// 프로세스 잡음: 기계식 rate는 beat-to-beat로 거의 변하지 않음.
    var processNoise: Double = 0.05

    /// 측정 잡음: 단일 IOI에서 환산한 rate 추정 분산.
    /// iPhone 마이크 + 실내 환경에서 약 ±4 s/day std → variance 16.
    var measurementNoise: Double = 16.0

    /// 수렴 임계: posterior std < 0.5 s/day 면 신뢰 가능(COSC ±4의 8배 정밀).
    var convergenceVariance: Double = 0.25

    // MARK: - State

    private(set) var estimate: Double = 0.0
    private(set) var variance: Double = 10_000.0
    private(set) var updateCount: Int = 0

    var isInitialised: Bool { updateCount > 0 }

    var isConverged: Bool {
        isInitialised && variance <= convergenceVariance
    }

    var standardDeviation: Double { sqrt(max(variance, 0)) }

    // MARK: - Update

    /// 새 rate 측정값으로 필터 업데이트.
    /// - Parameter z: IOI에서 환산한 instantaneous rate (s/day).
    mutating func update(measurement z: Double) {
        guard isInitialised else {
            estimate = z
            variance = measurementNoise
            updateCount = 1
            return
        }
        let pPrior = variance + processNoise
        let K = pPrior / (pPrior + measurementNoise)
        estimate = estimate + K * (z - estimate)
        variance = (1.0 - K) * pPrior
        updateCount += 1
    }

    mutating func reset() {
        estimate = 0.0
        variance = 10_000.0
        updateCount = 0
    }
}
