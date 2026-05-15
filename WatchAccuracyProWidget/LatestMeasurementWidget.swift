import SwiftUI
import WidgetKit

/// 가장 최근 측정 결과를 홈/잠금화면 위젯으로 노출.
/// 데이터는 App Group UserDefaults 에 저장된 LatestMeasurementSnapshot 을 읽어 사용.
struct LatestMeasurementWidget: Widget {
    let kind = "com.ticklab.watchaccuracypro.widget.latest"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LatestMeasurementProvider()) { entry in
            LatestMeasurementWidgetView(entry: entry)
        }
        .configurationDisplayName("TickLab")
        .description("Latest watch accuracy measurement")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct LatestMeasurementEntry: TimelineEntry {
    let date: Date
    let snapshot: LatestMeasurementSnapshot?
}

struct LatestMeasurementProvider: TimelineProvider {
    func placeholder(in context: Context) -> LatestMeasurementEntry {
        LatestMeasurementEntry(date: Date(), snapshot: .placeholder)
    }
    func getSnapshot(in context: Context, completion: @escaping (LatestMeasurementEntry) -> Void) {
        completion(LatestMeasurementEntry(date: Date(), snapshot: SharedSnapshotStore.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LatestMeasurementEntry>) -> Void) {
        let entry = LatestMeasurementEntry(date: Date(), snapshot: SharedSnapshotStore.read())
        // 다음 갱신은 30분 후. 새 측정 시 앱이 reloadAllTimelines() 호출.
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct LatestMeasurementWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: LatestMeasurementEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText())
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text(entry.snapshot?.watchName ?? "TickLab").font(.headline)
                Text(rateText()).font(.caption.monospaced())
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.snapshot?.watchName ?? "—").font(.caption).lineLimit(1)
                Text(rateText()).font(.title2.monospacedDigit())
                if let amplitude = entry.snapshot?.amplitudeDegrees {
                    Text("\(Int(amplitude))°").font(.caption2)
                }
                Text(timestampText()).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private func inlineText() -> String {
        guard let s = entry.snapshot else { return "TickLab" }
        return "\(s.watchName) · \(rateText())"
    }

    private func rateText() -> String {
        guard let s = entry.snapshot else { return "—" }
        return String(format: "%+.1f s/d", s.rateSecondsPerDay)
    }

    private func timestampText() -> String {
        guard let s = entry.snapshot else { return "" }
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: s.timestamp, relativeTo: Date())
    }
}
