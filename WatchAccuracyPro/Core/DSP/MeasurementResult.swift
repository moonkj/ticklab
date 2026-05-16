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
        let windowPenalty: Int = {
            guard let d = crossWindowDelta, d > 25 else { return 0 }
            return Int(min(20, d - 25))
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
    let rateSecondsPerDay: Double
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

    /// 후방 호환 — UI 가 String key 를 직접 다루는 코드가 있으면 이 프로퍼티 사용.
    var reliabilityNoteKey: String? { reliabilityNote?.rawValue }
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
}

/// 라이브 파형 표시용 페이로드. -1...1 범위 다운샘플 진폭 + 측정 시작부터의 경과 시각.
struct LiveWaveformChunk: Sendable, Equatable {
    /// 200개 정도로 다운샘플된 -1...1 범위 진폭.
    var samples: [Float]
    var elapsedSeconds: Double
}
