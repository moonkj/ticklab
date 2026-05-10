import Foundation
import SwiftUI

enum UserMode: String, CaseIterable {
    case beginner
    case expert
}

/// 앱 전역 사용자 설정 — 온보딩 완료 여부, 사용자 모드, 무음 측정 기본값.
/// `@AppStorage` 와 호환되도록 String/Bool 만 다룬다.
@Observable
final class UserPreferences {
    @ObservationIgnored
    private let defaults = UserDefaults.standard

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }

    var userMode: UserMode {
        didSet { defaults.set(userMode.rawValue, forKey: Keys.mode) }
    }

    var silentModeDefault: Bool {
        didSet { defaults.set(silentModeDefault, forKey: Keys.silentMode) }
    }

    init() {
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        let modeString = defaults.string(forKey: Keys.mode) ?? UserMode.beginner.rawValue
        self.userMode = UserMode(rawValue: modeString) ?? .beginner
        self.silentModeDefault = defaults.bool(forKey: Keys.silentMode)
    }

    private enum Keys {
        static let onboarding = "ticklab.onboardingComplete"
        static let mode = "ticklab.userMode"
        static let silentMode = "ticklab.silentModeDefault"
    }
}
