import Foundation
@testable import WatchAccuracyPro

/// 미리 생성된 [Float] 신호를 100ms 청크로 동기 콜백해 주는 가짜 AudioSource.
/// `start(onBuffer:)` 호출 즉시 모든 청크를 흘려 보내고 반환한다 — 비동기 대기 없는 테스트용.
final class SyntheticAudioSource: AudioSource {
    let sampleRate: Double
    private let signal: [Float]
    private var onBuffer: (([Float]) -> Void)?

    init(signal: [Float], sampleRate: Double = 48_000) {
        self.signal = signal
        self.sampleRate = sampleRate
    }

    func start(onBuffer: @escaping ([Float]) -> Void) throws {
        self.onBuffer = onBuffer
        let chunkSize = Int(sampleRate * 0.1) // 100ms
        var idx = 0
        while idx < signal.count {
            let end = min(idx + chunkSize, signal.count)
            let chunk = Array(signal[idx..<end])
            onBuffer(chunk)
            idx = end
        }
    }

    func stop() {
        onBuffer = nil
    }
}
