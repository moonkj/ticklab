import ActivityKit
import Foundation

/// Live Activity 의 시작/업데이트/종료 헬퍼.
/// 시뮬레이터에서 ActivityKit 가 제한적이므로 모든 호출은 try? 로 보호.
@available(iOS 16.2, *)
final class MeasurementLiveActivityService {
    static let shared = MeasurementLiveActivityService()

    private var activity: Activity<MeasurementActivityAttributes>?
    /// Round 7 (Sora): IPC 비용 + ActivityKit 의 자체 throttle 고려 — 우리도 5초 간격으로 cap.
    private let updateMinInterval: TimeInterval = 5.0
    private var lastUpdate: Date?

    /// Round 5 (Sora, audit): staleDate 명시. 측정은 길어도 5분 이내라 가정.
    /// 시스템이 stale 처리해 잠금화면에서 자동 사라지도록.
    private static let staleAfter: TimeInterval = 5 * 60

    func start(watchName: String, caliber: String?) {
        lastUpdate = nil
        // Round 169: 이전 측정의 Live Activity 가 남아있으면 정리 후 새로 시작.
        if let existing = activity {
            Task {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
            activity = nil
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = MeasurementActivityAttributes(
            watchName: watchName,
            caliber: caliber,
            startedAt: Date()
        )
        let initial = MeasurementActivityAttributes.MeasurementContentState.placeholder
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initial, staleDate: Date().addingTimeInterval(Self.staleAfter)),
                pushType: nil
            )
        } catch {
            // Live Activity 시작 실패는 측정 자체엔 영향 없음. 조용히 무시.
            activity = nil
        }
    }

    func update(with metrics: LiveMetrics) {
        let now = Date()
        if let last = lastUpdate, now.timeIntervalSince(last) < updateMinInterval { return }
        lastUpdate = now
        Task {
            let state = MeasurementActivityAttributes.MeasurementContentState(
                elapsedSeconds: metrics.elapsedSeconds,
                bph: metrics.bph,
                rateSecondsPerDay: metrics.rateSecondsPerDay,
                beatErrorMs: metrics.beatErrorMs,
                amplitudeDegrees: metrics.amplitudeDegrees,
                confidenceScore: metrics.confidenceScore
            )
            await activity?.update(.init(
                state: state,
                staleDate: Date().addingTimeInterval(Self.staleAfter)
            ))
        }
    }

    func end(final metrics: LiveMetrics?) {
        guard let activity else { return }
        Task {
            let state: MeasurementActivityAttributes.MeasurementContentState = metrics.map {
                .init(
                    elapsedSeconds: $0.elapsedSeconds,
                    bph: $0.bph,
                    rateSecondsPerDay: $0.rateSecondsPerDay,
                    beatErrorMs: $0.beatErrorMs,
                    amplitudeDegrees: $0.amplitudeDegrees,
                    confidenceScore: $0.confidenceScore
                )
            } ?? .placeholder
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        self.activity = nil
    }
}
