import AppIntents
import SwiftUI
import UIKit
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
        .description("widget.config.desc")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct LatestMeasurementEntry: TimelineEntry {
    let date: Date
    let snapshot: LatestMeasurementSnapshot?
    /// 위젯에 표시된 시계(=최근 측정)의 실제 "오늘 착용" 상태 — 버튼 on/off.
    let wornToday: Bool
}

struct LatestMeasurementProvider: TimelineProvider {
    private func makeEntry() -> LatestMeasurementEntry {
        LatestMeasurementEntry(date: Date(), snapshot: SharedSnapshotStore.read(),
                               wornToday: SharedSnapshotStore.readWornToday())
    }
    func placeholder(in context: Context) -> LatestMeasurementEntry {
        LatestMeasurementEntry(date: Date(), snapshot: .placeholder, wornToday: false)
    }
    func getSnapshot(in context: Context, completion: @escaping (LatestMeasurementEntry) -> Void) {
        completion(makeEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LatestMeasurementEntry>) -> Void) {
        // Round 17 (Sora): policy .never — 앱의 reloadAllTimelines(측정 save·착용 변경) 만 trigger.
        completion(Timeline(entries: [makeEntry()], policy: .never))
    }
}

struct LatestMeasurementWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: LatestMeasurementEntry

    /// 브랜드 골드(위젯 타깃은 AppColors 미접근 → 상수).
    private let brand = Color(red: 0.72, green: 0.55, blue: 0.21)

    var body: some View {
        content
            // iOS 17 필수: 위젯은 containerBackground 를 채택해야 시스템이 내용을 렌더한다.
            //   미채택 시 "Please adopt containerBackground API" placeholder 가 대신 표시됨(버그 원인).
            .containerBackground(for: .widget) { background }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText())
        case .accessoryRectangular:
            accessoryRectangular
        case .systemMedium:
            mediumLayout
        default:
            smallLayout
        }
    }

    // MARK: - 상단 브랜드 헤더 (앱 아이콘 + 이름)

    private var header: some View {
        HStack(spacing: 4) {
            Image("WidgetLogo")
                .resizable().scaledToFit()
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text("TickLab")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(brand)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 홈화면 small

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Text(entry.snapshot?.watchName ?? "—")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(rateText())
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(rateColor()).lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 10) {
                metric("metronome", beatErrorText())
                metric("gauge.medium", amplitudeText())
            }
            Spacer(minLength: 0)
            wearButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
    }

    // MARK: - 홈화면 medium (헤더 + 풀 메트릭 + 착용 버튼)

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.snapshot?.watchName ?? "—").font(.headline).lineLimit(1)
                    if let cal = entry.snapshot?.caliber, !cal.isEmpty {
                        Text(cal).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    Text(rateText())
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(rateColor()).lineLimit(1).minimumScaleFactor(0.5)
                    Text(timestampText()).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    metric("metronome", beatErrorText())
                    metric("gauge.medium", amplitudeText())
                    metric("timer", bphText())
                    metric("checkmark.seal", confidenceText())
                    Spacer(minLength: 2)
                    wearButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
    }

    // MARK: - 잠금화면 accessory (버튼 미지원 → 정보만)

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.snapshot?.watchName ?? "TickLab").font(.headline).lineLimit(1)
            HStack(spacing: 6) {
                Text(rateText()).font(.caption.monospacedDigit())
                Text("·").foregroundStyle(.secondary)
                Text(beatErrorText()).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                if entry.snapshot?.amplitudeDegrees != nil {
                    Text(amplitudeText()).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text("\(bphText()) · \(timestampText())")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    // MARK: - 오늘 착용 버튼 (iOS 17 인터랙티브 — WearToggleIntent)

    private var wearButton: some View {
        let worn = entry.wornToday
        let label: LocalizedStringKey = worn ? "widget.wear.done" : "widget.wear.today"
        return Button(intent: WearToggleIntent()) {
            HStack(spacing: 4) {
                Image(systemName: worn ? "checkmark.circle.fill" : "plus.circle")
                Text(label).lineLimit(1).minimumScaleFactor(0.7)
            }
            .font(.system(size: 12, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background((worn ? Color.green : brand).opacity(0.16), in: Capsule())
            .foregroundStyle(worn ? Color.green : brand)
        }
        .buttonStyle(.plain)
    }

    private func metric(_ icon: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 14)
            Text(value)
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    /// 잠금화면 accessory 위젯은 투명(시스템 vibrancy), 홈화면 system 위젯은 불투명 배경.
    @ViewBuilder private var background: some View {
        switch family {
        case .accessoryRectangular, .accessoryInline, .accessoryCircular:
            Color.clear
        default:
            Color(.systemBackground)
        }
    }

    // MARK: - 포맷터 (단위는 언어 중립)

    private func inlineText() -> String {
        guard let s = entry.snapshot else { return "TickLab" }
        return "\(s.watchName) · \(rateText())"
    }

    private func rateText() -> String {
        guard let s = entry.snapshot else { return "—" }
        return String(format: "%+.1f s/d", s.rateSecondsPerDay)
    }

    private func beatErrorText() -> String {
        guard let s = entry.snapshot else { return "—" }
        return String(format: "%.1f ms", s.beatErrorMs)
    }

    private func amplitudeText() -> String {
        guard let a = entry.snapshot?.amplitudeDegrees else { return "—" }
        return "\(Int(a))°"
    }

    private func bphText() -> String {
        guard let s = entry.snapshot else { return "—" }
        return "\(s.bph) bph"
    }

    private func confidenceText() -> String {
        guard let s = entry.snapshot else { return "—" }
        return "\(s.confidenceScore)%"
    }

    /// rate 정확도 색상 — 앱 공통 톤(±6 우수 / ±20 양호 / 그 외 주의).
    private func rateColor() -> Color {
        guard let s = entry.snapshot else { return .primary }
        let a = abs(s.rateSecondsPerDay)
        if a <= 6 { return .green }
        if a <= 20 { return .orange }
        return .red
    }

    private func timestampText() -> String {
        guard let s = entry.snapshot else { return "" }
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: s.timestamp, relativeTo: Date())
    }
}
