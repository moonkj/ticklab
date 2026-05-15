import SwiftUI

/// Sparkline — 측정 이력 mini chart. zero baseline + dot at last point.
struct Sparkline: View {
    let values: [Double]
    var width: CGFloat = 80
    var height: CGFloat = 22

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2 else {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: size.height / 2))
                p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(p, with: .color(AppColors.rule),
                               style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                return
            }
            let minV = min((values.min() ?? -1), -1)
            let maxV = max((values.max() ?? 1), 1)
            let range = max(maxV - minV, 0.001)
            let stepX = size.width / CGFloat(values.count - 1)
            let mapY: (Double) -> CGFloat = { v in
                size.height - ((CGFloat(v - minV) / CGFloat(range)) * (size.height - 4)) - 2
            }
            // baseline (0)
            var baseline = Path()
            let yZero = mapY(0)
            baseline.move(to: CGPoint(x: 0, y: yZero))
            baseline.addLine(to: CGPoint(x: size.width, y: yZero))
            context.stroke(baseline, with: .color(AppColors.rule),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            // line
            var line = Path()
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: CGFloat(i) * stepX, y: mapY(v))
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            context.stroke(line, with: .color(AppColors.ink1),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            // last dot accent
            if let last = values.last {
                let p = CGPoint(x: CGFloat(values.count - 1) * stepX, y: mapY(last))
                context.fill(Path(ellipseIn: CGRect(x: p.x - 2.2, y: p.y - 2.2, width: 4.4, height: 4.4)),
                             with: .color(AppColors.accent))
            }
        }
        .frame(width: width, height: height)
    }
}

#Preview {
    VStack(spacing: 8) {
        Sparkline(values: [-2, 1, 3, -1, 2, 4, 1])
        Sparkline(values: [], width: 100)
    }
    .padding().background(AppColors.paper0)
}
