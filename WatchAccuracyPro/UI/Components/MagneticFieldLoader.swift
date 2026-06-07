import SwiftUI

/// 자기장 측정 로딩 인디케이터 — 회전하는 나침반 바늘(N 빨강/S 스틸) + 바깥으로 퍼지는 자기장 펄스 링
/// + 다이폴 필드 라인(큰 사이즈일 때). 다크/라이트 배경 모두 가독. Reduce Motion 시 정적.
struct MagneticFieldLoader: View {
    var size: CGFloat = 64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { tl in
            Canvas { gc, sz in
                let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                draw(gc, sz, t)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    private func draw(_ gc: GraphicsContext, _ sz: CGSize, _ t: Double) {
        let s = min(sz.width, sz.height)
        let cx = sz.width / 2, cy = sz.height / 2
        let R = s / 2
        let field = AppColors.primary          // 인디고 — 자기장
        let north = AppColors.danger           // 빨강 — N극
        let south = Color(white: 0.62)         // 스틸 — S극
        let gold = AppColors.accent

        // 바깥으로 퍼지는 자기장 펄스 링(레이더식 = 장 감지).
        for k in 0..<3 {
            let phase = (t * 0.7 + Double(k) / 3.0).truncatingRemainder(dividingBy: 1.0)
            let rr = R * (0.30 + 0.70 * CGFloat(phase))
            let op = (1.0 - phase) * 0.45
            gc.stroke(circle(cx, cy, rr), with: .color(field.opacity(op)),
                      lineWidth: max(1, s * 0.03))
        }

        // 다이폴 필드 라인 — 큰 사이즈에서만(좌우 대칭 루프, 은은).
        if s >= 44 {
            for sgn in [-1.0, 1.0] as [CGFloat] {
                var p = Path()
                p.move(to: CGPoint(x: cx, y: cy - R * 0.62))
                p.addCurve(to: CGPoint(x: cx, y: cy + R * 0.62),
                           control1: CGPoint(x: cx + sgn * R * 0.95, y: cy - R * 0.30),
                           control2: CGPoint(x: cx + sgn * R * 0.95, y: cy + R * 0.30))
                gc.stroke(p, with: .color(field.opacity(0.22)), lineWidth: max(1, s * 0.022))
            }
        }

        // 회전하는 나침반 바늘 — 천천히 스캔(2.6s/회).
        var g = gc
        g.translateBy(x: cx, y: cy)
        g.rotate(by: .radians(t * (2 * .pi / 2.6)))
        let len = R * 0.60, w = R * 0.16
        var pn = Path()
        pn.move(to: CGPoint(x: 0, y: -len)); pn.addLine(to: CGPoint(x: -w, y: 0)); pn.addLine(to: CGPoint(x: w, y: 0)); pn.closeSubpath()
        g.fill(pn, with: .color(north))
        var ps = Path()
        ps.move(to: CGPoint(x: 0, y: len)); ps.addLine(to: CGPoint(x: -w, y: 0)); ps.addLine(to: CGPoint(x: w, y: 0)); ps.closeSubpath()
        g.fill(ps, with: .color(south))
        g.fill(circle(0, 0, w * 0.6), with: .color(gold))
    }
}

#Preview {
    HStack(spacing: 24) {
        MagneticFieldLoader(size: 22)
        MagneticFieldLoader(size: 64)
    }
    .padding(40)
    .background(AppColors.ink0)
}
