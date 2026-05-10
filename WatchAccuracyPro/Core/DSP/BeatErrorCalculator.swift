import Foundation

/// tic→toc 간격(T1)과 toc→tic 간격(T2)의 비대칭으로부터 beat error를 계산한다.
/// beat error = |mean(T1) - mean(T2)| × 1000 (단위 ms).
/// 이상적으로는 두 간격이 같아 0ms, 0.5ms 이상이면 일반 조정 권장.
enum BeatErrorCalculator {
    /// - Parameter beats: 시간 오름차순 beat events. tic/toc 가 번갈아 등장한다고 가정.
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
        guard !t1.isEmpty, !t2.isEmpty else { return nil }
        let m1 = t1.reduce(0, +) / Double(t1.count)
        let m2 = t2.reduce(0, +) / Double(t2.count)
        return abs(m1 - m2) * 1_000
    }
}
