import Foundation
import MetricKit

/// Sprint 2 (P0-5.1): MetricKit 구독 — Apple 내장, 외부 SDK 없이 hang/crash/메모리 경고 수집.
///
/// MetricKit 은 시스템이 24시간마다 payload 를 전송 — 실시간 알림 X. 누적 diagnostic 로그용.
/// App.swift 의 launch 직후 1회 호출하여 구독.
///
/// 보고된 payload 는 (DEBUG 빌드) console 출력 / (Release) 향후 원격 collector 로 업로드 가능.
/// Phase 1 hard rule #6 (외부 API) 준수 — 현재 단계는 on-device 출력만.
final class MetricKitSubscriber: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitSubscriber()
    private override init() { super.init() }

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            log(payload: payload)
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            logDiagnostic(payload: payload)
        }
    }

    private func log(payload: MXMetricPayload) {
        #if DEBUG
        let app = payload.applicationLaunchMetrics
        let hangs = app?.histogrammedTimeToFirstDraw
        print("📊 MetricKit metric payload: launches=\(payload.applicationTimeMetrics?.cumulativeForegroundTime.value ?? 0), hangs=\(hangs?.totalBucketCount ?? 0)")
        #endif
    }

    private func logDiagnostic(payload: MXDiagnosticPayload) {
        #if DEBUG
        if let crashes = payload.crashDiagnostics, !crashes.isEmpty {
            print("⚠️ MetricKit crashes: \(crashes.count)")
        }
        if let hangs = payload.hangDiagnostics, !hangs.isEmpty {
            print("⚠️ MetricKit hangs: \(hangs.count)")
        }
        if let cpus = payload.cpuExceptionDiagnostics, !cpus.isEmpty {
            print("⚠️ MetricKit cpu exceptions: \(cpus.count)")
        }
        #endif
    }
}
