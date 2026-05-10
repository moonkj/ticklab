import SwiftUI
import SwiftData

@main
struct WatchAccuracyProApp: App {
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
            ContentView()
        }
        .modelContainer(container)
    }
}
