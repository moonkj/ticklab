import Foundation

/// Algorithm self-test 용 가짜 AudioSource. 합성 watch tic 신호를 chunk 단위로 stream.
/// 사용자 마이크 측정 실패 시 algorithm 자체가 정상인지 검증하는 도구.
///
/// Round 37 (Hyemi): 사용자 5+ 라운드 algorithm fix 후에도 lock 실패 — acoustic coupling 한계.
/// 알고리즘이 합성 28800 BPH 신호 위에서는 잘 작동 (unit test PASS) 임을 사용자가 직접 검증.
final class SimulatedAudioSource: AudioSource {
    let sampleRate: Double
    private let bph: Int
    private let durationSeconds: Double
    private let realtime: Bool
    private var onBuffer: (([Float]) -> Void)?
    private var streamTask: Task<Void, Never>?

    /// - Parameters:
    ///   - bph: 합성할 BPH (28800 = ETA 7750/2824 등).
    ///   - durationSeconds: 총 stream 시간.
    ///   - realtime: true 면 실 측정처럼 100ms chunk 마다 100ms 대기. false 면 즉시 stream (테스트용).
    init(bph: Int = 28_800, durationSeconds: Double = 30, sampleRate: Double = 48_000, realtime: Bool = true) {
        self.bph = bph
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.realtime = realtime
    }

    func start(onBuffer: @escaping ([Float]) -> Void) throws {
        self.onBuffer = onBuffer
        let signal = Self.makeImpulseTrain(bph: bph, durationSeconds: durationSeconds, sampleRate: sampleRate)
        let chunkSize = Int(sampleRate * 0.1)  // 100ms chunks
        if realtime {
            streamTask = Task { [weak self] in
                guard let self else { return }
                var idx = 0
                while idx < signal.count && !Task.isCancelled {
                    let end = min(idx + chunkSize, signal.count)
                    let chunk = Array(signal[idx..<end])
                    await MainActor.run { self.onBuffer?(chunk) }
                    idx = end
                    try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                }
            }
        } else {
            var idx = 0
            while idx < signal.count {
                let end = min(idx + chunkSize, signal.count)
                let chunk = Array(signal[idx..<end])
                onBuffer(chunk)
                idx = end
            }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        onBuffer = nil
    }

    /// Gabor pulse train — 시계 tic 의 acoustic signature 모방 (5500Hz 중심, 5ms).
    /// realistic test 위해 noise 와 jitter 약간 추가.
    static func makeImpulseTrain(
        bph: Int,
        durationSeconds: Double,
        sampleRate: Double = 48_000,
        amplitudeJitter: Float = 0.1,
        noiseLevel: Float = 0.01
    ) -> [Float] {
        let total = Int(durationSeconds * sampleRate)
        var signal = [Float](repeating: 0, count: total)
        let periodSamples = Int(3_600.0 / Double(bph) * sampleRate)
        let burstSamples = 240  // 5ms
        let centerFreq: Double = 5_500
        let sigma: Double = 0.001  // 1ms gaussian width

        var t = 0
        var rng = SystemRandomNumberGenerator()
        while t + burstSamples < total {
            let amp: Float = 0.6 * (1.0 + Float.random(in: -amplitudeJitter...amplitudeJitter, using: &rng))
            for i in 0..<burstSamples {
                let time = Double(i) / sampleRate
                let env = exp(-((time - 0.0025) * (time - 0.0025)) / (2 * sigma * sigma))
                let s = sin(2 * .pi * centerFreq * time)
                signal[t + i] += amp * Float(env * s)
            }
            t += periodSamples
        }
        // background white noise — algorithm robustness 검증.
        for i in 0..<total {
            signal[i] += Float.random(in: -noiseLevel...noiseLevel, using: &rng)
        }
        return signal
    }
}
