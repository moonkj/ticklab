import Foundation

// MARK: - IOIRateEstimator
// Onset 시각에서 IOI(Inter-Onset Interval)를 계산하고, MAD outlier rejection 후
// Kalman filter로 온라인 rate 추정. 기존 autocorrelation 30초 window를 대체하는 제안.
// (제안 — 미통합. 검토용 보관.)

struct IOIRateEstimator {

    // MARK: - Configuration

    private let minIOIsForSeed: Int = 3
    private let madThreshold: Double = 3.5

    /// 명목 BPH — MovementDB 또는 Goertzel 추정값으로 설정.
    var nominalBPH: Int = 28800

    // MARK: - State

    private var onsetTimes: [Double] = []
    private var ticTimes: [Double] = []
    private var tocTimes: [Double] = []

    private(set) var kalman = KalmanRateFilter()

    // MARK: - Computed

    var isConverged: Bool { kalman.isConverged }
    var rateSecPerDay: Double { kalman.estimate }
    var rateSigma: Double { kalman.standardDeviation }

    var confidenceScore: Int {
        guard kalman.isInitialised else { return 0 }
        let c = max(0.0, 1.0 - kalman.variance / 10.0)
        return Int(c * 100)
    }

    // MARK: - Update

    /// 새 onset 시각을 추가하고 Kalman 업데이트.
    /// - Parameters:
    ///   - time: onset 발생 시각(초, 측정 시작 기준)
    ///   - parity: beat parity (짝수=tic, 홀수=toc)
    mutating func addOnset(time: Double, parity: Int) {
        onsetTimes.append(time)
        if parity % 2 == 0 { ticTimes.append(time) } else { tocTimes.append(time) }

        guard onsetTimes.count >= minIOIsForSeed + 1 else { return }

        let iois: [Double] = zip(onsetTimes.dropLast(), onsetTimes.dropFirst())
            .map { $1 - $0 }

        let cleanIOIs = madFilter(iois)
        guard !cleanIOIs.isEmpty else { return }

        let medianHalfPeriod = median(cleanIOIs)
        guard medianHalfPeriod > 0 else { return }

        // rate = (명목 반주기 - 측정 반주기) / 명목 반주기 × 86400
        let nominalHalfPeriod = 3600.0 / Double(nominalBPH)
        let rateEstimate = (nominalHalfPeriod - medianHalfPeriod) / nominalHalfPeriod * 86400.0

        kalman.update(measurement: rateEstimate)
    }

    // MARK: - Beat Error

    /// Beat error (ms): tic→toc 간격과 toc→tic 간격 차이의 절반. nil if insufficient data.
    var beatErrorMs: Double? {
        guard ticTimes.count >= 2, tocTimes.count >= 2 else { return nil }
        let n = min(ticTimes.count, tocTimes.count) - 1
        guard n >= 1 else { return nil }
        var errors: [Double] = []
        for i in 0..<n {
            let t1 = tocTimes[i] - ticTimes[i]
            let t2 = ticTimes[i + 1] - tocTimes[i]
            errors.append(abs(t1 - t2) / 2.0 * 1000.0)
        }
        return errors.isEmpty ? nil : median(errors)
    }

    // MARK: - Reset

    mutating func reset() {
        onsetTimes.removeAll()
        ticTimes.removeAll()
        tocTimes.removeAll()
        kalman.reset()
    }

    // MARK: - Statistics

    private func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        let n = s.count
        guard n > 0 else { return 0 }
        return n % 2 == 0 ? (s[n/2 - 1] + s[n/2]) / 2.0 : s[n/2]
    }

    /// Modified Z-score outlier rejection (Iglewicz & Hoaglin, 1993).
    private func madFilter(_ values: [Double]) -> [Double] {
        guard values.count >= 3 else { return values }
        let med = median(values)
        let deviations = values.map { abs($0 - med) }
        let mad = median(deviations)
        guard mad > 0 else { return values }
        let bound = madThreshold * 1.4826 * mad
        return values.filter { abs($0 - med) <= bound }
    }
}
