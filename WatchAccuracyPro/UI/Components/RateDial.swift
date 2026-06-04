import Foundation
import SwiftUI

/// Semi-circular rate dial — 디자인 mockup 의 RateDial.
/// 색상 zone: danger / warn / ok / warn / danger
/// scale: −30 ~ +30 s/day
///
/// 웨이브2-B: `animatedRate == true` 면 결과 진입 시 바늘이 0(12시)에서 실제 rate 각도로
/// ~1.1s 언더댐핑 spring 스윕(자동차 계기판 시동 메타포). 도착 순간 해당 COSC zone arc 가 0.15s 글로우 펄스.
/// Reduce Motion 이면 즉시 최종각(연출 생략). idle 시 정지 — TimelineView 상시가동 없음.
struct RateDial: View {
    let rate: Double
    var size: CGFloat = 200
    /// true 면 onAppear 에 0 → rate 스윕 애니메이션. false(기본)면 정적 표시(기존 동작 보존).
    var animatedRate: Bool = false

    private let minVal: Double = -30
    private let maxVal: Double = 30

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 바늘이 가리키는 현재 rate(애니메이션 대상). 정적 모드에선 항상 = rate.
    @State private var displayRate: Double = 0
    /// 도착 글로우 펄스 강도(0…1). 도착 순간 1 → 0.15s 페이드.
    @State private var glowPulse: Double = 0
    @State private var didAnimate = false

    var body: some View {
        let w = size
        let h = size * 0.62
        let clamped = min(maxVal, max(minVal, rate))
        return DialCanvas(
            displayRate: animatedRate ? displayRate : rate,
            targetRate: clamped,
            glowPulse: glowPulse,
            minVal: minVal,
            maxVal: maxVal,
            reduceGlow: reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        .frame(width: w, height: h + 10)
        // Round 176: VoiceOver — 다이얼이 의미 있는 값임을 음성으로.
        .accessibilityElement()
        .accessibilityLabel(String(format: NSLocalizedString("a11y.rate_dial", comment: ""),
                                    rate, String(localized: "unit.seconds_per_day")))
        .onAppear {
            guard animatedRate, !didAnimate else { return }
            didAnimate = true
            // Reduce Motion: 즉시 최종각, 연출 생략.
            guard !reduceMotion else {
                displayRate = clamped
                return
            }
            displayRate = 0
            // 언더댐핑 오버슈트(계기판 시동) — interpolatingSpring stiffness 120 / damping 12.
            withAnimation(.interpolatingSpring(stiffness: 120, damping: 12)) {
                displayRate = clamped
            }
            // 도착 시점(~0.85s)에 해당 zone arc 글로우 펄스(0.15s). Low Power 시 생략.
            if !ProcessInfo.processInfo.isLowPowerModeEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                    glowPulse = 1
                    withAnimation(.easeOut(duration: 0.15)) { glowPulse = 0 }
                }
            }
        }
    }
}

// MARK: - Canvas layer (animatable)

/// Canvas 렌더 본체. `displayRate`·`glowPulse` 가 애니메이션 가능한 값으로 주입되어
/// SwiftUI 가 매 프레임 보간 → 단발 애니메이션 동안에만 redraw(idle 시 정지).
private struct DialCanvas: View, Animatable {
    var displayRate: Double
    let targetRate: Double
    var glowPulse: Double
    let minVal: Double
    let maxVal: Double
    let reduceGlow: Bool

    /// displayRate·glowPulse 둘 다 보간 대상.
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(displayRate, glowPulse) }
        set { displayRate = newValue.first; glowPulse = newValue.second }
    }

    var body: some View {
        Canvas { context, canvasSize in
            let h = canvasSize.height - 10
            let cx = canvasSize.width / 2
            let cy = canvasSize.height * (h / (h + 10))
            let r = canvasSize.width / 2 - 16

            // 도착 zone 글로우 펄스 — 바늘이 멈추는 zone arc 만 강조.
            if !reduceGlow && glowPulse > 0.001 {
                let (zFrom, zTo, zColor) = zoneFor(targetRate)
                strokeArc(context, cx: cx, cy: cy, r: r, from: zFrom, to: zTo,
                          color: zColor.opacity(0.55 * glowPulse), lineWidth: 14)
            }

            // zones
            strokeArc(context, cx: cx, cy: cy, r: r, from: angleFor(-30), to: angleFor(-20),
                      color: AppColors.danger, lineWidth: 6)
            strokeArc(context, cx: cx, cy: cy, r: r, from: angleFor(-20), to: angleFor(-6),
                      color: AppColors.warning, lineWidth: 6)
            strokeArc(context, cx: cx, cy: cy, r: r, from: angleFor(-6), to: angleFor(6),
                      color: AppColors.success, lineWidth: 6)
            strokeArc(context, cx: cx, cy: cy, r: r, from: angleFor(6), to: angleFor(20),
                      color: AppColors.warning, lineWidth: 6)
            strokeArc(context, cx: cx, cy: cy, r: r, from: angleFor(20), to: angleFor(30),
                      color: AppColors.danger, lineWidth: 6)

            // major ticks + labels
            let majors: [Double] = [-30, -20, -10, 0, 10, 20, 30]
            for v in majors {
                let a = angleFor(v)
                let p1 = polar(cx: cx, cy: cy, r: r, angle: a)
                let p2 = polar(cx: cx, cy: cy, r: r + 8, angle: a)
                var tick = Path()
                tick.move(to: p1)
                tick.addLine(to: p2)
                context.stroke(tick, with: .color(AppColors.ink3), lineWidth: 1)

                let pt = polar(cx: cx, cy: cy, r: r + 18, angle: a)
                let label = (v >= 0 ? "+" : "") + String(format: "%.0f", v)
                let text = Text(label).font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AppColors.ink3)
                let resolved = context.resolve(text)
                context.draw(resolved,
                             at: CGPoint(x: pt.x, y: pt.y),
                             anchor: .center)
            }

            // needle — 웨이브2-B: gold-foil 폴리시(linear gradient hub→tip).
            let valueAngle = angleFor(min(maxVal, max(minVal, displayRate)))
            let np = polar(cx: cx, cy: cy, r: r, angle: valueAngle)
            var needle = Path()
            needle.move(to: CGPoint(x: cx, y: cy))
            needle.addLine(to: np)
            let goldFoil = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [AppColors.accentDark, AppColors.accent, AppColors.accentLight]),
                startPoint: CGPoint(x: cx, y: cy),
                endPoint: np
            )
            context.stroke(needle, with: goldFoil,
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            // center cap — gold hub.
            context.fill(Path(ellipseIn: CGRect(x: cx - 5.5, y: cy - 5.5, width: 11, height: 11)),
                         with: .color(AppColors.accentDark))
            context.fill(Path(ellipseIn: CGRect(x: cx - 2, y: cy - 2, width: 4, height: 4)),
                         with: .color(AppColors.paper0))
        }
    }

    // MARK: - Geometry

    private func angleFor(_ v: Double) -> Double {
        // 0 → −30, 180 → +30 (mockup 과 동일 — 좌측 = 음수)
        (v - minVal) / (maxVal - minVal) * 180
    }
    private func polar(cx: CGFloat, cy: CGFloat, r: CGFloat, angle deg: Double) -> CGPoint {
        // angle 0..180, semi-circle 그리려면 (deg - 180) 적용
        let rad: CGFloat = CGFloat((deg - 180) * .pi / 180)
        return CGPoint(x: cx + r * CoreGraphics.cos(rad), y: cy + r * CoreGraphics.sin(rad))
    }
    private func strokeArc(_ context: GraphicsContext, cx: CGFloat, cy: CGFloat, r: CGFloat,
                           from: Double, to: Double, color: Color, lineWidth: CGFloat) {
        var path = Path()
        let p1 = polar(cx: cx, cy: cy, r: r, angle: from)
        path.move(to: p1)
        path.addArc(
            center: CGPoint(x: cx, y: cy),
            radius: r,
            startAngle: .degrees(from - 180),
            endAngle: .degrees(to - 180),
            clockwise: false
        )
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }

    /// rate 가 속한 COSC zone 의 arc 범위(각도)와 색.
    private func zoneFor(_ v: Double) -> (Double, Double, Color) {
        switch v {
        case ..<(-20): return (angleFor(-30), angleFor(-20), AppColors.danger)
        case ..<(-6):  return (angleFor(-20), angleFor(-6),  AppColors.warning)
        case ...6:     return (angleFor(-6),  angleFor(6),   AppColors.success)
        case ...20:    return (angleFor(6),   angleFor(20),  AppColors.warning)
        default:       return (angleFor(20),  angleFor(30),  AppColors.danger)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        RateDial(rate: 1.8, size: 220, animatedRate: true)
        RateDial(rate: -18, size: 220)
        RateDial(rate: 28, size: 220)
    }
    .padding().background(AppColors.paper0)
}
