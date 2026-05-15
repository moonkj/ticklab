import Accelerate
import Foundation

/// Matched filter cross-correlation for mechanical watch tic detection.
///
/// Industry-standard 접근 (vacaboja/tg, Watch-O-Scope 의 핵심 알고리즘).
/// 합성 watch tic template (Gabor pulse: 5500Hz 중심, 5ms duration, gaussian envelope)
/// 과 cross-correlation. tic-like transient 만 강한 응답, broadband noise 는 약한 응답.
///
/// 동작:
/// - input: bandpass 통과한 audio-rate signal (48kHz)
/// - output: 같은 length 의 |cc(n)| — 각 위치에서 template 와의 매칭 강도
/// - 그 output 이 envelope/flux extractor 의 입력으로 들어가면, 결과 onset signal 이
///   훨씬 robust (noise dominant 환경에서도 tic shape 만 강조).
///
/// 일반 RMS-based envelope 대비 장점: amplitude 변동에 강함, broadband noise 거의 reject.
/// Round 151 (Müller + Kim 토론): 캘리버 family 별 matched filter profile.
/// Round 37 IWC mismatch 회피 — escapement + bph 기반 dispatch.
enum MatchedFilterProfile: Equatable {
    case bypass                               // coAxial / springDrive / quartz / detent
    case vintage18k                           // 18000 BPH swissLever (ETA 2750 등)
    case swissLever21600                      // ETA 2824, SW200 vintage
    case swissLever28800Classic               // ETA 2892, Rolex 3135, IWC 35111 (Round 156: Modern 통합)
    case highBeat36000                        // Zenith El Primero, GS 9S86

    var centerFrequencyHz: Double? {
        switch self {
        case .bypass: return nil
        case .vintage18k: return 4_000
        case .swissLever21600: return 5_000
        case .swissLever28800Classic: return 5_800
        case .highBeat36000: return 7_500
        }
    }
    var durationMs: Double? {
        switch self {
        case .bypass: return nil
        case .vintage18k: return 9.0
        case .swissLever21600: return 6.0
        case .swissLever28800Classic: return 5.0
        case .highBeat36000: return 3.5
        }
    }

    /// escapement + bph → profile. 안 맞으면 .bypass (Round 37 회피).
    /// Round 156 (Hyemi #4 fix): swissLever28800Modern 는 resolve 에서 도달 불가능한 dead path 였음
    /// (25_200..<31_500 → Classic 만 반환). 향후 composite Gabor template 도입 시 별도 함수로 분리하여 추가 예정.
    static func resolve(escapement: Escapement, bph: Int) -> MatchedFilterProfile {
        switch escapement {
        case .coAxial, .springDrive, .quartz, .detentEscapement:
            return .bypass
        case .swissLever, .siliconEscapement:
            switch bph {
            case ..<19_800: return .vintage18k
            case 19_800..<25_200: return .swissLever21600
            case 25_200..<31_500: return .swissLever28800Classic
            case 31_500...: return .highBeat36000
            default: return .bypass
            }
        }
    }
}

final class MatchedFilter {
    /// Gabor pulse template — 시계 tic acoustic signature 모방.
    private let template: [Float]
    /// Chunk boundary carry — process 가 chunk 단위로 호출될 때 boundary M-1 sample 보존.
    private var carry: [Float] = []
    private let templateSize: Int
    let profile: MatchedFilterProfile

    /// Round 151: profile 기반 init. `.bypass` 면 template 0 length → process() 는 input 그대로 반환.
    init(profile: MatchedFilterProfile, sampleRate: Double = 48_000) {
        self.profile = profile
        if let f = profile.centerFrequencyHz, let d = profile.durationMs {
            self.template = Self.gaborTemplate(
                sampleRate: sampleRate, centerFreq: f, durationMs: d
            )
        } else {
            self.template = []
        }
        self.templateSize = template.count
    }

    /// 레거시 init — 호환성 유지 (직접 5500 Hz 호출 코드 잔존 시).
    init(sampleRate: Double = 48_000, centerFrequencyHz: Double = 5_500, durationMs: Double = 5.0) {
        self.profile = .swissLever28800Classic
        self.template = Self.gaborTemplate(
            sampleRate: sampleRate,
            centerFreq: centerFrequencyHz,
            durationMs: durationMs
        )
        self.templateSize = template.count
    }

    /// Gabor pulse: gaussian envelope × sinusoid. 시계 tic 의 dominant freq 5-7kHz 영역 모방.
    /// (ETA 7750 / 2824 / Sellita SW200 등 popular movement 의 acoustic signature 와 align.)
    private static func gaborTemplate(sampleRate: Double, centerFreq: Double, durationMs: Double) -> [Float] {
        let N = max(8, Int(durationMs / 1000.0 * sampleRate))
        let center = durationMs / 2000.0       // 중심 시각 (s)
        let sigma = durationMs / 4000.0         // gaussian width — duration 의 1/4
        var t = [Float](repeating: 0, count: N)
        for i in 0..<N {
            let time = Double(i) / sampleRate
            let env = exp(-((time - center) * (time - center)) / (2 * sigma * sigma))
            let sinusoid = sin(2 * .pi * centerFreq * time)
            t[i] = Float(env * sinusoid)
        }
        // Normalize — sum of squares = 1.
        var sumSq: Float = 0
        for v in t { sumSq += v * v }
        let norm = sqrt(sumSq)
        if norm > 0 {
            for i in 0..<N { t[i] /= norm }
        }
        return t
    }

    func reset() { carry.removeAll() }

    /// `samples` 위에 matched filter 적용. carry 와 합쳐 cc 결과 (same length as `samples`) 반환.
    /// 마지막 M-1 sample 은 다음 chunk 와 boundary 처리 (carry 로 보존).
    func process(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        // Round 151 (Müller Layer 3): bypass profile — input 그대로 반환 (no-op).
        if templateSize == 0 { return samples }
        let buffer = carry + samples
        let N = buffer.count
        let M = templateSize
        guard N >= M else {
            carry = buffer
            return [Float](repeating: 0, count: samples.count)
        }
        // cc 계산 — buffer 의 0..N-M+1 에서. 각 position 에서 template 와 dot product.
        let ccLength = N - M + 1
        var cc = [Float](repeating: 0, count: ccLength)
        buffer.withUnsafeBufferPointer { bp in
            template.withUnsafeBufferPointer { tp in
                for n in 0..<ccLength {
                    var v: Float = 0
                    vDSP_dotpr(bp.baseAddress!.advanced(by: n), 1, tp.baseAddress!, 1, &v, vDSP_Length(M))
                    cc[n] = abs(v)
                }
            }
        }
        // Carry: 다음 chunk 와 overlap 위해 마지막 M-1 sample 보존.
        carry = Array(buffer.suffix(M - 1))
        // Return: samples 길이 만큼만. carry 영역 (buffer 의 처음 carry-prev 길이) 만큼 잘라낸 후.
        // 단순화 — cc 의 마지막 samples.count 만큼 반환. boundary 정확도 약간 잃지만 OK.
        if cc.count >= samples.count {
            return Array(cc.suffix(samples.count))
        } else {
            return cc + [Float](repeating: 0, count: samples.count - cc.count)
        }
    }
}
