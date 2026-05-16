import Foundation
import CoreMotion

/// 주변 자기장 측정 서비스.
///
/// Round 180 (Sora): 기계식 시계는 자기장에 약함 — 자성화되면 정확도가 망가짐.
/// 측정 전에 주변 자기장을 체크해서 위험 환경(스피커, 헤드폰, 자석 등) 근처면 경고.
///
/// CMMotionManager 의 magnetometer raw data 를 사용.
/// 단위: microTesla (uT). 지구 자기장은 보통 25~65 uT.
///
/// - 외부 전송 없음 (Hard Rule 8) — 모든 처리는 on-device.
/// - 캘리브레이션 안 된 raw magnetometer 라서 절대값보다 상대 변화에 가까움.
///   다만 시계 자성화 위험 임계치(>200 uT)는 절대값으로도 충분히 식별 가능.
@MainActor
final class MagneticFieldService: ObservableObject {
    static let shared = MagneticFieldService()

    @Published private(set) var currentMicroTesla: Double = 0
    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var isSampling: Bool = false
    /// Round 137 사용자 요청: 실시간 그래프용 sample history (시간순 uT 값).
    @Published private(set) var sampleHistory: [Double] = []

    private let motionManager = CMMotionManager()

    private init() {
        isAvailable = motionManager.isMagnetometerAvailable
    }

    /// 자기장 측정 등급.
    /// 25~65 uT: 지구 자기장 (정상 범위). 측정 위치/각도 영향으로 변동 가능.
    /// - normal:        < 100 uT     — 정상. 측정에 영향 없음.
    /// - slightlyHigh:  100~300 uT   — 약간 높음. 작은 자성 물체 근처일 수 있음.
    /// - high:          300~1000 uT  — 높음. 시계 자성화 위험.
    /// - veryHigh:      >= 1000 uT   — 매우 높음. 즉시 멀리할 것.
    enum Level: String, CaseIterable, Sendable {
        case normal
        case slightlyHigh
        case high
        case veryHigh

        var localizationKey: String {
            switch self {
            case .normal:       return "magnetic.level.normal"
            case .slightlyHigh: return "magnetic.level.slightly_high"
            case .high:         return "magnetic.level.high"
            case .veryHigh:     return "magnetic.level.very_high"
            }
        }

        var verdictKey: String {
            switch self {
            case .normal:       return "magnetic.verdict.normal"
            case .slightlyHigh: return "magnetic.verdict.slightly_high"
            case .high:         return "magnetic.verdict.high"
            case .veryHigh:     return "magnetic.verdict.very_high"
            }
        }
    }

    /// uT 값을 등급으로 분류.
    /// PRD 의 임계치: 40/200/1000 이었으나 실측 시 지구 자기장만으로도 50~80 uT 가 흔히 나옴.
    /// 오탐 줄이려고 normal 상한을 100 uT 로 상향. 임계치는 운영하면서 조정 가능.
    static func level(microTesla: Double) -> Level {
        let v = Swift.abs(microTesla)
        switch v {
        case ..<100:    return .normal
        case ..<300:    return .slightlyHigh
        case ..<1000:   return .high
        default:        return .veryHigh
        }
    }

    /// `durationSeconds` 동안 약 30 sample 수집 후 median 반환.
    /// magnetometer 미지원 디바이스에서는 nil.
    /// 캘리브레이션 데이터(`startDeviceMotion`)는 권한·약간의 워밍업 필요 → 단순 magnetometer raw 사용.
    func sample(durationSeconds: Double = 3.0) async -> Double? {
        guard motionManager.isMagnetometerAvailable else {
            isAvailable = false
            return nil
        }
        // 사용자 보고 fix: re-entrancy guard — 두 sample() 동시 호출 시 shared motionManager/sampleHistory race 차단.
        guard !isSampling else { return nil }

        isAvailable = true
        isSampling = true
        sampleHistory = []  // Round 137: 새 측정 시 history 초기화.
        defer { isSampling = false }

        let sampleCount = 30
        let interval = max(0.05, durationSeconds / Double(sampleCount))
        motionManager.magnetometerUpdateInterval = interval

        // Round 133 BUG FIX: startMagnetometerUpdates(to:) 는 handler 필수 → no-arg 버전 사용.
        // magnetometerData 프로퍼티로 polling.
        motionManager.startMagnetometerUpdates()

        var magnitudes: [Double] = []
        magnitudes.reserveCapacity(sampleCount)

        let totalNanos = UInt64(durationSeconds * 1_000_000_000)
        let stepNanos = UInt64(interval * 1_000_000_000)
        var elapsedNanos: UInt64 = 0

        while elapsedNanos < totalNanos {
            // Round 19 (Doyoon): cancellation 즉시 반영 — 이전엔 isSampling=false 만 set 되고
            //   sleep loop 가 계속 진행되며 sample append 됨.
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: stepNanos)
            if Task.isCancelled { break }
            elapsedNanos += stepNanos
            if let field = motionManager.magnetometerData?.magneticField {
                // CMMagnetometerData.magneticField 는 uT 단위 (Apple docs).
                let m = sqrt(field.x * field.x + field.y * field.y + field.z * field.z)
                magnitudes.append(m)
                currentMicroTesla = m
                sampleHistory.append(m)  // Round 137: 실시간 그래프 갱신.
                // Round 19 (Sora): sampleHistory unbounded growth 차단 — 시각화는 최근 300 개만 충분.
                if sampleHistory.count > 300 { sampleHistory.removeFirst() }
            }
        }

        motionManager.stopMagnetometerUpdates()

        guard !magnitudes.isEmpty else { return nil }
        let sorted = magnitudes.sorted()
        let median = sorted[sorted.count / 2]
        currentMicroTesla = median
        return median
    }

    /// 진행 중인 sampling 즉시 종료. View 사라질 때 호출.
    func cancelSampling() {
        if motionManager.isMagnetometerActive {
            motionManager.stopMagnetometerUpdates()
        }
        isSampling = false
    }
}
