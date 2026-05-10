import Foundation

/// 측정된 BPH와 명목 BPH의 차이로부터 일일 오차(초/일)를 계산한다.
enum RateCalculator {
    /// - Parameters:
    ///   - measuredBph: BPHEstimator가 산출한 raw BPH
    ///   - nominalBph: 무브먼트 DB의 명목 BPH (예: 28800)
    /// - Returns: 양수면 시계가 빠름, 음수면 느림. 단위 초/일.
    static func secondsPerDay(measuredBph: Double, nominalBph: Int) -> Double {
        guard nominalBph > 0 else { return 0 }
        let ratio = (measuredBph - Double(nominalBph)) / Double(nominalBph)
        return ratio * 86_400
    }

    /// beat events를 직접 입력받아 측정 BPH를 산출한 뒤 일일 오차로 변환.
    /// - Parameters:
    ///   - beats: 검출된 beat 이벤트 (시간 오름차순)
    ///   - nominalBph: 명목 BPH
    /// - Returns: 일일 오차. beats가 부족하면 nil.
    static func secondsPerDay(beats: [BeatEvent], nominalBph: Int) -> Double? {
        guard beats.count >= 2 else { return nil }
        let first = beats.first!.timestampSeconds
        let last = beats.last!.timestampSeconds
        let duration = last - first
        guard duration > 0 else { return nil }
        // beat 1개 = 3600/BPH 초 → 측정 BPH = 3600 × beats / duration
        // (count - 1)개 inter-onset interval로 정확히 측정
        let measuredBph = 3_600.0 * Double(beats.count - 1) / duration
        return secondsPerDay(measuredBph: measuredBph, nominalBph: nominalBph)
    }
}
