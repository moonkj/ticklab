import Foundation

/// 단위 테스트용 합성 시계 신호 생성기.
/// 실 fixture(.wav) 가 추가되기 전까지 DSP 알고리즘 회귀 테스트에 사용된다.
enum SyntheticSignal {
    /// 시계 tic-toc 임펄스 트레인 합성. tic 과 toc 의 진폭/감쇠를 다르게 줘서
    /// 실 시계의 비대칭 패턴을 흉내낸다 (full-cycle 자기상관 peak 가 우세하도록).
    ///
    /// - Parameters:
    ///   - bph: 시간당 비트 (예: 28800)
    ///   - duration: 신호 길이 (초)
    ///   - sampleRate: 48000 권장
    ///   - ticToTocDelayMs: tic 과 toc 간 비대칭 (양수: toc이 늦음, beat error 시뮬레이션)
    ///   - noiseAmplitude: 추가 가우시안 노이즈 진폭 (0~1)
    static func ticTocImpulseTrain(
        bph: Int,
        duration: Double,
        sampleRate: Double = 48_000,
        ticToTocDelayMs: Double = 0,
        noiseAmplitude: Float = 0.0,
        seed: UInt64 = 42
    ) -> [Float] {
        let totalSamples = Int(duration * sampleRate)
        var signal = [Float](repeating: 0, count: totalSamples)

        // 평균 inter-onset (초). BPH = 시간당 beats. 1 beat = 3600/BPH 초.
        let interOnset = 3_600.0 / Double(bph)
        let halfCycle = interOnset
        let ticAmp: Float = 1.0
        let tocAmp: Float = 0.7
        // 임펄스: 짧은 5kHz tone burst, 5ms 폭 + 지수 감쇠
        let burstFrames = Int(0.005 * sampleRate)
        let burstFreq: Double = 5_000

        var t = 0.0
        var beatIndex = 0
        while t < duration {
            let isTic = beatIndex.isMultiple(of: 2)
            let tEffective = isTic ? t : t + (ticToTocDelayMs / 1_000.0)
            let onsetIdx = Int(tEffective * sampleRate)
            if onsetIdx + burstFrames < totalSamples {
                let amp = isTic ? ticAmp : tocAmp
                for k in 0..<burstFrames {
                    let phase = 2.0 * .pi * burstFreq * Double(k) / sampleRate
                    let envelope = expf(-Float(k) / Float(burstFrames) * 5)
                    signal[onsetIdx + k] += amp * envelope * Float(sin(phase))
                }
            }
            t += halfCycle
            beatIndex += 1
        }

        if noiseAmplitude > 0 {
            var rng = SeededXorShift64(seed: seed)
            for i in 0..<totalSamples {
                let n = Float.random(in: -1...1, using: &rng) * noiseAmplitude
                signal[i] += n
            }
        }

        return signal
    }

    /// **realistic** 합성 신호 (라운드 3, Doyoon/Min): 단일 5kHz burst 가 아닌
    /// multi-frequency damped (2/4/6 kHz 가산) — 실 watch tic 의 다중 공명 모방.
    /// 가산 가우시안 노이즈 (-30dBFS 수준) 도 기본 포함.
    static func realisticTicTocTrain(
        bph: Int,
        duration: Double,
        sampleRate: Double = 48_000,
        ticToTocDelayMs: Double = 0,
        noiseAmplitudeDB: Double = -30,
        seed: UInt64 = 42
    ) -> [Float] {
        let totalSamples = Int(duration * sampleRate)
        var signal = [Float](repeating: 0, count: totalSamples)
        let interOnset = 3_600.0 / Double(bph)
        let burstFrames = Int(0.006 * sampleRate)  // 6ms (실 시계 burst 더 길음)
        // Multi-resonance: 2.4 / 4.2 / 6.0 kHz, 각 진폭 다름
        let resonances: [(freq: Double, amp: Float)] = [
            (2_400, 0.4), (4_200, 0.6), (6_000, 0.3)
        ]
        let ticAmp: Float = 1.0
        let tocAmp: Float = 0.8

        var t = 0.0
        var beatIndex = 0
        while t < duration {
            let isTic = beatIndex.isMultiple(of: 2)
            let tEffective = isTic ? t : t + (ticToTocDelayMs / 1_000.0)
            let onsetIdx = Int(tEffective * sampleRate)
            if onsetIdx + burstFrames < totalSamples {
                let amp = isTic ? ticAmp : tocAmp
                for k in 0..<burstFrames {
                    let envelope = expf(-Float(k) / Float(burstFrames) * 4)
                    var sample: Float = 0
                    for r in resonances {
                        let phase = 2.0 * .pi * r.freq * Double(k) / sampleRate
                        sample += r.amp * Float(sin(phase))
                    }
                    signal[onsetIdx + k] += amp * envelope * sample
                }
            }
            t += interOnset
            beatIndex += 1
        }

        // 노이즈
        let noiseLinear = Float(pow(10.0, noiseAmplitudeDB / 20))
        var rng = SeededXorShift64(seed: seed)
        for i in 0..<totalSamples {
            signal[i] += Float.random(in: -1...1, using: &rng) * noiseLinear
        }
        return signal
    }
}

/// 결정론적 시드를 받는 RNG (테스트 재현성용).
private struct SeededXorShift64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed != 0 ? seed : 0xdeadbeef }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
