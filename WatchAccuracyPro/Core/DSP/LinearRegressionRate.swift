import Foundation

/// Linear least-squares regression on cumulative beat positions vs time.
///
/// Industry-standard approach (vacaboja/tg, Watch-O-Scope manual).
/// 누적 beat index (0, 1, 2, ..., N-1) vs timestamps 의 LSQ regression.
/// slope = seconds per beat → BPH 추정.
/// 단일 IOI median 보다 정확 (N 개 beat 의 noise 평균화 + sub-sample timestamp 활용).
///
/// 정밀도: noise level σ 일 때 slope 정밀도 ~ σ/√N. 30s 측정 240 beat + sub-sample timestamp
/// 정밀도 ±0.02ms 가정 시 rate 정밀도 약 ±1 s/d 이내.
///
/// Round 39 (사용자 보고: live rate +0.0 quantization): IOI median 기반 calc 의 한계 극복.
enum LinearRegressionRate {
    /// beats 의 cumulative position 위 LSQ regression. slope = sec per beat.
    /// - Returns: (slope, rSquared) — slope: sec/beat, rSquared: fit 품질 [0,1].
    static func slopeSecondsPerBeat(beats: [BeatEvent]) -> (slope: Double, rSquared: Double)? {
        guard beats.count >= 4 else { return nil }
        let n = Double(beats.count)
        // x_i = beat index, y_i = timestamp.
        var sumX: Double = 0, sumY: Double = 0
        for i in 0..<beats.count {
            sumX += Double(i)
            sumY += beats[i].timestampSeconds
        }
        let meanX = sumX / n
        let meanY = sumY / n
        var num: Double = 0, denX: Double = 0, denY: Double = 0
        for i in 0..<beats.count {
            let dx = Double(i) - meanX
            let dy = beats[i].timestampSeconds - meanY
            num += dx * dy
            denX += dx * dx
            denY += dy * dy
        }
        guard denX > 0, denY > 0 else { return nil }
        let slope = num / denX
        let r = num / sqrt(denX * denY)
        return (slope, r * r)
    }

    /// LSQ 기반 정밀 BPH 추정.
    static func bph(beats: [BeatEvent]) -> Double? {
        guard let (slope, _) = slopeSecondsPerBeat(beats: beats), slope > 0 else { return nil }
        return 3_600.0 / slope
    }

    /// LSQ 기반 정밀 rate (sec/day) 추정.
    /// - Parameters:
    ///   - beats: 정밀 timestamp 의 beat events (`refineTimestamps` 후).
    ///   - nominalBph: 명목 BPH.
    static func secondsPerDay(beats: [BeatEvent], nominalBph: Int) -> Double? {
        guard nominalBph > 0, let measuredBph = bph(beats: beats) else { return nil }
        return (measuredBph - Double(nominalBph)) / Double(nominalBph) * 86_400
    }
}
