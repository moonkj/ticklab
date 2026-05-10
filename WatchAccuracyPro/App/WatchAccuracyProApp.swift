import SwiftUI
import SwiftData

@main
struct WatchAccuracyProApp: App {
    @State private var preferences = UserPreferences()
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: Watch.self, WatchMeasurement.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: false)
            )
        } catch {
            fatalError("ModelContainer 생성 실패: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(preferences)
        }
        .modelContainer(container)
    }
}

private struct RootView: View {
    @Environment(UserPreferences.self) private var preferences
    @State private var modeChosen = false

    var body: some View {
        if !preferences.hasCompletedOnboarding {
            OnboardingView {
                preferences.hasCompletedOnboarding = true
            }
        } else if !modeChosen && !UserDefaults.standard.bool(forKey: "ticklab.modeChosenOnce") {
            ModeSelectView { mode in
                preferences.userMode = mode
                UserDefaults.standard.set(true, forKey: "ticklab.modeChosenOnce")
                modeChosen = true
            }
        } else {
            CollectionView()
        }
    }
}
