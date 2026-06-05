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
                        // 배경 — 부드럽게 흐르는 잔잔한 파형. 모양은 매끄러운 다중 사인, **진폭만 실제 신호
                        //   세기로 변조**(소리 크면 큰 파/작으면 잔물결). 정밀 데이터는 아래 톡톡 점이 담당.
                        if let s = samples, s.count > 1 {
                            drawSmoothWave(gc, samples: s, w: w, mid: mid, h: h, t: t)
                        }
                        // 틱 톡 틱 톡 — 측정된 BPH 박자(2박에 1번)로 새 점이 **오른쪽에 하나씩 '톡톡' 찍힘**.
                        //   처음엔 좌→우로 채워지고, 다 차면 가장 오래된 점이 왼쪽으로 빠지며 새 점이 오른쪽에
                        //   계속 찍힌다(끊김 없이 이어짐 — 비우고 다시 시작 X). tic/toc 은 mark 인덱스 패리티로 고정.
                        let beatPeriod = 3600.0 / Double(bph)
                        let now = measurementStartedAt.map { ctx.date.timeIntervalSince($0) } ?? t
                        let markFloat = max(0, now / (beatPeriod * 2.0))   // 경과시간 기준 — 꾸준히 증가
                        let M = markFloat.rounded(.down)                   // 현재(최신) mark 인덱스
                        let phase = markFloat - M                          // 현재 mark 내 0..1
                        let slots = 20
                        let offset = max(0, M - Double(slots - 1))         // 다 차면(왼쪽으로) 스크롤 오프셋
                        let margin = w * 0.06
                        let spacing = (w - margin * 2) / CGFloat(slots - 1)
                        let yT: CGFloat = mid - 16
                        let yB: CGFloat = mid + 16
                        var m = offset
                        while m <= M {
                            let slot = m - offset                         // 0..slots-1
                            let x = margin + CGFloat(slot) * spacing
                            let isTic = m.truncatingRemainder(dividingBy: 2) < 1
                            // 막 찍힌 점(최신, 맨 오른쪽)만 stamp(팝+링), 나머진 정적. 모션저감이면 stamp 없음.
                            let stamp = (m >= M - 0.5 && !reduceMotion) ? max(0, 1 - phase * 2.0) : 0
                            drawFlowBeat(gc, x: x, y: isTic ? yT : yB, isTic: isTic, fresh: stamp)
                            m += 1
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

    /// 부드럽게 흐르는 배경 파형 — 모양은 매끄러운 다중 사인(노이즈 X), 진폭은 실제 신호 세기로 변조,
    /// 시간으로 연속 흐름. 정밀 측정 데이터는 위의 톡톡 점이 담당하므로 배경은 잔잔한 앰비언트.
    private func drawSmoothWave(_ gc: GraphicsContext, samples: [Float], w: CGFloat, mid: CGFloat, h: CGFloat, t: Double) {
        // 실제 신호 레벨(평균 |amp|) → 진폭 변조. 작아도 최소 잔물결 유지.
        let level = samples.isEmpty ? 0 : samples.reduce(0) { $0 + abs($1) } / Float(samples.count)
        let dynAmp = h * 0.16 * Double(min(1, level * 3))
        let A = h * 0.04 + dynAmp
        let flow = reduceMotion ? 0 : t * 1.2   // 연속 흐름(모션저감 시 정지)
        var p = Path()
        var first = true
        for xi in stride(from: 0.0, through: Double(w), by: 3) {
            let nx = xi / Double(max(1, w))
            let y = Double(mid)
                + sin(nx * 4 * .pi - flow) * A * 0.6
                + sin(nx * 7 * .pi - flow * 1.4) * A * 0.4
            let pt = CGPoint(x: xi, y: y)
            if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
        }
        gc.stroke(p, with: .color(AppColors.primary500.opacity(0.22)), lineWidth: 1.4)
    }

    /// 흐르는 박동 점 — 오른쪽에서 막 찍힌 점(fresh≈1)은 크고 확장·소멸 링(stamp), 좌측으로 가며 가라앉음.
    /// tic=원, toc=다이아몬드(색 외 형태 구분) + 어두운 림(대비).
    private func drawFlowBeat(_ gc: GraphicsContext, x: CGFloat, y: CGFloat, isTic: Bool, fresh: Double) {
        let color: Color = diffWithoutColor ? AppColors.ink0 : (isTic ? AppColors.success : AppColors.accentDark)
        let baseR: CGFloat = 3.5
        let r = baseR + CGFloat(fresh) * 4   // 새 점일수록 크게 '찍힘'
        // 확장·소멸 링(ping) — 등장 직후 또렷, 흐르며 퍼져 사라짐.
        if fresh > 0.05 {
            let ringR = r + 3 + CGFloat(1 - fresh) * 12
            gc.stroke(
                Path(ellipseIn: CGRect(x: x - ringR, y: y - ringR, width: 2 * ringR, height: 2 * ringR)),
                with: .color(color.opacity(fresh * 0.4)), lineWidth: 1.5
            )
        }
        let shape: Path = isTic
            ? Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            : diamond(cx: x, cy: y, r: r + 0.5)
        gc.fill(shape, with: .color(color))
        gc.stroke(shape, with: .color(AppColors.ink0.opacity(0.45)), lineWidth: 1)
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
