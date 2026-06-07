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
            // 측정 데이터(rate) 왼쪽에 밸런스 휠 — 측정 엔진의 시그니처.
            HStack(spacing: 8) {
                BalanceWheelGlyph(size: 30)
                Text(rateText())
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(rateColor()).lineLimit(1).minimumScaleFactor(0.6)
            }
            HStack(spacing: 10) {
                metric("metronome", beatErrorText())
                if showsAmplitude { metric("gauge.medium", amplitudeText()) }
            }
            // 기계식 → 다음 오버홀, 배터리 구동(스마트워치/쿼츠) → 배터리. 데이터 있을 때만.
            statusChip
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
                    // 측정 데이터(rate) 왼쪽에 밸런스 휠 — 측정 엔진의 시그니처. (HTML 목업 레이아웃)
                    HStack(spacing: 11) {
                        BalanceWheelGlyph(size: 46)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(rateText())
                                .font(.system(.title, design: .rounded).weight(.bold))
                                .foregroundStyle(rateColor()).lineLimit(1).minimumScaleFactor(0.5)
                            Text(timestampText()).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    metric("metronome", beatErrorText())
                    if showsAmplitude {
                        metric("gauge.medium", amplitudeText())
                    } else {
                        // Hard Rule #9: medium/low 신뢰도 캘리버는 amplitude 비노출 → bph 로 대체 표시.
                        metric("timer", bphText())
                    }
                    metric("checkmark.seal", confidenceText())
                    statusMetric
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
                if showsAmplitude {
                    Text(amplitudeText()).font(.caption2).foregroundStyle(.secondary)
                }
            }
            // 세 번째 줄: 데이터 있으면 배터리/오버홀, 없으면 기존 bph·시각.
            if let status = statusText() {
                Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("\(bphText()) · \(timestampText())")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
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

    // MARK: - 상태 행 (배터리 / 다음 오버홀) — 무브먼트 타입에 따라 분기

    /// small 레이아웃용 칩 — 데이터 없으면 렌더 안 함(공간 절약).
    @ViewBuilder private var statusChip: some View {
        if let info = statusInfo() {
            HStack(spacing: 4) {
                Image(systemName: info.icon).font(.system(size: 10))
                Text(info.text).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(info.tint)
        }
    }

    /// medium 레이아웃용 metric 행 — 데이터 없으면 timestamp 로 fallback(빈 줄 방지).
    @ViewBuilder private var statusMetric: some View {
        if let info = statusInfo() {
            HStack(spacing: 4) {
                Image(systemName: info.icon).font(.system(size: 10)).foregroundStyle(info.tint).frame(width: 14)
                Text(info.text)
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(info.tint).lineLimit(1).minimumScaleFactor(0.7)
            }
        } else {
            metric("timer", bphText())
        }
    }

    private struct StatusInfo { let icon: String; let text: String; let tint: Color }

    /// 무브먼트 타입에 따라 배터리(스마트워치/쿼츠) 또는 다음 오버홀(기계식)을 결정. 데이터 없으면 nil.
    private func statusInfo() -> StatusInfo? {
        guard let s = entry.snapshot else { return nil }
        if s.isBatteryPowered {
            guard let pct = s.batteryPercent else { return nil }
            let tint: Color = pct <= 15 ? .red : (pct <= 30 ? .orange : .green)
            return StatusInfo(icon: batteryIcon(pct), text: "\(pct)%", tint: tint)
        } else {
            guard let due = s.nextOverhaulDate else { return nil }
            let overdue = due < Date()
            return StatusInfo(
                icon: "wrench.and.screwdriver",
                text: overhaulText(due),
                tint: overdue ? .red : .secondary
            )
        }
    }

    /// accessory(잠금화면)용 한 줄 문자열. 데이터 없으면 nil → 호출부가 bph fallback.
    private func statusText() -> String? {
        guard let info = statusInfo() else { return nil }
        return info.text
    }

    private func batteryIcon(_ pct: Int) -> String {
        switch pct {
        case ..<13:  return "battery.0percent"
        case ..<38:  return "battery.25percent"
        case ..<63:  return "battery.50percent"
        case ..<88:  return "battery.75percent"
        default:     return "battery.100percent"
        }
    }

    /// 다음 오버홀 텍스트 — 지났으면 "정비 필요", 아니면 상대 기한.
    private func overhaulText(_ date: Date) -> String {
        if date < Date() { return String(localized: "widget.overhaul.due") }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = [.year, .month]
        formatter.maximumUnitCount = 1
        let interval = date.timeIntervalSince(Date())
        let rel = formatter.string(from: interval) ?? ""
        // "1개월 후 정비" 형태 — 라벨 키에 %@ 로 기한 삽입.
        return String(format: String(localized: "widget.overhaul.in"), rel)
    }

    /// Hard Rule #9: 신뢰도 라벨이 medium/low 인 캘리버는 amplitude 노출 금지.
    /// 라벨이 nil(legacy) 이면 종전대로 amplitude 표시 허용.
    private var showsAmplitude: Bool {
        guard entry.snapshot?.amplitudeDegrees != nil else { return false }
        switch entry.snapshot?.confidenceLabel {
        case "medium", "low": return false
        default:              return true
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

/// 밸런스 휠 벡터 — 골드 그라데이션 림 + 안쪽 링 + 3스포크(끝에 타이밍 스크류) + 허브.
/// ⚠️ WidgetKit 홈 위젯은 자유 애니메이션이 불가(타임라인 스냅샷 렌더)하므로 **정지 벡터**로 표시한다.
/// 살짝 기운 각도로 '정지 상태의 실제 밸런스 휠'처럼 보이게 함.
struct BalanceWheelGlyph: View {
    var size: CGFloat = 44
    /// 정지 각도 — 대칭이 아니라 살짝 기운 모습(실물 느낌).
    var angle: Double = 16

    private let goldLight = Color(red: 0.91, green: 0.79, blue: 0.48)
    private let goldMid   = Color(red: 0.79, green: 0.66, blue: 0.30)
    private let goldDark  = Color(red: 0.60, green: 0.48, blue: 0.18)
    private let hub       = Color(red: 0.08, green: 0.08, blue: 0.11)

    var body: some View {
        Canvas { ctx, sz in
            let s = min(sz.width, sz.height)
            let u = s / 100                       // HTML viewBox(100) 기준 스케일
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)

            func circleRect(_ r: CGFloat) -> CGRect {
                CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            }

            // 림(골드 그라데이션)
            ctx.stroke(
                Path(ellipseIn: circleRect(38 * u)),
                with: .linearGradient(
                    Gradient(colors: [goldLight, goldMid, goldDark]),
                    startPoint: CGPoint(x: c.x - 38 * u, y: c.y - 38 * u),
                    endPoint: CGPoint(x: c.x + 38 * u, y: c.y + 38 * u)),
                lineWidth: 7 * u)
            // 안쪽 링
            ctx.stroke(Path(ellipseIn: circleRect(31 * u)),
                       with: .color(goldMid.opacity(0.35)), lineWidth: 1.5 * u)

            // 3스포크 + 끝 스크류(120°씩)
            for k in 0..<3 {
                var g = ctx
                g.translateBy(x: c.x, y: c.y)
                g.rotate(by: .degrees(Double(k) * 120))
                var spoke = Path()
                spoke.move(to: .zero)
                spoke.addLine(to: CGPoint(x: 0, y: -35 * u))
                g.stroke(spoke, with: .color(goldDark),
                         style: StrokeStyle(lineWidth: 4.5 * u, lineCap: .round))
                let dr = 3 * u
                g.fill(Path(ellipseIn: CGRect(x: -dr, y: -36 * u - dr, width: dr * 2, height: dr * 2)),
                       with: .color(goldMid))
            }

            // 허브
            ctx.fill(Path(ellipseIn: circleRect(6 * u)), with: .color(goldMid))
            ctx.fill(Path(ellipseIn: circleRect(2.5 * u)), with: .color(hub))
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(angle))
    }
}
