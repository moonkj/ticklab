import SwiftUI
import WidgetKit

@main
struct WatchAccuracyProWidgetBundle: WidgetBundle {
    var body: some Widget {
        LatestMeasurementWidget()
        if #available(iOS 16.2, *) {
            MeasurementLiveActivityWidget()
        }
    }
}
