import Foundation

/// 측정 결과 화면에 부여될 신뢰도 안내. UI 가 title/body 모두 keyset 으로 매핑.
/// Round 7 (Doyoon/Min): String typo 방지 위해 enum 으로.
enum ReliabilityNote: String, Sendable, Hashable, Codable {
    case coaxial          = "movement.reliability.coaxial.notice"
    case generic          = "movement.reliability.generic.notice"
    case amplitudeUnstable = "movement.reliability.amplitude_unstable.notice"

    var titleKey: String {
        switch self {
        case .coaxial:           return "movement.reliability.coaxial.title"
        case .amplitudeUnstable: return "movement.reliability.amplitude_unstable.title"
        case .generic:           return "movement.reliability.generic.title"
        }
    }

    var bodyKey: String { rawValue }
}

/// Round 152 (Müller+Chen+Min 토론): 측정 신뢰도 등급 — A/B/C/F.
/// confidence 0-100 + cross-window rate delta 종합 평가. 사용자 friendly 표시.
enum ReliabilityGrade: String, Sendable, Hashable, Codable {
    case a, b, c, f

    /// Chen 권장 임계 — 실측 분포 반영. A≥75 (이전 토론 85 보다 완화).
    /// Round 154 사용자 실측: 임계 10 → 25 s/d 로 완화 (모바일 환경 자연 stddev).
    static func from(confidence: Int, crossWindowDelta: Double?) -> ReliabilityGrade {
        from(confidence: confidence, crossWindowDelta: crossWindowDelta, rateSecondsPerDay: 0)
    }

    /// Round 158 (사용자 보고: Grade B 인데 +157 s/d): rate 절대값 기반 추가 penalty.
    /// 정상 시계는 ±50 s/d 이내. |rate| 큰 측정은 consistency 무관하게 grade 낮춤.
    static func from(confidence: Int, crossWindowDelta: Double?, rateSecondsPerDay: Double) -> ReliabilityGrade {
        // Round 171 Phase B → Round 173 강화 (감사 P0: σ7.4 garbage 가 −6점뿐이라 A 통과).
        // crossWindowDelta = tgSigma×2 (simplified path). σ 가 ±s/d 재현성이므로 가파르게 강등.
        // 5 초과부터 ×3.0, cap 60: delta4(σ2) 0, delta8(σ4) 9, delta10(σ5) 15, delta14.8(σ7.4) 29.
        // confidence(창내부 자기일관성)가 높아도 강한 재현성 불일치면 강등되도록 cap 큼.
        let windowPenalty: Int = {
            guard let d = crossWindowDelta, d > 5 else { return 0 }
            return Int(min(60, (d - 5) * 3.0))
        }()
        let absRate = abs(rateSecondsPerDay)
        let ratePenalty: Int = {
            // |rate| > 50 부터 점진 penalty, |rate| > 100 면 매우 강함.
            if absRate <= 30 { return 0 }
            if absRate <= 60 { return Int(absRate - 30) }  // 0-30
            if absRate <= 120 { return 30 + Int((absRate - 60) / 2) }  // 30-60
            return 60  // |rate| > 120 → 항상 F-grade
        }()
        let adjusted = confidence - windowPenalty - ratePenalty
        switch adjusted {
        case 75...: return .a
        case 55..<75: return .b
        case 35..<55: return .c
        default: return .f
        }
    }
}

/// DSPPipeline 의 분석 산출물. UI 표시용 + SwiftData 저장용 중간 모델.
struct MeasurementResult: Equatable, Hashable, Sendable {
    let bph: Int
    /// Round 171 C1: stop() 의 robust 윈도우 집계가 오염 구간 배제 후 median 으로 교체할 수 있어 var.
    var rateSecondsPerDay: Double
    let beatErrorMs: Double
    /// 코악시얼/스프링드라이브 또는 추정 실패 시 nil.
    let amplitudeDegrees: Double?
    let confidenceScore: Int
    let durationSeconds: Int
    let snrDB: Double
    let beatCount: Int
    /// 코악시얼 등 reliability 가 medium/low 또는 amplitude 추정 실패 시 부여.
    let reliabilityNote: ReliabilityNote?
    /// 측정 시 사용자가 선택한 자세. nil/.unknown 이면 "미지정".
    var position: Position = .unknown
    /// Round 152 (Müller H1): 30s 측정을 3개 10s sub-window 로 나눠 rate max-min 차이. nil 이면 평가 안 됨.
    var crossWindowRateDelta: Double? = nil
    /// Round 152: 사용자 표시용 신뢰도 등급. nil 이면 legacy (.from 으로 fallback 가능).
    var reliabilityGrade: ReliabilityGrade? = nil
    /// Round 170 (팀 토론): OLS residual RMS (seconds). rate 정밀도 직접 metric — internal gate 용.
    /// ±1 s/d 목표 시 240 beats 면 RMS ≤ 22μs, 96 beats 면 ≤ 35μs.
    var residualRMSSeconds: Double? = nil
    /// Round 176 (감사): residualRMS 가 산출된 **실제 OLS fit beat 수** — ±s/d 불확도 공식의 N.
    /// 감사 P1: 이전엔 N 에 beatCount(전체 onset)를 써서 fit 이 부분집합일 때 ± 과신(최대 6×).
    ///   nil 이면 beatCount 로 폴백(legacy 경로 보존). 표시 전용·미persist.
    var rateFitBeatCount: Int? = nil
    /// Round 172 (tg estimator): envelope 자기상관 cycle-to-cycle 일관성(s/d). 작을수록 신뢰.
    /// tg 가 headline 일 때 ±/grade 의 재현성 신호로 사용(노이즈 큰 10s-window spread 대체).
    var tgSigma: Double? = nil
    /// (DEBUG 진단) 추정기 내부값 한 줄 — 고정 시계 run-to-run 변동 원인 추적용. 릴리스 미표시.
    var diagnostic: String? = nil

    /// 후방 호환 — UI 가 String key 를 직접 다루는 코드가 있으면 이 프로퍼티 사용.
    var reliabilityNoteKey: String? { reliabilityNote?.rawValue }

    /// ±s/d rate **fit 정밀도** 불확도 — OLS slope 이론 σ_slope = σ_resid × √12 / N^1.5.
    /// 감사 P1 수정: N = rateFitBeatCount(실제 fit) 우선, 없으면 beatCount 폴백.
    ///   residualRMS·bph 부족 시 nil. persist 게이트와 표시 ± 가 이 단일 소스를 공유한다.
    var rateFitUncertaintySD: Double? {
        Self.rateFitUncertaintySD(residualRMSSeconds: residualRMSSeconds,
                                  fitBeatCount: rateFitBeatCount,
                                  beatCount: beatCount,
                                  bph: bph)
    }

    /// 순수 함수(테스트용) — 표시/게이트 양쪽이 동일 공식을 쓰도록 단일화.
    static func rateFitUncertaintySD(residualRMSSeconds: Double?, fitBeatCount: Int?, beatCount: Int, bph: Int) -> Double? {
        guard let rms = residualRMSSeconds, bph > 0 else { return nil }
        let n = Double(fitBeatCount ?? beatCount)
        guard n > 1 else { return nil }
        let nominalPeriod = 3600.0 / Double(bph)
        let sigmaSlope = rms * 12.0.squareRoot() / pow(n, 1.5)
        return sigmaSlope / nominalPeriod * 86400.0
    }
}

/// 진행 중 측정의 라이브 메트릭 — UI 갱신용 스트림 페이로드.
struct LiveMetrics: Sendable, Equatable {
    var bph: Int?
    var rateSecondsPerDay: Double?
    var beatErrorMs: Double?
    var amplitudeDegrees: Double?
    var confidenceScore: Int
    var elapsedSeconds: Double
    /// envelope 기반 SNR (dB). BPH 락 후에만 의미 있음.
    var snrDB: Double?
    /// raw 마이크 RMS in dBFS (-∞ ~ 0). 마이크 자체가 신호 받고 있는지 확인용.
    var rawRMSDB: Double?
    /// 검출된 onset (tic) 개수 — 신호 주기성 체크.
    var onsetCount: Int?
    /// envelope peak/floor ratio — 신호 명료도.
    var envelopeDynamicRange: Double?
    /// Round 32 (Min): BPH lock 실패 시 어느 layer 에서 막혔는지. UI 진단 strip 에 노출.
    /// 사용자 보고: 91/70/117/47 onsets 어느 케이스도 lock 실패 — 그 동안 어떤 path 가 reject 했는지 모름.
    var lockFailReason: String?
    // Round 153 (Doyoon+Chen+Min coaching): 사용자 시각 피드백 점수.
    /// 0-100. rawRMSDB [-50, -20] dBFS linear remap. nil = 데이터 부족.
    var micContactScore: Int? = nil
    /// 0-100. 직전 5초 rate ring stddev → 역지수 매핑.
    var lockStabilityScore: Int? = nil
    /// Pro mode 진단용 — rate 의 rolling std-dev (s/d).
    var rateRollingStdDev: Double? = nil
    /// 사용자 요청: 실시간 tic/toc 점 시각화 — 최근 검출 onset 시각 (측정 시작 기준 seconds).
    /// 알고리즘 자체는 unchanged — 기존 detection 결과 외부 노출 전용. nil 이면 빈 화면.
    var recentOnsetTimes: [Double]? = nil
    /// Round 171 C3 (적응형 조기종료): 최근 rate 가 충분히 안정 + 신뢰도 확보 → 더 측정할 필요 없음.
    /// UI 가 true 를 보면 30초 cap 전에 자동 stop. 불안정하면 false 유지 → 계속 측정.
    var converged: Bool = false
}

/// 라이브 파형 표시용 페이로드. -1...1 범위 다운샘플 진폭 + 측정 시작부터의 경과 시각.
struct LiveWaveformChunk: Sendable, Equatable {
    /// 200개 정도로 다운샘플된 -1...1 범위 진폭.
    var samples: [Float]
    var elapsedSeconds: Double
}
