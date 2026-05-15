import ActivityKit
import SwiftUI
import WidgetKit

/// 측정 중 잠금화면/Dynamic Island 에 노출되는 Live Activity widget.
/// Phase 2 베타: 구체적 디자인은 manual QA 후 폴리싱 예정.
@available(iOS 16.2, *)
struct MeasurementLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MeasurementActivityAttributes.self) { context in
            // Lock-screen / Banner UI
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(context.attributes.watchName).font(.headline)
                    Spacer()
                    Text(elapsed(context.state.elapsedSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack {
                    metric("Rate", value: context.state.rateSecondsPerDay.map { String(format: "%+.1f", $0) } ?? "—")
                    metric("BPH", value: context.state.bph.map(String.init) ?? "—")
                    metric("Conf", value: "\(context.state.confidenceScore)")
                }
            }
            .padding(12)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.watchName).font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(elapsed(context.state.elapsedSeconds))
                        .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        metric("Rate", value: context.state.rateSecondsPerDay.map { String(format: "%+.1f", $0) } ?? "—")
                        metric("BPH", value: context.state.bph.map(String.init) ?? "—")
                    }
                }
            } compactLeading: {
                Image(systemName: "waveform")
            } compactTrailing: {
                Text(elapsed(context.state.elapsedSeconds))
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "waveform")
            }
        }
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.body.monospacedDigit())
        }
    }

    private func elapsed(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
