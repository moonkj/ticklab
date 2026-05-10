import Foundation

/// DSPPipeline 의 분석 산출물. UI 표시용 + SwiftData 저장용 중간 모델.
struct MeasurementResult: Equatable, Sendable {
    let bph: Int
    let rateSecondsPerDay: Double
    let beatErrorMs: Double
    /// 코악시얼/스프링드라이브 또는 추정 실패 시 nil.
    let amplitudeDegrees: Double?
    let confidenceScore: Int
    let durationSeconds: Int
    let snrDB: Double
    let beatCount: Int
    /// 코악시얼 등 reliability 가 medium/low 일 때 사용자에게 보일 안내 키.
    let reliabilityNoteKey: String?
}

/// 진행 중 측정의 라이브 메트릭 — UI 갱신용 스트림 페이로드.
struct LiveMetrics: Sendable, Equatable {
    var bph: Int?
    var rateSecondsPerDay: Double?
    var beatErrorMs: Double?
    var amplitudeDegrees: Double?
    var confidenceScore: Int
    var elapsedSeconds: Double
}
