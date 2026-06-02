import Foundation

/// Round 172/173 (사용자 제안): 폰 하드웨어 발진기(mach/systemUptime) vs 진짜시간 드리프트 자동 보정.
///
/// 배경: rate 측정의 잔여 고정편향(예: −5.8 s/d ≈ +68ppm)은 이 iPhone 발진기가 진짜시간 대비 어긋난 것이다.
/// **진짜시간 기준 = iOS wall clock(`Date`)** — iOS 가 NTP 로 disciplined 하므로 장기 주파수가 진짜시간(원자시계)에
/// 맞춰져 있다(사용자 표현 "원자시계 대비"를 iOS 의 NTP 규율로 그대로 활용). wall 은 **로컬 시계라 표본 지터 0**
/// (네트워크 NTP 직접질의의 ±수십 ms 지터 없음) — 단지 slew wobble 만 있는데 이는 **분 단위 구간**에 걸쳐 평균화된다.
/// (Round 173 실측: per-measurement 22초 창 비교는 slew wobble 로 noisy → 철회. mach 는 단기 안정 reference.)
///
/// 사용자 입력 없음. 앱 실행/foreground/**측정마다** (mono=systemUptime, wall=Date) 점을 누적 → 회귀로 ppm 산출.
/// baseline(누적 점들의 시간 범위)이 길수록 정밀. 측정 ~3회(수 분)면 baseline 충족 → 빠른 수렴.
/// 같은 부팅 세션 내 점만 유효(mono 리셋=재부팅 감지).
final class ClockCalibrationService {
    static let shared = ClockCalibrationService()

    private let defaults: UserDefaults
    private let lock = NSLock()
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private enum Keys {
        static let monos    = "ticklab.clockcal.monos"     // [Double] systemUptime 점들(부팅 세션 기준)
        static let trues    = "ticklab.clockcal.trues"     // [Double] 대응 wall(Date) unix 시각
        static let driftPpm = "ticklab.clockcal.driftPpm"  // 확정 ppm (0 = 미수렴)
    }

    /// 최소 baseline(초). wall 은 표본 지터 0(로컬 시계)이라 분 단위면 충분 — 측정 ~3회(수 분)면 수렴.
    /// slew wobble 은 이 구간에 평균화. 그 전엔 보정 0(정직히 "보정 중").
    static let minBaselineSeconds: Double = 120
    /// sanity — 이 범위 밖 ppm 은 이상치로 보고 무시.
    static let maxAbsPpm: Double = 200
    /// 점 누적 상한 / 최소 간격(초). 간격 이내 중복은 skip(launch+foreground 버스트 방지). 측정 start/end 2점 허용.
    static let maxPoints = 60
    static let minSpacingSeconds: Double = 15

    /// 현재 추정 발진기 드리프트(ppm, mono−true). 미수렴이면 0.
    var driftPpm: Double { defaults.double(forKey: Keys.driftPpm) }

    /// beatSec(또는 period)에 곱할 보정 계수 (mach초 → 진짜초). driftPpm 0이면 1.0(무보정).
    var correctionFactor: Double { 1.0 / (1.0 + driftPpm / 1_000_000.0) }

    /// 이미 baseline 이 충분해 ppm 이 확정됐는지(보정 적용 중인지).
    var isCalibrated: Bool { driftPpm != 0 }

    /// 누적된 보정 점 수(진단/UX 용).
    var pointCount: Int { (defaults.array(forKey: Keys.monos) as? [Double])?.count ?? 0 }

    /// NTP 진짜시각을 얻을 때마다 호출. systemUptime(mono)과 쌍으로 점을 누적 → 회귀로 드리프트 갱신.
    /// - Parameter trueUnixTime: NTP 보정된 진짜 시각(Unix epoch seconds).
    func recordCalibrationPoint(trueUnixTime: Double) {
        let nowMono = ProcessInfo.processInfo.systemUptime
        lock.lock(); defer { lock.unlock() }

        var monos = defaults.array(forKey: Keys.monos) as? [Double] ?? []
        var trues = defaults.array(forKey: Keys.trues) as? [Double] ?? []
        if monos.count != trues.count { monos = []; trues = [] }   // 손상 방어

        // 재부팅(mono 역행) → 이전 점들은 다른 부팅 세션이라 비교 불가. 리셋.
        if let lastMono = monos.last, nowMono < lastMono - 1.0 {
            monos = []; trues = []
            defaults.set(0.0, forKey: Keys.driftPpm)
        }
        // 너무 촘촘하면 skip(baseline 안 늘고 점만 낭비). 단 첫 점은 무조건 추가.
        if let lastMono = monos.last, nowMono - lastMono < Self.minSpacingSeconds { return }

        monos.append(nowMono); trues.append(trueUnixTime)
        // 상한 초과 시 2번째 점 제거(최초 앵커=긴 baseline 보존, 최근 밀도 유지).
        if monos.count > Self.maxPoints { monos.remove(at: 1); trues.remove(at: 1) }

        defaults.set(monos, forKey: Keys.monos)
        defaults.set(trues, forKey: Keys.trues)

        if let ppm = Self.regressionPpm(monos: monos, trues: trues,
                                        minBaseline: Self.minBaselineSeconds, maxAbsPpm: Self.maxAbsPpm) {
            defaults.set(ppm, forKey: Keys.driftPpm)
        }
    }

    /// 누적 (mono, true) 점들의 최소제곱 회귀로 드리프트(ppm) 산출(순수·테스트 가능).
    /// span(true 범위) ≥ minBaseline 이고 |ppm| ≤ maxAbsPpm 일 때만 값, 아니면 nil.
    /// 모델: mono ≈ a + s·true → 발진기가 빠르면 s>1 → ppm = (s−1)×1e6 > 0.
    static func regressionPpm(monos: [Double], trues: [Double],
                              minBaseline: Double, maxAbsPpm: Double) -> Double? {
        guard monos.count == trues.count, monos.count >= 2,
              let tMin = trues.min(), let tMax = trues.max() else { return nil }
        guard (tMax - tMin) >= minBaseline else { return nil }
        let n = Double(monos.count)
        let meanT = trues.reduce(0, +) / n
        let meanM = monos.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for i in 0..<monos.count {
            let dt = trues[i] - meanT
            num += dt * (monos[i] - meanM)
            den += dt * dt
        }
        guard den > 0 else { return nil }
        let ppm = (num / den - 1.0) * 1_000_000.0
        guard abs(ppm) <= maxAbsPpm else { return nil }
        return ppm
    }

    /// 단일 쌍 드리프트 계산(순수·테스트 가능 — 회귀 이전 버전 호환). baseline 부족/이상치면 nil.
    static func driftPpm(monotonicElapsed: Double, trueElapsed: Double,
                         minBaseline: Double, maxAbsPpm: Double) -> Double? {
        guard trueElapsed >= minBaseline, monotonicElapsed > 0 else { return nil }
        let ppm = (monotonicElapsed - trueElapsed) / trueElapsed * 1_000_000.0
        guard abs(ppm) <= maxAbsPpm else { return nil }
        return ppm
    }

    /// (mono=systemUptime, wall=Date) 보정 점을 1개 누적한다. 네트워크 불필요·즉시.
    /// 앱 실행/foreground/측정 start·end 에서 호출 → 측정 ~3회면 baseline 충족.
    func recordPoint() {
        recordCalibrationPoint(trueUnixTime: Date().timeIntervalSince1970)
    }

    /// 호환 유지(앱 launch/scene .active 호출부) — 이제 네트워크 없이 wall 점만 누적.
    func calibrateNow() async {
        recordPoint()
    }
}
