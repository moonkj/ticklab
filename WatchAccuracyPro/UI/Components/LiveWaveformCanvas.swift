import SwiftUI

/// 측정 라이브 신호 — **실측 진폭 엔벨로프**(waveformSamples) + 실제 검출 onset(tic/toc).
/// (이전엔 lock 시 장식용 합성 sin 을 그려 실데이터와 충돌 → 정직한 신호로 교체.)
///
/// 접근성/성능(전문가 검토 반영):
/// - tic=원, toc=다이아몬드 + 어두운 림 → 색 외 형태로도 구분(색맹/저시력) + paper2 라이트모드 대비 확보.
/// - Reduce Motion: 합성 흐름/대시 crawl 제거(데이터 갱신만), fps 저감.
/// - 60fps 상한(Hard Rule 4) 유지 + 저전력/모션저감 시 30/20fps 로 graceful degrade.
struct LiveWaveformCanvas: View {
    var running: Bool = true
    /// raw waveform samples (-1...1). 실측 진폭 링버퍼(좌→우 흐름). nil 이면 가는 baseline.
    var samples: [Float]? = nil
    /// Round 158: detected BPH (locked). nil 이면 검출 중(dashed line).
    var lockedBPH: Int? = nil
    /// DSP 가 실제 검출한 onset timestamps(측정 시작 기준 seconds). 실시간 tic/toc.
    var recentOnsetTimes: [Double]? = nil
    var measurementStartedAt: Date? = nil
    var showProInfo: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var diffWithoutColor

    /// 60fps 상한 + graceful degrade. 모션저감/저전력에선 낮춰 budget·배터리 보호.
    private var fps: Double {
        if reduceMotion { return 20 }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return 30 }
        return 60
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TimelineView(.animation(minimumInterval: 1.0 / fps, paused: !running)) { ctx in
                Canvas { gc, size in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let w = size.width
                    let h = size.height
                    let mid = h / 2

                    // 가로 grid 4선.
                    for y in stride(from: 0.0, through: h, by: h / 4) {
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                        gc.stroke(p, with: .color(AppColors.primary500.opacity(0.12)), lineWidth: 1)
                    }

                    if running, let bph = lockedBPH, bph > 0 {
                        // 1) 실측 진폭 엔벨로프 (합성 sin 제거). 신호가 약하면 낮고 노이즈하게, 깨끗하면 또렷한 버스트.
                        if let s = samples, s.count > 1 {
                            drawEnvelope(gc, samples: s, w: w, mid: mid, h: h)
                        } else {
                            var base = Path(); base.move(to: CGPoint(x: 0, y: mid)); base.addLine(to: CGPoint(x: w, y: mid))
                            gc.stroke(base, with: .color(AppColors.primary500.opacity(0.3)), lineWidth: 1)
                        }
                        // 2) 실제 onset — tic(원)/toc(다이아몬드), 5초 viewport, latest 기준.
                        if let onsets = recentOnsetTimes, let latest = onsets.last {
                            let secondsPerScreen: Double = 5.0
                            let viewEnd = latest
                            let viewStart = viewEnd - secondsPerScreen
                            let yT: CGFloat = mid - 16
                            let yB: CGFloat = mid + 16
                            for (i, ts) in onsets.enumerated() where ts >= viewStart && ts <= viewEnd {
                                let progress = (ts - viewStart) / secondsPerScreen
                                let x = CGFloat(progress) * w
                                let isTic = (i % 2 == 0)
                                drawBeat(gc, x: x, y: isTic ? yT : yB, isTic: isTic)
                            }
                        }
                    } else if running {
                        // lock 전 — 측정 중 dashed line. 모션저감이면 고정, 아니면 흐름.
                        let dashLen: CGFloat = 8, gapLen: CGFloat = 6
                        let cycle = dashLen + gapLen
                        let off = reduceMotion ? 0 : CGFloat(t * 30).truncatingRemainder(dividingBy: cycle)
                        var x = -cycle + off
                        var dashes = Path()
                        while x < w {
                            dashes.move(to: CGPoint(x: max(0, x), y: mid))
                            dashes.addLine(to: CGPoint(x: min(w, x + dashLen), y: mid))
                            x += cycle
                        }
                        gc.stroke(dashes, with: .color(AppColors.primary500.opacity(0.45)), lineWidth: 1.6)
                    } else {
                        // idle — 정적 baseline.
                        var baseline = Path()
                        baseline.move(to: CGPoint(x: 0, y: mid))
                        baseline.addLine(to: CGPoint(x: w, y: mid))
                        gc.stroke(baseline, with: .color(AppColors.primary500.opacity(0.2)), lineWidth: 1)
                    }
                }
            }
            legend
        }
        .background(AppColors.paper2)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // 접근성: Canvas 는 시각 전용 — 수치는 metrics/diagnostic 셀이 음성 안내.
        .accessibilityHidden(true)
    }

    /// 실측 진폭을 거울 밴드 + 상단 rim 으로. 3-tap smoothing 으로 샘플 지글거림 완화.
    private func drawEnvelope(_ gc: GraphicsContext, samples: [Float], w: CGFloat, mid: CGFloat, h: CGFloat) {
        let n = samples.count
        guard n > 1 else { return }
        let amp = h * 0.34
        let mags: [CGFloat] = (0..<n).map { i in
            let a = samples[max(0, i - 1)], b = samples[i], c = samples[min(n - 1, i + 1)]
            return min(1.0, CGFloat(abs((a + b + c) / 3))) * amp
        }
        func px(_ i: Int) -> CGFloat { CGFloat(i) / CGFloat(n - 1) * w }
        var band = Path()
        band.move(to: CGPoint(x: 0, y: mid - mags[0]))
        for i in 1..<n { band.addLine(to: CGPoint(x: px(i), y: mid - mags[i])) }
        for i in stride(from: n - 1, through: 0, by: -1) { band.addLine(to: CGPoint(x: px(i), y: mid + mags[i])) }
        band.closeSubpath()
        gc.fill(band, with: .color(AppColors.primary500.opacity(0.12)))
        var rim = Path()
        rim.move(to: CGPoint(x: 0, y: mid - mags[0]))
        for i in 1..<n { rim.addLine(to: CGPoint(x: px(i), y: mid - mags[i])) }
        gc.stroke(rim, with: .color(AppColors.primary500.opacity(0.8)), lineWidth: 1.3)
    }

    /// 검출 박동 — tic=원, toc=다이아몬드(형태 구분) + 어두운 림(대비). 색은 보조.
    private func drawBeat(_ gc: GraphicsContext, x: CGFloat, y: CGFloat, isTic: Bool) {
        let r: CGFloat = 4
        let fillColor: Color = diffWithoutColor
            ? AppColors.ink0
            : (isTic ? AppColors.success : AppColors.accentDark)
        let shape: Path = isTic
            ? Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            : diamond(cx: x, cy: y, r: r + 0.5)
        gc.fill(shape, with: .color(fillColor))
        gc.stroke(shape, with: .color(AppColors.ink0.opacity(0.5)), lineWidth: 1)
    }

    private func diamond(cx: CGFloat, cy: CGFloat, r: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: cx, y: cy - r))
        p.addLine(to: CGPoint(x: cx + r, y: cy))
        p.addLine(to: CGPoint(x: cx, y: cy + r))
        p.addLine(to: CGPoint(x: cx - r, y: cy))
        p.closeSubpath()
        return p
    }

    /// 범례 — 색 + 형태(원/다이아몬드)로 이중 표기.
    private var legend: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Circle().fill(diffWithoutColor ? AppColors.ink0 : AppColors.success).frame(width: 6, height: 6)
                Text("tic").font(.system(size: 10, weight: .medium)).foregroundStyle(AppColors.ink2)
            }
            HStack(spacing: 4) {
                Rectangle().fill(diffWithoutColor ? AppColors.ink0 : AppColors.accentDark)
                    .frame(width: 6, height: 6).rotationEffect(.degrees(45))
                Text("toc").font(.system(size: 10, weight: .medium)).foregroundStyle(AppColors.ink2)
            }
        }
        .padding(.bottom, 8)
        .padding(.trailing, 12)
    }
}

#Preview {
    VStack {
        LiveWaveformCanvas(running: true)
            .frame(height: 170)
        LiveWaveformCanvas(running: true, samples: (0..<200).map { Float(sin(Double($0) * 0.3)) * 0.6 }, lockedBPH: 28800,
                           recentOnsetTimes: (0..<20).map { Double($0) * 0.25 })
            .frame(height: 170)
        LiveWaveformCanvas(running: true, samples: [0.1, 0.2], lockedBPH: nil)
            .frame(height: 170)
    }
    .padding()
    .background(AppColors.paper0)
}
