import Foundation

struct ConfidenceInputs {
    let snrDB: Double
    let durationSeconds: Double
    let bphAutocorrelationConfidence: Double  // 0~1, R(τ*)/R(0)
    let beatCount: Int
    let beatErrorMs: Double?
}

/// 측정 신뢰도(0~100)를 산출.
/// Round 110 (DSP 연구팀): 가중치 재조정 — SNR 과중 완화, BPH 정확도 강화.
/// 가중치 합산 (합계 100):
///   - SNR(dB): 12dB 기준, 22dB 상한으로 낮춤 (이전 25dB는 실내에서도 드물었음) → 20점
///   - 측정 시간: 30s 이상 부분 점수, 120s+ = 25점 (유지)
///   - BPH autocorrelation 신뢰도: lock 품질 → 30점 (이전 25점에서 상향)
///   - tic/toc 분리도 (beat error 0~2ms) → 25점 (이전 20점에서 상향)
/// 합계: 20+25+30+25 = 100
enum ConfidenceScorer {
    static func score(_ inputs: ConfidenceInputs) -> Int {
        var s = 0.0

        // SNR — Round 110: 상한 25→22dB, 가중치 30→20점.
        // Round 129 (실기기 피드백): 케이스백 닫힌 드레스워치(IWC/Longines 등)는 SNR이 낮음.
        // 12→10dB 완화. 10dB 이하는 노이즈 환경으로 간주.
        let snrLow = 10.0
        let snrHigh = 22.0
        if inputs.snrDB >= snrHigh {
            s += 20
        } else if inputs.snrDB > snrLow {
            let normalized = (inputs.snrDB - snrLow) / (snrHigh - snrLow)
            s += 20 * normalized
        }

        // Duration — 30초 = 10점, 60초 = 17점, 120초+ = 25점 (사이 linear).
        let dur = inputs.durationSeconds
        if dur >= 120 {
            s += 25
        } else if dur >= 60 {
            s += 17 + 8 * (dur - 60) / 60
        } else if dur >= 30 {
            s += 10 + 7 * (dur - 30) / 30
        } else if dur >= 10 {
            s += 5 + 5 * (dur - 10) / 20
        }

        // BPH autocorrelation confidence — Round 110: 25→30점 (lock 품질 핵심 지표).
        let bphConf = max(0, min(1, inputs.bphAutocorrelationConfidence))
        s += 30 * bphConf

        // tic/toc 분리도 — Round 110: 20→25점 (beat error 0ms 는 무브먼트 상태 매우 양호).
        if let beatError = inputs.beatErrorMs {
            let normalized = max(0, min(1, beatError / 2.0))  // 2ms 이상이면 0점
            s += 25 * (1 - normalized)
        }

        return min(100, Int(s.rounded()))
    }

    /// T-02: 신뢰도 저하의 주된 원인 분류 — UI 가 개선 안내(HelpCard)로 노출. 우선순위 순.
    /// `bphConfidence` 가 주어지면(DSP 경로) 직접 판정, nil(결과화면 경로)이면
    /// SNR·측정시간으로 설명되지 않는 저점수를 BPH lock 문제로 추정한다.
    static func reasons(snrDB: Double, durationSeconds: Double,
                        confidenceScore: Int, bphConfidence: Double? = nil) -> [ConfidenceReason] {
        var out: [ConfidenceReason] = []
        if snrDB < 14 { out.append(.lowSNR) }
        if durationSeconds < 30 { out.append(.shortDuration) }
        if let c = bphConfidence {
            if c < 0.6 { out.append(.bphUncertain) }
        } else if confidenceScore < 70, snrDB >= 14, durationSeconds >= 30 {
            out.append(.bphUncertain)
        }
        return out
    }
}

/// 신뢰도 저하 원인 — 낮은 신뢰도일 때 사용자에게 개선 방법을 안내(T-02).
enum ConfidenceReason: String, CaseIterable, Hashable, Sendable {
    case lowSNR
    case shortDuration
    case bphUncertain

    /// Localizable.strings 키 (Hard Rule #3: 인라인 문자열 금지).
    var localizationKey: String {
        switch self {
        case .lowSNR:        return "confidence.reason.lowSNR"
        case .shortDuration: return "confidence.reason.shortDuration"
        case .bphUncertain:  return "confidence.reason.bphUncertain"
        }
    }
    var icon: String {
        switch self {
        case .lowSNR:        return "speaker.wave.2"
        case .shortDuration: return "clock"
        case .bphUncertain:  return "waveform.badge.magnifyingglass"
        }
    }
}
