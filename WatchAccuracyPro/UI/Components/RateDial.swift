import Foundation
import SwiftUI

/// Semi-circular rate dial — 디자인 mockup 의 RateDial.
/// 색상 zone: danger / warn / ok / warn / danger
/// scale: −30 ~ +30 s/day
struct RateDial: View {
    let rate: Double
    var size: CGFloat = 200

    private let minVal: Double = -30
    private let maxVal: Double = 30

    var body: some View {
        let w = size
        let h = size * 0.62
        return Canvas { context, canvasSize in
            let cx = canvasSize.width / 2
            let cy = canvasSize.height * (h / (h + 10))
            let r = canvasSize.width / 2 - 16

            // zones
            stroke(context, cx: cx, cy: cy, r: r, from: angleFor(-30), to: angleFor(-20),
                   color: AppColors.danger, lineWidth: 6)
            stroke(context, cx: cx, cy: cy, r: r, from: angleFor(-20), to: angleFor(-6),
                   color: AppColors.warning, lineWidth: 6)
            stroke(context, cx: cx, cy: cy, r: r, from: angleFor(-6), to: angleFor(6),
                   color: AppColors.success, lineWidth: 6)
            stroke(context, cx: cx, cy: cy, r: r, from: angleFor(6), to: angleFor(20),
                   color: AppColors.warning, lineWidth: 6)
            stroke(context, cx: cx, cy: cy, r: r, from: angleFor(20), to: angleFor(30),
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

            // needle
            let valueAngle = angleFor(min(maxVal, max(minVal, rate)))
            let np = polar(cx: cx, cy: cy, r: r, angle: valueAngle)
            var needle = Path()
            needle.move(to: CGPoint(x: cx, y: cy))
            needle.addLine(to: np)
            context.stroke(needle, with: .color(AppColors.ink0),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
            // center cap
            context.fill(Path(ellipseIn: CGRect(x: cx - 5, y: cy - 5, width: 10, height: 10)),
                         with: .color(AppColors.ink0))
            context.fill(Path(ellipseIn: CGRect(x: cx - 2, y: cy - 2, width: 4, height: 4)),
                         with: .color(AppColors.paper0))
        }
        .frame(width: w, height: h + 10)
        // Round 176: VoiceOver — 다이얼이 의미 있는 값임을 음성으로.
        .accessibilityElement()
        .accessibilityLabel(String(format: NSLocalizedString("a11y.rate_dial", comment: ""),
                                    rate, String(localized: "unit.seconds_per_day")))
    }

    private func angleFor(_ v: Double) -> Double {
        // 0 → −30, 180 → +30 (mockup 과 동일 — 좌측 = 음수)
        (v - minVal) / (maxVal - minVal) * 180
    }
    private func polar(cx: CGFloat, cy: CGFloat, r: CGFloat, angle deg: Double) -> CGPoint {
        // angle 0..180, semi-circle 그리려면 (deg - 180) 적용
        let rad: CGFloat = CGFloat((deg - 180) * .pi / 180)
        return CGPoint(x: cx + r * CoreGraphics.cos(rad), y: cy + r * CoreGraphics.sin(rad))
    }
    private func stroke(_ context: GraphicsContext, cx: CGFloat, cy: CGFloat, r: CGFloat,
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
}

#Preview {
    VStack(spacing: 16) {
        RateDial(rate: 1.8, size: 220)
        RateDial(rate: -18, size: 220)
        RateDial(rate: 28, size: 220)
    }
    .padding().background(AppColors.paper0)
}
