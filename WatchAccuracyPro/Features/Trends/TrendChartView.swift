import SwiftUI
import Charts

// MARK: - TrendRange

/// 트렌드 차트 기간 선택. WatchDetailView + TrendChartView 가 공유.
enum WatchDetailTrendRange: String, CaseIterable {
    case week = "7d", month = "30d", quarter = "90d", year = "1y", all = "ALL"

    var cutoffDate: Date {
        switch self {
        case .week:    return Date().addingTimeInterval(-7 * 86400)
        case .month:   return Date().addingTimeInterval(-30 * 86400)
        case .quarter: return Date().addingTimeInterval(-90 * 86400)
        case .year:    return Date().addingTimeInterval(-365 * 86400)
        case .all:     return .distantPast
        }
    }

    var days: Int {
        switch self {
        case .week: return 7; case .month: return 30; case .quarter: return 90
        case .year: return 365; case .all: return 9999
        }
    }

    /// Round 11: localized tab label (rawValue 영문 유지 — analytics/test 호환).
    var localizedLabel: String {
        switch self {
        case .week:    return String(localized: "trend.range.7d")
        case .month:   return String(localized: "trend.range.30d")
        case .quarter: return String(localized: "trend.range.90d")
        case .year:    return String(localized: "trend.range.1y")
        case .all:     return String(localized: "trend.range.all")
        }
    }

    /// VoiceOver용 자연어 라벨.
    var accessibilityLabel: String {
        switch self {
        case .week:    return String(localized: "trend.range.a11y.7d")
        case .month:   return String(localized: "trend.range.a11y.30d")
        case .quarter: return String(localized: "trend.range.a11y.90d")
        case .year:    return String(localized: "trend.range.a11y.1y")
        case .all:     return String(localized: "trend.range.a11y.all")
        }
    }
}

/// Round 73: 외부 컨테이너(WatchDetailView)의 range picker 가 이미 filter 한 measurements 를 받아 그리는 dumb presenter.
/// Round 171: range 전달 → chartXScale domain + chartXAxis label 이 range 에 맞게 고정.
/// 이전엔 x-axis 가 data 범위에만 맞춰져 range 바꿔도 날짜가 안 바뀌는 버그.
struct TrendChartView: View {
    let measurements: [WatchMeasurement]
    /// range = nil 이면 데이터 범위에 맞춤 (ALL 케이스 호환).
    var range: WatchDetailTrendRange?
    /// 스트림 D: Rate Drift 예측 ghost 선 표시 여부. 기본 ON.
    var showForecast: Bool = true
    /// 스크럽 — 드래그로 선택된 측정(그 시점 rate·날짜 말풍선).
    @State private var selected: WatchMeasurement?

    private var sorted: [WatchMeasurement] {
        measurements.sorted(by: { $0.timestamp < $1.timestamp })
    }

    /// 스트림 D: rate 추세 외삽. minCount 미달이면 nil → ghost 선 미표시(graceful degrade).
    /// 예측선은 마지막 측정 시각 → +horizon 일 까지 점선으로 그린다.
    private var forecast: RateForecastService.Forecast? {
        guard showForecast else { return nil }
        return RateForecastService.forecast(measurements: measurements)
    }

    /// ghost 예측선의 (시작점, 끝점). 마지막 측정 = anchor, +horizon 일 = projected.
    /// 끝점이 보이는 domain 밖이면 domain upperBound 로 clamp(그 지점 rate 로 재계산) — 어떤 range 든 점선이 보이게.
    private var forecastSegment: (start: (Date, Double), end: (Date, Double))? {
        guard let f = forecast, let lastDate = sorted.last?.timestamp else { return nil }
        let fullEndDate = lastDate.addingTimeInterval(Double(f.horizonDays) * 86_400)
        let domainEnd = xDomain.upperBound
        // 점선이 도메인을 넘으면 가시 영역 끝까지만 그리되, slope 로 그 지점 rate 를 보간.
        if fullEndDate <= domainEnd {
            return (start: (lastDate, f.currentRate), end: (fullEndDate, f.projectedRate))
        }
        guard domainEnd > lastDate else { return nil }
        let elapsedDays = domainEnd.timeIntervalSince(lastDate) / 86_400
        let clampedRate = f.currentRate + f.slopePerDay * elapsedDays
        return (start: (lastDate, f.currentRate), end: (domainEnd, clampedRate))
    }

    private var xDomain: ClosedRange<Date> {
        let now = Date()
        // 사용자 보고: 30d/1y range 에서 마지막 axis label (오늘) 이 chart 오른쪽 edge 에서 절반 잘려 "..." 표시.
        //   domain upperBound 에 trailing padding 추가 → 마지막 mark 가 chart 안쪽으로 위치, 라벨 완전 표시.
        guard let r = range else {
            let start = sorted.first?.timestamp ?? now.addingTimeInterval(-7 * 86400)
            return start...trailingPaddedEnd(now, range: nil)
        }
        switch r {
        case .all:
            let start = sorted.first?.timestamp ?? now.addingTimeInterval(-7 * 86400)
            return start...trailingPaddedEnd(now, range: r)
        default:
            return r.cutoffDate...trailingPaddedEnd(now, range: r)
        }
    }

    /// range 별 적정 trailing padding — 마지막 axis label 잘림 차단.
    /// week: 0.5 day, month: 1.5 day, quarter: 4 day, year: 15 day, all: 동적.
    private func trailingPaddedEnd(_ now: Date, range: WatchDetailTrendRange?) -> Date {
        let pad: TimeInterval
        switch range ?? .week {
        case .week:    pad = 86400 * 0.5
        case .month:   pad = 86400 * 1.5
        case .quarter: pad = 86400 * 4
        case .year:    pad = 86400 * 15
        case .all:     pad = 86400 * 2
        }
        return now.addingTimeInterval(pad)
    }

    var body: some View {
        Chart {
            if sorted.isEmpty {
                // 데이터 없어도 x-axis 날짜는 range 에 맞게 표시 — 투명 anchor point 로 domain 강제.
                PointMark(x: .value("date", xDomain.lowerBound), y: .value("rate", 0.0))
                    .foregroundStyle(.clear)
                PointMark(x: .value("date", xDomain.upperBound), y: .value("rate", 0.0))
                    .foregroundStyle(.clear)
            } else {
                ForEach(sorted, id: \.id) { m in
                    PointMark(
                        x: .value("date", m.timestamp),
                        y: .value("rate", m.rateSecondsPerDay)
                    )
                    .foregroundStyle(color(for: m).opacity(0.8))
                    .symbolSize(opacityFromConfidence(m.confidenceScore) * 80)
                }
                if sorted.count > 1 {
                    ForEach(sorted, id: \.id) { m in
                        LineMark(
                            x: .value("date", m.timestamp),
                            y: .value("rate", m.rateSecondsPerDay)
                        )
                        .foregroundStyle(AppColors.primary.opacity(0.5))
                        .interpolationMethod(.catmullRom)
                    }
                }
                // 스트림 D: ghost 예측선 — 마지막 측정에서 추세를 점선으로 외삽.
                if let seg = forecastSegment {
                    LineMark(x: .value("date", seg.start.0), y: .value("rate", seg.start.1),
                             series: .value("series", "forecast"))
                        .foregroundStyle(AppColors.accent.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    LineMark(x: .value("date", seg.end.0), y: .value("rate", seg.end.1),
                             series: .value("series", "forecast"))
                        .foregroundStyle(AppColors.accent.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    PointMark(x: .value("date", seg.end.0), y: .value("rate", seg.end.1))
                        .foregroundStyle(AppColors.accent.opacity(0.7))
                        .symbolSize(40)
                        .symbol(.diamond)
                }
                // 스크럽 선택 — 드래그한 지점의 측정 강조 + 말풍선.
                if let sel = selected {
                    RuleMark(x: .value("date", sel.timestamp))
                        .foregroundStyle(AppColors.ink3.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    PointMark(x: .value("date", sel.timestamp), y: .value("rate", sel.rateSecondsPerDay))
                        .foregroundStyle(color(for: sel))
                        .symbolSize(150)
                        .annotation(position: .top,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            scrubReadout(sel)
                        }
                }
            }
            RuleMark(y: .value("zero", 0)).foregroundStyle(AppColors.border)
        }
        .chartXScale(domain: xDomain)
        .chartXAxis { xAxisContent as AnyAxisContent }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in updateSelection(at: v.location, proxy: proxy, geo: geo) }
                            .onEnded { _ in selected = nil }
                    )
            }
        }
        .overlay {
            if sorted.isEmpty {
                // UX 고도화 — 빈 차트 대신 "미래를 미리보기": 글리프 + 격려 카피로 다음 행동 유도.
                VStack(spacing: 8) {
                    ConceptGlyph(systemName: "chart.line.uptrend.xyaxis", size: 30, color: AppColors.accent.opacity(0.55))
                    Text(String(localized: "trend.empty"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Text(String(localized: "trend.empty.hint",
                                defaultValue: "측정을 쌓으면 정확도 추세가 여기에 그려져요"))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.ink3)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
            }
        }
        .overlay(alignment: .topTrailing) {
            // 스트림 D: ghost 예측선 범례 + 90일 외삽 요약. 예측이 있을 때만.
            if let f = forecast {
                HStack(spacing: 4) {
                    ConceptGlyph(systemName: "chart.line.uptrend.xyaxis", size: 8)
                    Text(String(format: NSLocalizedString("forecast.legend.projected", comment: ""),
                                f.horizonDays, f.projectedRate))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(AppColors.accent.opacity(0.9))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(AppColors.accent.opacity(0.1))
                .clipShape(Capsule())
                .padding(4)
                .accessibilityLabel(Text(String(format: NSLocalizedString("forecast.legend.a11y", comment: ""),
                                                f.horizonDays, f.projectedRate, f.confidenceMargin)))
            }
        }
    }

    private var xAxisContent: AnyAxisContent {
        switch range ?? .week {
        case .week:
            return AnyAxisContent(AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                    .font(.system(size: 9, design: .monospaced))
            })
        case .month:
            return AnyAxisContent(AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                    .font(.system(size: 9, design: .monospaced))
            })
        case .quarter:
            return AnyAxisContent(AxisMarks(values: .stride(by: .month, count: 1)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            })
        case .year:
            return AnyAxisContent(AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            })
        case .all:
            // 실제 데이터 span 에 맞게 granularity 자동 조정.
            let spanDays = sorted.isEmpty ? 0 : {
                let s = sorted.first!.timestamp
                let e = sorted.last!.timestamp
                return Int(e.timeIntervalSince(s) / 86400)
            }()
            if spanDays <= 14 {
                return AnyAxisContent(AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        .font(.system(size: 9, design: .monospaced))
                })
            } else if spanDays <= 60 {
                return AnyAxisContent(AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        .font(.system(size: 9, design: .monospaced))
                })
            } else if spanDays <= 365 {
                return AnyAxisContent(AxisMarks(values: .stride(by: .month, count: 1)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                })
            } else {
                return AnyAxisContent(AxisMarks(values: .stride(by: .month, count: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                })
            }
        }
    }

    /// 드래그 위치 → 가장 가까운 측정 선택. 새 포인트로 바뀔 때마다 톡 햅틱(시계 박동 메타포).
    private func updateSelection(at point: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard !sorted.isEmpty, let plotFrame = proxy.plotFrame else { return }
        let x = point.x - geo[plotFrame].origin.x
        guard let date: Date = proxy.value(atX: x) else { return }
        guard let nearest = sorted.min(by: {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        }) else { return }
        if nearest.id != selected?.id {
            selected = nearest
            HapticManager.trigger(.selection)
        }
    }

    @ViewBuilder private func scrubReadout(_ m: WatchMeasurement) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%+.1f ", m.rateSecondsPerDay) + String(localized: "unit.seconds_per_day"))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(color(for: m))
            Text(m.timestamp.formatted(.dateTime.month().day().hour().minute()))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(AppColors.ink3)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    private func color(for m: WatchMeasurement) -> Color {
        let abs = abs(m.rateSecondsPerDay)
        if abs <= 6 { return AppColors.success }
        if abs <= 20 { return AppColors.warning }
        return AppColors.danger
    }

    private func opacityFromConfidence(_ score: Int) -> Double {
        max(0.3, Double(score) / 100)
    }
}

#Preview {
    let demo = (0..<10).map { idx in
        WatchMeasurement(
            timestamp: Date().addingTimeInterval(-Double(idx) * 86_400),
            rateSecondsPerDay: Double.random(in: -10...10),
            beatErrorMs: Double.random(in: 0.1...0.8),
            amplitudeDegrees: 280,
            bph: 28800,
            confidenceScore: Int.random(in: 60...95),
            durationSeconds: 60
        )
    }
    TrendChartView(measurements: demo, range: .month).padding()
}
