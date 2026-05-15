import Foundation

/// tic→toc 간격(T1)과 toc→tic 간격(T2)의 비대칭으로부터 beat error를 계산한다.
/// beat error = |mean(T1) - mean(T2)| × 1000 (단위 ms).
/// 이상적으로는 두 간격이 같아 0ms, 0.5ms 이상이면 일반 조정 권장.
enum BeatErrorCalculator {
    /// - Parameter beats: 시간 오름차순 beat events. tic/toc 가 번갈아 등장한다고 가정.
    /// Round 30: missing tic 으로 한쪽 IOI 가 부풀려지는 case 대비 median 기반 + valid filter.
    /// 사용자 보고: 70 onsets/12s 의 mean-based beat error 가 30ms 넘게 부풀려져 BPH lock 자체 실패.
    static func beatErrorMs(beats: [BeatEvent]) -> Double? {
        guard beats.count >= 4 else { return nil }
        var t1: [Double] = []  // tic→toc
        var t2: [Double] = []  // toc→tic
        for i in 0..<beats.count - 1 {
            let interval = beats[i + 1].timestampSeconds - beats[i].timestampSeconds
            if beats[i].type == .tic {
                t1.append(interval)
            } else {
                t2.append(interval)
            }
        }
        // Valid filter — missing beat 로 인한 250ms+ IOI 등 outlier 제거.
        let validT1 = t1.filter { $0 >= 0.060 && $0 <= 0.500 }.sorted()
        let validT2 = t2.filter { $0 >= 0.060 && $0 <= 0.500 }.sorted()
        guard !validT1.isEmpty, !validT2.isEmpty else { return nil }
        let median1 = validT1[validT1.count / 2]
        let median2 = validT2[validT2.count / 2]
        return abs(median1 - median2) * 1_000
    }
}
