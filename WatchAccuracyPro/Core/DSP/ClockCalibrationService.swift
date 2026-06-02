import Foundation

/// Round 172 (사용자 제안): 폰 발진기(시스템 monotonic 클록) vs NTP 원자시간 드리프트 자동 보정.
///
/// 배경: rate 측정의 잔여 고정편향(예: −4.8 s/d)은 이 iPhone 발진기가 진짜 원자시간 대비 ~수십 ppm
/// 어긋난 것이다. 폰 내부 클록(오디오·mach·wall)은 모두 같은 발진기에서 나와 **내부만으론 측정 불가** —
/// 외부 진짜시간(NTP) 과 비교해야 한다. iOS 가 wall clock 은 보정하지만 `systemUptime`(mach, monotonic)은
/// 보정하지 않으므로, monotonic↔NTP 진짜시간 쌍을 누적하면 발진기 드리프트가 드러난다.
///
/// 사용자 입력 없음. 최초 측정에 앵커를 잡고 이후 측정마다 갱신 → baseline 길수록 정밀(NTP 지터 평균화).
final class ClockCalibrationService {
    static let shared = ClockCalibrationService()

    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private enum Keys {
        static let anchorMono = "ticklab.clockcal.anchorMono"
        static let anchorTrue = "ticklab.clockcal.anchorTrue"
        static let driftPpm   = "ticklab.clockcal.driftPpm"
    }

    /// 최소 baseline(초). NTP 지터(~수십 ms) 대비 ±수 ppm 정밀 위해 1시간. 그 전엔 보정 0.
    static let minBaselineSeconds: Double = 3600
    /// sanity — 이 범위 밖 ppm 은 NTP 오류/이상치로 보고 무시.
    static let maxAbsPpm: Double = 200

    /// 현재 추정 발진기 드리프트(ppm, monotonic−true). 미수렴이면 0.
    var driftPpm: Double { defaults.double(forKey: Keys.driftPpm) }

    /// beatSec(또는 period)에 곱할 보정 계수 (mach초 → 진짜초). driftPpm 0이면 1.0(무보정).
    var correctionFactor: Double { 1.0 / (1.0 + driftPpm / 1_000_000.0) }

    /// NTP 진짜시각을 얻을 때마다 호출. systemUptime(monotonic)과 쌍으로 앵커 누적 → 드리프트 갱신.
    /// - Parameter trueUnixTime: NTP 보정된 진짜 시각(Unix epoch seconds).
    func recordCalibrationPoint(trueUnixTime: Double) {
        let nowMono = ProcessInfo.processInfo.systemUptime
        let anchorMono = defaults.object(forKey: Keys.anchorMono) as? Double
        let anchorTrue = defaults.object(forKey: Keys.anchorTrue) as? Double
        // 앵커 없음 또는 재부팅(monotonic 역행) → 앵커 재설정(보정 baseline 리셋).
        guard let am = anchorMono, let at = anchorTrue, nowMono >= am else {
            defaults.set(nowMono, forKey: Keys.anchorMono)
            defaults.set(trueUnixTime, forKey: Keys.anchorTrue)
            return
        }
        if let ppm = Self.driftPpm(monotonicElapsed: nowMono - am, trueElapsed: trueUnixTime - at,
                                   minBaseline: Self.minBaselineSeconds, maxAbsPpm: Self.maxAbsPpm) {
            defaults.set(ppm, forKey: Keys.driftPpm)
        }
    }

    /// 순수 드리프트 계산(테스트 가능). baseline 부족/이상치면 nil.
    static func driftPpm(monotonicElapsed: Double, trueElapsed: Double,
                         minBaseline: Double, maxAbsPpm: Double) -> Double? {
        guard trueElapsed >= minBaseline, monotonicElapsed > 0 else { return nil }
        let ppm = (monotonicElapsed - trueElapsed) / trueElapsed * 1_000_000.0
        guard abs(ppm) <= maxAbsPpm else { return nil }
        return ppm
    }

    /// 이미 baseline 이 충분해 ppm 이 확정됐는지(보정 적용 중인지).
    var isCalibrated: Bool { driftPpm != 0 }

    /// NTP 진짜시간을 한 번 받아 보정 점을 누적한다. **측정과 무관** — 앱 foreground/측정 등에서 호출.
    /// 측정 안 해도 앱을 1시간+ 간격으로 다시 열면 baseline 이 차서 보정이 확정된다.
    func calibrateNow() async {
        guard let sample = try? await AtomicTimeService.shared.fetchSample() else { return }
        // 진짜시간 = 기기 wall − NTP offset (AtomicTimeService 컨벤션).
        let trueUnix = Date().timeIntervalSince1970 - sample.offsetSeconds
        recordCalibrationPoint(trueUnixTime: trueUnix)
    }
}
