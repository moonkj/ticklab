import Foundation

/// 진폭(amplitude, 도) 추정.
///
/// 표준 horology 공식: amplitude_deg = (lift_angle_deg × T_beat) / (π × t_imp)
/// 여기서 t_imp 는 펄스(impulse) 지속시간으로, envelope 의 FWHM 으로 근사한다.
///
/// 한계:
/// - swiss lever 무브먼트에 대해서만 유의미. 코악시얼/스프링드라이브는 nil 반환.
/// - 폰 마이크 신호로는 t_imp 추정 정확도가 낮아 실측치와 ±20° 정도의 편차가 흔하다.
///   Week 7 베타 단계에서 Weishi 1900 ground truth로 캘리브레이션 예정.
enum AmplitudeEstimator {
    /// - Parameters:
    ///   - envelope: BandPass→Envelope 처리된 신호
    ///   - beats: 검출된 beat 이벤트
    ///   - sampleRate: 48000 권장
    ///   - liftAngleDegrees: 무브먼트 DB lookup 값. 모르면 nil 반환.
    ///   - escapement: coAxial / springDrive 면 nil 반환.
    /// - Returns: 진폭(도). 추정 불가 시 nil.
    static func estimate(
        envelope: [Float],
        beats: [BeatEvent],
        sampleRate: Double = 48_000,
        liftAngleDegrees: Double?,
        escapement: Escapement
    ) -> Double? {
        guard let liftAngle = liftAngleDegrees else { return nil }
        guard escapement == .swissLever else { return nil }
        guard beats.count >= 4 else { return nil }

        // T_beat 추정 — beats 사이 평균 간격
        var totalInterval: Double = 0
        for i in 0..<beats.count - 1 {
            totalInterval += beats[i + 1].timestampSeconds - beats[i].timestampSeconds
        }
        let tBeat = totalInterval / Double(beats.count - 1)
        guard tBeat > 0 else { return nil }

        // 각 beat의 envelope FWHM을 측정해 평균
        var fwhmEstimates: [Double] = []
        for beat in beats {
            let centerIdx = Int(beat.timestampSeconds * sampleRate)
            guard let fwhm = envelopeFWHM(envelope: envelope, centerIndex: centerIdx, sampleRate: sampleRate) else {
                continue
            }
            fwhmEstimates.append(fwhm)
        }
        guard !fwhmEstimates.isEmpty else { return nil }
        // 시작/끝 제외 robust 평균 (median)
        let sorted = fwhmEstimates.sorted()
        let tImp = sorted[sorted.count / 2]
        guard tImp > 0 else { return nil }

        let amplitude = (liftAngle * tBeat) / (.pi * tImp)
        // 합리적 범위 클램프 (스파이크 방지)
        return min(max(amplitude, 100), 360)
    }

    /// `centerIndex` 주변에서 local peak 의 envelope FWHM 을 초 단위로 반환.
    private static func envelopeFWHM(envelope: [Float], centerIndex: Int, sampleRate: Double) -> Double? {
        // 탐색 윈도우: ±20ms
        let windowSamples = Int(0.02 * sampleRate)
        let start = max(0, centerIndex - windowSamples)
        let end = min(envelope.count - 1, centerIndex + windowSamples)
        guard end > start else { return nil }
        var peakIdx = start
        var peak: Float = -.infinity
        for i in start...end where envelope[i] > peak {
            peak = envelope[i]
            peakIdx = i
        }
        guard peak > 0 else { return nil }
        let half = peak / 2
        var leftIdx = peakIdx
        var rightIdx = peakIdx
        while leftIdx > start && envelope[leftIdx] > half {
            leftIdx -= 1
        }
        while rightIdx < end && envelope[rightIdx] > half {
            rightIdx += 1
        }
        let fwhmSamples = Double(rightIdx - leftIdx)
        guard fwhmSamples > 0 else { return nil }
        return fwhmSamples / sampleRate
    }
}
