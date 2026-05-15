import Foundation

/// Round 158: Phase-Locked Loop tracking — Müller/Wang 패널 권고 구현.
///
/// 동작:
/// 1. 첫 N개 onset 으로 초기 period 추정 (median IOI)
/// 2. 각 후속 onset: 예상 phase 와 비교 → ±tolerance 안이면 lock 유지 + period 미세조정
/// 3. 예상 시점 ±tolerance 밖 onset 은 outlier — reject
/// 4. Lock 잃으면 (consecutive miss > maxMiss) → reset
///
/// 결과: sub-pulse drift 영향 차단, period 안정 추적.
final class PLLTracker {
    /// 현재 period 추정 (seconds)
    private(set) var period: Double
    /// 마지막 lock 시각 (seconds, 신호 시작 기준)
    private(set) var lastLockTime: Double = 0
    /// 누적 lock 횟수
    private(set) var lockCount: Int = 0
    /// 연속 miss 횟수
    private var consecutiveMiss: Int = 0

    /// Tolerance — 예상 phase 대비 ±toleranceFraction × period 안이면 lock.
    let toleranceFraction: Double
    /// Period 학습률 (1차 IIR alpha). 작을수록 안정, 클수록 빠른 적응.
    let learningRate: Double
    /// 최대 연속 miss — 이 이상이면 lock 잃은 것으로 간주.
    let maxConsecutiveMiss: Int

    init(initialPeriod: Double,
         toleranceFraction: Double = 0.08,  // ±8% = 28800 의 ±10ms
         learningRate: Double = 0.05,
         maxConsecutiveMiss: Int = 5) {
        self.period = initialPeriod
        self.toleranceFraction = toleranceFraction
        self.learningRate = learningRate
        self.maxConsecutiveMiss = maxConsecutiveMiss
    }

    /// PLL 초기화 — 첫 onset 으로 phase 설정.
    func bootstrap(firstOnset: Double) {
        lastLockTime = firstOnset
        lockCount = 1
        consecutiveMiss = 0
    }

    /// 후속 onset 시도. lock 성공 시 true 반환 + period 업데이트.
    /// 예상 시점 = lastLockTime + period (× 정수배 — onset 1개 또는 여러 개 미스 후 가능)
    @discardableResult
    func tryLock(onsetTime: Double) -> Bool {
        guard lockCount > 0 else {
            bootstrap(firstOnset: onsetTime)
            return true
        }
        // 예상 phase 후보 (1, 2, 3 period 후 — missed beat 보상)
        let elapsed = onsetTime - lastLockTime
        guard elapsed > 0 else { return false }
        let nearestK = max(1, Int(round(elapsed / period)))
        let expected = lastLockTime + Double(nearestK) * period
        let phaseError = onsetTime - expected
        let tolerance = period * toleranceFraction
        guard abs(phaseError) <= tolerance else {
            consecutiveMiss += 1
            if consecutiveMiss > maxConsecutiveMiss {
                // Lock 잃음 — reset 으로 새로운 phase 시작.
                bootstrap(firstOnset: onsetTime)
            }
            return false
        }
        // Lock 성공 — period 미세조정 (IIR).
        let measuredPeriod = (onsetTime - lastLockTime) / Double(nearestK)
        period = (1 - learningRate) * period + learningRate * measuredPeriod
        lastLockTime = onsetTime
        lockCount += 1
        consecutiveMiss = 0
        return true
    }

    /// 다음 예상 onset 시간.
    func nextExpected() -> Double {
        lastLockTime + period
    }
}
