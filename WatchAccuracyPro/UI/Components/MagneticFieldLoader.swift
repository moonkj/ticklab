import SwiftUI

/// 자기장 측정 로딩 — 회전하는 **말굽자석**(N 빨강 / S 파랑) + 양극 사이 자기장 펄스.
/// 나침반/밸런스휠 아님. 다크/라이트 배경 모두 가독. Reduce Motion 시 정적.
struct MagneticFieldLoader: View {
    var size: CGFloat = 26
    /// 회전 여부 — 측정 중일 때만 true. false 면 정지(자석 똑바로).
    var animating: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var move: Bool { animating && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !move)) { tl in
            Canvas { gc, sz in
                let t = move ? tl.date.timeIntervalSinceReferenceDate : 0
                draw(gc, sz, t)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
        var p = Path(); p.move(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x2, y: y2)); return p
    }

    private func draw(_ gc: GraphicsContext, _ sz: CGSize, _ t: Double) {
        let s = min(sz.width, sz.height)
        let cx = sz.width / 2, cy = sz.height / 2
        let R = s / 2
        let north = Color(red: 0.95, green: 0.27, blue: 0.25)   // N극 빨강
        let south = Color(red: 0.36, green: 0.58, blue: 1.0)    // S극 파랑(밝게)
        let body = AppColors.accent                              // 자석 몸체 골드 — 다크/라이트 모두 또렷
        let lw = R * 0.30                                         // 자석 두께

        var g = gc
        g.translateBy(x: cx, y: cy)
        g.rotate(by: .radians(t * (2 * .pi / 2.2)))              // 천천히 회전(로딩)
        g.translateBy(x: -cx, y: -cy)

        let legX = R * 0.40                                       // 다리 좌우 간격
        let topY = cy - R * 0.42                                  // 양극(위) y
        let botY = cy + R * 0.30                                  // 곡선 시작 y
        let capLen = R * 0.30                                     // 극 색 캡 길이

        // 몸체 U(말굽) — 양다리 + 바닥 곡선.
        var u = Path()
        u.move(to: CGPoint(x: cx - legX, y: topY + capLen))
        u.addLine(to: CGPoint(x: cx - legX, y: botY))
        u.addQuadCurve(to: CGPoint(x: cx + legX, y: botY),
                       control: CGPoint(x: cx, y: botY + legX * 1.7))
        u.addLine(to: CGPoint(x: cx + legX, y: topY + capLen))
        g.stroke(u, with: .color(body), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))

        // 양극 색 캡 — 좌 N(빨강) / 우 S(파랑).
        g.stroke(line(cx - legX, topY, cx - legX, topY + capLen), with: .color(north),
                 style: StrokeStyle(lineWidth: lw, lineCap: .round))
        g.stroke(line(cx + legX, topY, cx + legX, topY + capLen), with: .color(south),
                 style: StrokeStyle(lineWidth: lw, lineCap: .round))

        // 양극 사이 자기장 펄스(위로 퍼지는 호) — 큰 사이즈에서만.
        if s >= 40 {
            for k in 0..<2 {
                let phase = (t * 1.1 + Double(k) / 2.0).truncatingRemainder(dividingBy: 1.0)
                let lift = R * (0.0 + 0.42 * CGFloat(phase))
                let op = (1.0 - phase) * 0.7
                var arc = Path()
                let ay = topY - lift
                arc.move(to: CGPoint(x: cx - legX, y: ay))
                arc.addQuadCurve(to: CGPoint(x: cx + legX, y: ay),
                                 control: CGPoint(x: cx, y: ay - R * 0.30))
                g.stroke(arc, with: .color(south.opacity(op)), style: StrokeStyle(lineWidth: max(1, s * 0.035)))
            }
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        MagneticFieldLoader(size: 24)
        MagneticFieldLoader(size: 64)
    }
    .padding(40)
    .background(AppColors.ink0)
}
