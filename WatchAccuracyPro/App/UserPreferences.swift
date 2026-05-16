import Foundation
import SwiftUI

enum UserMode: String, CaseIterable {
    case novice    // 디자인 SSOT 명칭. 기존 코드 호환을 위해 "beginner" 도 alias 로 받음.
    case pro       // 디자인 SSOT. 기존 "expert" alias.

    /// 기존 raw value 호환 — 사용자가 이전 빌드에서 "beginner"/"expert" 저장한 케이스 흡수.
    init?(rawValue: String) {
        switch rawValue {
        case "novice", "beginner":  self = .novice
        case "pro", "expert":       self = .pro
        default:                    return nil
        }
    }

    /// CaseIterable 의 default allCases 가 위 init 으로 우회 안 되도록 명시.
    static var allCases: [UserMode] { [.novice, .pro] }
}

/// 앱 전역 사용자 설정 — 온보딩 완료 여부, 사용자 모드, 무음 측정 기본값.
/// `@AppStorage` 와 호환되도록 String/Bool 만 다룬다.
@Observable
final class UserPreferences {
    @ObservationIgnored
    private let defaults = UserDefaults.standard
    /// Round 23 (Min): NotificationCenter observer token — deinit 에서 removeObserver 하기 위함.
    @ObservationIgnored
    private var proEntitlementObserver: NSObjectProtocol?

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }

    var userMode: UserMode {
        didSet { defaults.set(userMode.rawValue, forKey: Keys.mode) }
    }

    var silentModeDefault: Bool {
        didSet { defaults.set(silentModeDefault, forKey: Keys.silentMode) }
    }

    /// Phase 3 — CloudKit 동기화 활성화 여부. 변경 시 다음 앱 시작에 반영(ModelContainer 재생성 필요).
    var iCloudSyncEnabled: Bool {
        didSet { defaults.set(iCloudSyncEnabled, forKey: Keys.iCloud) }
    }

    /// Phase 2 — 무브먼트 DB 자동 OTA 업데이트.
    var autoUpdateMovementDB: Bool {
        didSet { defaults.set(autoUpdateMovementDB, forKey: Keys.autoOTA) }
    }

    /// Phase 2 — 실험적 CoreML beat detector 활성화 (모델 부재 시 자동 fall-back).
    var useCoreMLBeatDetector: Bool {
        didSet { defaults.set(useCoreMLBeatDetector, forKey: Keys.coreML) }
    }

    /// Round 40 (Pivot Pro): Pro IAP unlock. 영구. one-time purchase.
    var isPro: Bool {
        didSet { defaults.set(isPro, forKey: Keys.isPro) }
    }

    /// App lock 활성화 — Face ID / Touch ID.
    var appLockEnabled: Bool {
        didSet { defaults.set(appLockEnabled, forKey: Keys.appLock) }
    }

    /// 일기 알림 — 매일 저녁 reminder.
    var journalReminderEnabled: Bool {
        didSet { defaults.set(journalReminderEnabled, forKey: Keys.journalReminder) }
    }
    /// Round 128 (이주현 H5): 일기 알림 시간 사용자 설정. 기본 21:00.
    var journalReminderHour: Int {
        didSet { defaults.set(journalReminderHour, forKey: Keys.journalReminderHour) }
    }
    var journalReminderMinute: Int {
        didSet { defaults.set(journalReminderMinute, forKey: Keys.journalReminderMinute) }
    }

    /// Apple Intelligence 기반 측정 진단 사용 — 기본 ON.
    /// OFF 면 rule-based 폴백만 사용 (LLM 호출 안 함).
    var aiVerdictEnabled: Bool {
        didSet { defaults.set(aiVerdictEnabled, forKey: Keys.aiVerdict) }
    }

    /// 랜덤 시계 뽑기 — 매일 설정한 시간에 등록된 시계 중 하나를 랜덤으로 알림.
    var randomPickEnabled: Bool {
        didSet { defaults.set(randomPickEnabled, forKey: Keys.randomPick) }
    }
    var randomPickHour: Int {
        didSet { defaults.set(randomPickHour, forKey: Keys.randomPickHour) }
    }
    var randomPickMinute: Int {
        didSet { defaults.set(randomPickMinute, forKey: Keys.randomPickMinute) }
    }

    /// 측정 중 항상 화면 켜기 — 기본값 ON (사용자 요청).
    var keepScreenOnDuringMeasurement: Bool {
        didSet { defaults.set(keepScreenOnDuringMeasurement, forKey: Keys.keepScreenOn) }
    }

    /// 자기장 측정 기능 활성화 — Apple Intelligence 코멘트 연동.
    var magneticFieldMeasurementEnabled: Bool {
        didSet { defaults.set(magneticFieldMeasurementEnabled, forKey: Keys.magneticField) }
    }

    /// 커스텀 PIN (별도 설정 가능, 6자리). 비어 있으면 PIN 미설정.
    /// Keychain 에 해시 저장. UserDefaults 에는 placeholder 만.
    var pinEnabled: Bool {
        didSet { defaults.set(pinEnabled, forKey: Keys.pinEnabled) }
    }

    /// Round 170 (사용자 보고: tickIQ ±5 s/d vs 우리 ±20-30 s/d):
    /// tickIQ-style simplified DSP pipeline 사용 (BP → envelope → MAD threshold → median IOI tight-3%).
    /// 기존 PLL/Template/OLS 경로 우회. 기본 ON (실험).
    var useSimplifiedDSP: Bool {
        didSet { defaults.set(useSimplifiedDSP, forKey: Keys.useSimplifiedDSP) }
    }

    init() {
        // Round 23 (Min): defaults.register — 외부 reader (Settings.app) / 다른 process 에서도
        //   ON-by-default 키들이 일관된 fallback. didSet 으로 한 번이라도 write 한 값은 우선 유지.
        defaults.register(defaults: [
            Keys.autoOTA: false,
            Keys.aiVerdict: true,
            Keys.keepScreenOn: true,
            Keys.journalReminderHour: 21,
            Keys.journalReminderMinute: 0,
            Keys.randomPickHour: 8,
            Keys.randomPickMinute: 0,
            Keys.useSimplifiedDSP: true
        ])
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        // Round 133: 사용자 모드 선택 UI 제거됨 — 항상 .pro 로 고정 (전문 분석 노출).
        // 사용자 보고 fix: 기본 .novice 이라서 MeasurementResultView details, WatchDetail specs,
        //   lift-angle override 등 5곳이 모든 유저에게 영구 hidden 이었음.
        let modeString = defaults.string(forKey: Keys.mode) ?? UserMode.pro.rawValue
        self.userMode = UserMode(rawValue: modeString) ?? .pro
        self.silentModeDefault = defaults.bool(forKey: Keys.silentMode)
        self.iCloudSyncEnabled = defaults.bool(forKey: Keys.iCloud)
        // Round 6 (Hyemi): 외부 호출 사용자 동의는 명시적 opt-in 으로. 기본 OFF.
        // Settings 에서 사용자가 토글하면 그 후로만 manifest 를 fetch.
        self.autoUpdateMovementDB = defaults.object(forKey: Keys.autoOTA) as? Bool ?? false
        self.useCoreMLBeatDetector = defaults.bool(forKey: Keys.coreML)
        self.isPro = defaults.bool(forKey: Keys.isPro)
        self.appLockEnabled = defaults.bool(forKey: Keys.appLock)
        self.journalReminderEnabled = defaults.bool(forKey: Keys.journalReminder)
        self.journalReminderHour = (defaults.object(forKey: Keys.journalReminderHour) as? Int) ?? 21
        self.journalReminderMinute = (defaults.object(forKey: Keys.journalReminderMinute) as? Int) ?? 0
        // 기본 ON — 사용자가 명시 OFF 안 했으면 AI 시도.
        self.aiVerdictEnabled = (defaults.object(forKey: Keys.aiVerdict) as? Bool) ?? true
        self.randomPickEnabled = defaults.bool(forKey: Keys.randomPick)
        self.randomPickHour = (defaults.object(forKey: Keys.randomPickHour) as? Int) ?? 8
        self.randomPickMinute = (defaults.object(forKey: Keys.randomPickMinute) as? Int) ?? 0
        // 기본 ON — 사용자 요청 (측정 중 잠금 화면 진입 방지).
        self.keepScreenOnDuringMeasurement = (defaults.object(forKey: Keys.keepScreenOn) as? Bool) ?? true
        self.magneticFieldMeasurementEnabled = defaults.bool(forKey: Keys.magneticField)
        self.pinEnabled = defaults.bool(forKey: Keys.pinEnabled)
        // Round 170: simplified DSP — 기본 ON. 사용자가 명시 OFF 해야 legacy 경로 사용.
        self.useSimplifiedDSP = (defaults.object(forKey: Keys.useSimplifiedDSP) as? Bool) ?? true
        // Round 149 (Hyemi 7 H1): ProEntitlement.markPro 가 호출되면 isPro 인스턴스 즉시 동기화.
        // Round 23 (Min): observer token 보관 → deinit 에서 removeObserver.
        proEntitlementObserver = NotificationCenter.default.addObserver(
            forName: .ticklabProEntitlementChanged, object: nil, queue: .main
        ) { [weak self] note in
            guard let on = note.userInfo?["isPro"] as? Bool else { return }
            self?.isPro = on
        }
    }

    deinit {
        if let token = proEntitlementObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private enum Keys {
        static let onboarding = "ticklab.onboardingComplete"
        static let mode = "ticklab.userMode"
        static let silentMode = "ticklab.silentModeDefault"
        static let iCloud = "ticklab.iCloudSyncEnabled"
        static let autoOTA = "ticklab.autoUpdateMovementDB"
        static let coreML = "ticklab.useCoreMLBeatDetector"
        static let isPro = "ticklab.isPro"
        static let appLock = "ticklab.appLockEnabled"
        static let journalReminder = "ticklab.journalReminderEnabled"
        static let journalReminderHour = "ticklab.journalReminderHour"
        static let journalReminderMinute = "ticklab.journalReminderMinute"
        static let aiVerdict = "ticklab.aiVerdictEnabled"
        static let randomPick = "ticklab.randomPickEnabled"
        static let randomPickHour = "ticklab.randomPickHour"
        static let randomPickMinute = "ticklab.randomPickMinute"
        static let keepScreenOn = "ticklab.keepScreenOnDuringMeasurement"
        static let magneticField = "ticklab.magneticFieldMeasurementEnabled"
        static let pinEnabled = "ticklab.pinEnabled"
        static let useSimplifiedDSP = "ticklab.useSimplifiedDSP"
        /// 측정 시작 화면의 풀와인딩 안내 토스트 마지막 노출 시각 (TimeInterval since 1970).
        /// 24h 이내 재진입 시 다시 안 띄움 — noise 줄이기 위함.
        static let windingHintShownAt = "ticklab.windingHintShownAt"
    }
}
