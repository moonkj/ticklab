import SwiftUI

/// 무드 아이콘 — 골드 시계 베젤 + 의미 기반 표정/심볼 벡터. 선택 시에만 애니메이션(시그니처 모션),
/// Reduce Motion 시 전부 정적. 100×100 좌표계로 그린 뒤 size 에 맞게 스케일.
struct MoodIcon: View {
    let mood: Mood
    var isSelected: Bool = false
    /// 애니메이션 ON/OFF. 기본 ON — 표시되는 동안 계속 움직임(HTML 디자인 의도). Reduce Motion 시 자동 정지.
    var animated: Bool = true
    var size: CGFloat = 42
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animate: Bool { animated && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animate)) { tl in
            Canvas { gc, sz in
                let s = min(sz.width, sz.height) / 100.0
                var ctx = gc
                ctx.scaleBy(x: s, y: s)               // 이후 0..100 좌표계
                let t = animate ? tl.date.timeIntervalSinceReferenceDate : 0
                MoodArt.draw(mood, into: &ctx, t: t, selected: isSelected, animate: animate)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 그리기 (100×100 공간)

private enum MoodArt {
    static let gold = rgb(201, 168, 76)
    static let goldGrad = Gradient(colors: [rgb(232, 201, 122), rgb(201, 168, 76), rgb(154, 123, 46)])

    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }
    static func circle(_ x: Double, _ y: Double, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
    /// 상대 q 베지어 한 획(눈/입 곡선).
    static func quad(_ fx: Double, _ fy: Double, _ cx: Double, _ cy: Double, _ ex: Double, _ ey: Double) -> Path {
        var p = Path(); p.move(to: CGPoint(x: fx, y: fy))
        p.addQuadCurve(to: CGPoint(x: ex, y: ey), control: CGPoint(x: cx, y: cy)); return p
    }
    static func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Path {
        var p = Path(); p.move(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x2, y: y2)); return p
    }
    static func stroke(_ ctx: inout GraphicsContext, _ path: Path, _ color: Color, _ w: Double) {
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }
    static func star(_ cx: Double, _ cy: Double, _ rO: Double, _ rI: Double) -> Path {
        var p = Path()
        for i in 0..<10 {
            let r = i.isMultiple(of: 2) ? rO : rI
            let a = -Double.pi / 2 + Double(i) * Double.pi / 5
            let pt = CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath(); return p
    }
    static func gear(_ cx: Double, _ cy: Double, _ rO: Double, _ rI: Double, _ n: Int) -> Path {
        var p = Path(); let st = Double.pi * 2 / Double(n)
        for i in 0..<n {
            let a = Double(i) * st
            let pts: [(Double, Double)] = [(rI, a), (rO, a + st * 0.25), (rO, a + st * 0.5), (rI, a + st * 0.7)]
            for (j, pr) in pts.enumerated() {
                let pt = CGPoint(x: cx + cos(pr.1) * pr.0, y: cy + sin(pr.1) * pr.0)
                (i == 0 && j == 0) ? p.move(to: pt) : p.addLine(to: pt)
            }
        }
        p.closeSubpath(); return p
    }
    /// 0..1 사인 위상.
    static func osc(_ t: Double, _ period: Double, _ phase: Double = 0) -> Double {
        0.5 + 0.5 * sin((t / period + phase) * 2 * Double.pi)
    }

    static func bezel(_ ctx: inout GraphicsContext, t: Double, selected: Bool, animate: Bool) {
        if selected {
            let glow = animate ? (0.25 + 0.35 * osc(t, 1.6)) : 0.4
            ctx.stroke(circle(50, 50, 44), with: .color(gold.opacity(glow)), style: StrokeStyle(lineWidth: 6))
        }
        ctx.stroke(circle(50, 50, 43),
                   with: .linearGradient(goldGrad, startPoint: CGPoint(x: 7, y: 7), endPoint: CGPoint(x: 93, y: 93)),
                   style: StrokeStyle(lineWidth: 3.2))
        ctx.stroke(circle(50, 50, 38.5), with: .color(gold.opacity(0.35)), style: StrokeStyle(lineWidth: 0.8))
    }

    // 하위 컨텍스트에 transform 적용 후 그리는 헬퍼(애니메이션 그룹).
    static func group(_ ctx: GraphicsContext, dx: Double = 0, dy: Double = 0,
                      rotate: Double = 0, scale: Double = 1, anchor: CGPoint = CGPoint(x: 50, y: 50),
                      _ body: (inout GraphicsContext) -> Void) {
        var g = ctx
        g.translateBy(x: anchor.x, y: anchor.y)
        g.translateBy(x: dx, y: dy)
        if scale != 1 { g.scaleBy(x: scale, y: scale) }
        if rotate != 0 { g.rotate(by: .radians(rotate)) }
        g.translateBy(x: -anchor.x, y: -anchor.y)
        body(&g)
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    /// 몸체(베젤 전체) 모션 — 무드별 흔들/끄덕/기울/호흡. 0..100 공간, 중심(50,50) 기준.
    static func bodyTransform(_ mood: Mood, _ t: Double) -> (dx: CGFloat, dy: CGFloat, scale: CGFloat, rot: Double) {
        func bosc(_ p: Double) -> Double { (1 - cos(t / p * 2 * .pi)) / 2 }   // 0→1→0 (50%에서 peak)
        func sn(_ p: Double) -> Double { sin(t / p * 2 * .pi) }               // -1↔1
        let d = Double.pi / 180
        switch mood {
        case .happy:        return (0, CGFloat(-3 * bosc(2.6)), 1 + 0.07 * bosc(2.6), 0)
        case .excited:      return (0, CGFloat(-4 * bosc(1.3)), 1, 9 * d * sn(0.65))
        case .proud:        return (0, 0, 1 + 0.12 * bosc(2.4), 0)
        case .awe:          return (0, CGFloat(-3 * bosc(2.2)), 1 + 0.13 * bosc(2.2), -3 * d * bosc(2.2))
        case .accomplished: return (0, CGFloat(3 - 8 * bosc(2.0)), 1, 0)
        case .love:         return (0, 0, 1 + 0.14 * bosc(0.75), 0)
        case .relief:       return (0, CGFloat(-5 + 8 * bosc(2.8)), 1, 0)
        case .calm:         return (0, 0, 0.98 + 0.11 * bosc(3.4), 0)
        case .neutral:      return (0, 0, 1, 5 * d * sn(3.8))
        case .curious:      return (0, CGFloat(-1 * bosc(2.8)), 1, 13 * d * sn(2.8))
        case .focused:      return (0, 0, 1.08 - 0.20 * bosc(2.0), 0)
        case .thoughtful:   return (0, CGFloat(-3 * bosc(3.2)), 1, 10 * d * sn(3.2))
        case .nostalgic:    return (0, 0, 1, 11 * d * sn(3.4))
        case .concerned:    return (CGFloat(3.5 * sn(0.25)), 0, 1, 5 * d * sn(0.25))
        case .disappointed: return (0, CGFloat(6 * bosc(2.8)), 1, -2 * d * bosc(2.8))
        case .surprised:    return (0, CGFloat(-5 * bosc(2.0)), 1 + 0.18 * bosc(2.0), 0)
        case .confused:     return (0, 0, 1, 14 * d * sn(2.6))
        case .longing:      return (CGFloat(1 - 4 * bosc(3.0)), 0, 1, (2 - 15 * bosc(3.0)) * d)
        case .tired:        return (0, CGFloat(6 * bosc(3.0)), 1, 7 * d * bosc(3.0))
        }
    }

    static func draw(_ mood: Mood, into ctx: inout GraphicsContext, t: Double, selected: Bool, animate: Bool) {
        // 몸체 모션 — 전체(베젤+얼굴)에 무드별 변형 적용. 얼굴 세부 모션은 그 위에 중첩.
        if animate {
            let b = bodyTransform(mood, t)
            ctx.translateBy(x: 50, y: 50)
            ctx.translateBy(x: b.dx, y: b.dy)
            if b.scale != 1 { ctx.scaleBy(x: b.scale, y: b.scale) }
            if b.rot != 0 { ctx.rotate(by: .radians(b.rot)) }
            ctx.translateBy(x: -50, y: -50)
        }
        bezel(&ctx, t: t, selected: selected, animate: animate)
        switch mood {
        // ===== 긍정 =====
        case .happy: // satisfied — 흐뭇한 미소, 위아래 bob
            let c = rgb(216, 154, 62)
            group(ctx, dy: animate ? -5 * osc(t, 2.2) : 0) { g in
                stroke(&g, quad(37, 44, 41, 39, 45, 44), c, 3)
                stroke(&g, quad(55, 44, 59, 39, 63, 44), c, 3)
                stroke(&g, quad(37, 56, 50, 69, 63, 56), c, 3.4)
            }
        case .excited: // 설렘 — 바운스 + 위 스파크
            let c = rgb(232, 150, 110); let sp = rgb(240, 176, 112)
            let riseT = (t.truncatingRemainder(dividingBy: 1.4)) / 1.4
            group(ctx, dy: animate ? (riseT < 0.45 ? -7 * (riseT / 0.45) : -7 * (1 - (riseT - 0.45) / 0.55)) : 0) {
                stroke(&$0, quad(37, 46, 41, 40, 45, 46), c, 3)
                stroke(&$0, quad(55, 46, 59, 40, 63, 46), c, 3)
                stroke(&$0, quad(35, 54, 50, 71, 65, 54), c, 3.4)
            }
            let sparkY = animate ? -6 * riseT : 0
            let sparkA = animate ? (riseT < 0.45 ? riseT / 0.45 : max(0, 1 - (riseT - 0.45) / 0.55)) : 0.8
            var g = ctx; g.translateBy(x: 0, y: sparkY)
            for x in [31.0, 50, 69] {
                stroke(&g, line(x, x == 50 ? 27 : 33, x, (x == 50 ? 27 : 33) - 5), sp.opacity(sparkA), 2)
            }
        case .proud: // 자랑 — 별 트윙클(회전+확대)
            let sc = animate ? 1 + 0.30 * osc(t, 1.8) : 1
            let rot = animate ? 1.2 * sin(t / 2 * 2 * .pi) : 0
            group(ctx, rotate: rot, scale: sc, anchor: CGPoint(x: 50, y: 52)) {
                $0.fill(star(50, 50, 18, 7.5), with: .color(rgb(232, 194, 90)))
            }
            ctx.fill(star(68, 43, 5, 2.2), with: .color(rgb(240, 216, 138).opacity(animate ? osc(t, 2.4) : 0.7)))
        case .awe: // 감탄 — 광선 펄스 + 눈 확대
            let c = rgb(240, 184, 76)
            let rs = animate ? 0.82 + 0.34 * osc(t, 1.8) : 1
            group(ctx, scale: rs) { g in
                let rays: [(Double, Double, Double, Double)] = [(50,20,50,15),(71,29,74,25),(29,29,26,25),(76,50,81,50),(24,50,19,50)]
                for (x1, y1, x2, y2) in rays {
                    stroke(&g, line(x1, y1, x2, y2), c.opacity(animate ? (0.3 + 0.55 * osc(t, 2.6)) : 0.7), 2)
                }
            }
            let es = animate ? 1 + 0.28 * osc(t, 1.8) : 1
            group(ctx, scale: es, anchor: CGPoint(x: 50, y: 47)) {
                $0.fill(circle(41, 47, 4.2), with: .color(c))
                $0.fill(circle(59, 47, 4.2), with: .color(c))
            }
            ctx.stroke(circle(50, 61, 4.2), with: .color(c), style: StrokeStyle(lineWidth: 2.6))
        case .accomplished: // 뿌듯 — 체크 팝
            let sc = animate ? 1 + 0.30 * osc(t, 1.8) : 1
            group(ctx, scale: sc, anchor: CGPoint(x: 50, y: 52)) {
                var p = Path(); p.move(to: CGPoint(x: 36, y: 50)); p.addLine(to: CGPoint(x: 46, y: 60)); p.addLine(to: CGPoint(x: 65, y: 39))
                $0.stroke(p, with: .color(gold), style: StrokeStyle(lineWidth: 4.4, lineCap: .round, lineJoin: .round))
            }
            ctx.fill(star(66, 37.5, 5.5, 2.3), with: .color(rgb(232, 201, 122).opacity(0.8)))
        case .nostalgic: // 향수 — 시계 바늘 역회전
            let c = rgb(168, 124, 78)
            ctx.fill(circle(50, 50, 33), with: .color(c.opacity(0.07)))
            let dots: [(Double, Double)] = [(50,22),(78,50),(50,78),(22,50)]
            for (x, y) in dots { ctx.fill(circle(x, y, 1.6), with: .color(c)) }
            group(ctx, rotate: animate ? -(t.truncatingRemainder(dividingBy: 6) / 6) * 2 * .pi : 0) {
                stroke(&$0, line(50, 50, 50, 33), c, 3)
                stroke(&$0, line(50, 50, 63, 50), c, 2.4)
            }
            ctx.fill(circle(50, 50, 2.6), with: .color(rgb(154, 123, 46)))
        // ===== 긍정(추가) =====
        case .love: // 애정 — 하트비트
            let beat = t.truncatingRemainder(dividingBy: 1.4) / 1.4
            let sc = animate ? (beat < 0.15 ? 1 + beat / 0.15 * 0.30 : beat < 0.3 ? 1.30 - (beat - 0.15) / 0.15 * 0.30 : beat < 0.45 ? 1 + (beat - 0.3) / 0.15 * 0.18 : beat < 0.6 ? 1.18 - (beat - 0.45) / 0.15 * 0.18 : 1) : 1
            group(ctx, scale: sc) {
                var p = Path()
                p.move(to: CGPoint(x: 50, y: 64))
                p.addCurve(to: CGPoint(x: 41, y: 37), control1: CGPoint(x: 35, y: 53), control2: CGPoint(x: 31, y: 41))
                p.addCurve(to: CGPoint(x: 50, y: 41.5), control1: CGPoint(x: 47, y: 34.5), control2: CGPoint(x: 50, y: 39))
                p.addCurve(to: CGPoint(x: 59, y: 37), control1: CGPoint(x: 50, y: 39), control2: CGPoint(x: 53, y: 34.5))
                p.addCurve(to: CGPoint(x: 50, y: 64), control1: CGPoint(x: 69, y: 41), control2: CGPoint(x: 65, y: 53))
                $0.fill(p, with: .color(rgb(217, 138, 138)))
            }
        case .relief: // 안도 — ∪ 눈, 아래로 sink
            let c = rgb(127, 176, 152)
            group(ctx, dy: animate ? 3.5 * osc(t, 2.6) : 0) {
                stroke(&$0, quad(37, 47, 41, 51, 45, 47), c, 3)
                stroke(&$0, quad(55, 47, 59, 51, 63, 47), c, 3)
                stroke(&$0, quad(40, 57, 50, 65, 60, 57), c, 3.2)
            }
        case .calm: // 평온 — 호흡(scale)
            let c = rgb(122, 160, 176)
            group(ctx, scale: animate ? 1 + 0.13 * osc(t, 2.8) : 1) {
                stroke(&$0, line(37, 47, 45, 47), c, 3)
                stroke(&$0, line(55, 47, 63, 47), c, 3)
                stroke(&$0, quad(42, 58, 50, 63, 58, 58), c, 3)
            }
        // ===== 사색·중립 =====
        case .neutral: // 평범 — 깜빡임
            let c = rgb(154, 160, 168)
            let blink = animate ? (osc(t, 3.2) > 0.9 ? 0.12 : 1) : 1
            group(ctx, scale: 1, anchor: CGPoint(x: 50, y: 46)) { g in
                var gg = g; gg.translateBy(x: 50, y: 46); gg.scaleBy(x: 1, y: blink); gg.translateBy(x: -50, y: -46)
                gg.fill(circle(41, 46, 3), with: .color(c))
                gg.fill(circle(59, 46, 3), with: .color(c))
            }
            stroke(&ctx, line(40, 60, 60, 60), c, 3.2)
        case .curious: // 호기심 — 돋보기 기울임 + 반짝
            let c = rgb(100, 112, 174)
            group(ctx, rotate: animate ? 0.24 * sin(t / 2.6 * 2 * .pi) : 0, anchor: CGPoint(x: 45, y: 45)) {
                $0.fill(circle(45, 45, 13), with: .color(c.opacity(0.08)))
                $0.stroke(circle(45, 45, 13), with: .color(c), style: StrokeStyle(lineWidth: 3.2))
                stroke(&$0, line(55, 55, 66, 66), rgb(154, 123, 46), 4)
                let sh = animate ? osc(t, 3.5) : 0.8
                stroke(&$0, line(41 + sh * 2, 42, 46 + sh * 2, 42), Color.white.opacity(0.8 * sh), 2.4)
            }
        case .focused: // 집중 — 동심원 수축 펄스
            let c = rgb(80, 96, 160)
            let r1 = animate ? 1 - 0.34 * osc(t, 1.8) : 1
            group(ctx, scale: r1) { $0.stroke(circle(50, 50, 16), with: .color(c), style: StrokeStyle(lineWidth: 2.4)) }
            group(ctx, scale: animate ? 1 - 0.34 * osc(t, 1.8, 0.2) : 1) { $0.stroke(circle(50, 50, 9), with: .color(c), style: StrokeStyle(lineWidth: 2.4)) }
            ctx.fill(circle(50, 50, 3), with: .color(c))
        case .thoughtful: // 사색 — 톱니 회전 + 생각 점
            let c = rgb(138, 138, 176)
            group(ctx, rotate: animate ? (t.truncatingRemainder(dividingBy: 4.5) / 4.5) * 2 * .pi : 0, anchor: CGPoint(x: 50, y: 48)) {
                $0.fill(gear(50, 48, 15, 11, 8), with: .color(c.opacity(0.9)))
            }
            ctx.stroke(circle(50, 48, 4.5), with: .color(c), style: StrokeStyle(lineWidth: 2))
            ctx.fill(circle(44, 66, 2), with: .color(c.opacity(0.7)))
            ctx.fill(circle(52, 68, 1.4), with: .color(c.opacity(0.5)))
        // ===== 복잡·부정 =====
        case .concerned: // 우려 — 떨림 + 찌푸린 눈썹
            let c = rgb(189, 154, 94)
            group(ctx, dx: animate ? 2.2 * sin(t / 0.4 * 2 * .pi) : 0) { g in
                let bf = animate ? -2.5 * osc(t, 2) : 0
                stroke(&g, line(36, 41 + bf, 45, 44 + bf), c, 3)
                stroke(&g, line(64, 41 + bf, 55, 44 + bf), c, 3)
                g.fill(circle(41, 50, 2.8), with: .color(c))
                g.fill(circle(59, 50, 2.8), with: .color(c))
                stroke(&g, quad(40, 63, 50, 55, 60, 63), c, 3.2)
            }
        case .disappointed: // 실망 — 처짐
            let c = rgb(138, 149, 168)
            group(ctx, dy: animate ? 3.5 * osc(t, 2.4) : 0) {
                stroke(&$0, quad(37, 44, 41, 49, 45, 46), c, 3)
                stroke(&$0, quad(55, 46, 59, 43, 63, 48), c, 3)
                stroke(&$0, quad(40, 63, 50, 56, 60, 63), c, 3.2)
            }
        case .surprised: // 놀람 — 팝
            let c = rgb(232, 184, 76)
            group(ctx, scale: animate ? 1 + 0.30 * osc(t, 1.6) : 1) {
                $0.fill(circle(41, 46, 4.2), with: .color(c))
                $0.fill(circle(59, 46, 4.2), with: .color(c))
                $0.stroke(Path(ellipseIn: CGRect(x: 45.8, y: 55.6, width: 8.4, height: 10.8)), with: .color(c), style: StrokeStyle(lineWidth: 2.6))
            }
        case .confused: // 혼란 — 물음표 기울임
            let c = rgb(160, 138, 176)
            group(ctx, rotate: animate ? 0.22 * sin(t / 2.4 * 2 * .pi) : 0, anchor: CGPoint(x: 50, y: 48)) {
                var p = Path()
                p.move(to: CGPoint(x: 43, y: 43))
                p.addQuadCurve(to: CGPoint(x: 51, y: 34), control: CGPoint(x: 43, y: 34))
                p.addQuadCurve(to: CGPoint(x: 52, y: 50.5), control: CGPoint(x: 60, y: 42))
                p.addLine(to: CGPoint(x: 52, y: 54.5))
                $0.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                $0.fill(circle(52, 64, 2.4), with: .color(c))
            }
        case .longing: // 그리움 — 먼 별 드리프트
            let c = rgb(154, 138, 160)
            ctx.fill(circle(44, 47, 3), with: .color(c))
            ctx.fill(circle(58, 47, 3), with: .color(c))
            stroke(&ctx, quad(42, 59, 50, 63, 58, 58), c, 3)
            let dr = animate ? t.truncatingRemainder(dividingBy: 2.6) / 2.6 : 0.3
            var g = ctx; g.translateBy(x: dr * 12, y: -dr * 9)
            g.fill(star(64, 38, 5.5, 2.4), with: .color(rgb(176, 160, 188).opacity(animate ? max(0, 1 - dr) : 0.6)))
        case .tired: // 지침 — 무거운 눈 + zzz
            let c = rgb(154, 154, 160)
            let hb = animate ? (osc(t, 2.8) > 0.82 ? 0.18 : 1) : 1
            group(ctx, scale: 1, anchor: CGPoint(x: 50, y: 48)) { g in
                var gg = g; gg.translateBy(x: 50, y: 48); gg.scaleBy(x: 1, y: hb); gg.translateBy(x: -50, y: -48)
                stroke(&gg, quad(37, 48, 41, 51, 45, 48), c, 3)
                stroke(&gg, quad(55, 48, 59, 51, 63, 48), c, 3)
            }
            stroke(&ctx, quad(40, 61, 50, 65, 60, 61), c, 3)
            let zT = animate ? t.truncatingRemainder(dividingBy: 3) / 3 : 0.4
            var g = ctx; g.translateBy(x: zT * 2, y: 2 - zT * 7)
            g.fill(star(0, 0, 0, 0), with: .color(.clear)) // noop keep g used
            let za = animate ? (zT < 0.5 ? zT * 2 : max(0, 1 - (zT - 0.5) * 2)) : 0.7
            g.draw(Text("z").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(c.opacity(za)), at: CGPoint(x: 64, y: 33))
            g.draw(Text("z").font(.system(size: 7, weight: .semibold, design: .monospaced)).foregroundColor(c.opacity(za)), at: CGPoint(x: 70, y: 27))
        }
    }
}

#Preview {
    ScrollView {
        let cols = Array(repeating: GridItem(.flexible()), count: 5)
        LazyVGrid(columns: cols, spacing: 14) {
            ForEach(Mood.allCases, id: \.self) { m in
                VStack(spacing: 4) {
                    MoodIcon(mood: m, isSelected: true, size: 48)
                    Text(m.rawValue).font(.system(size: 8))
                }
            }
        }
        .padding()
    }
    .background(AppColors.paper0)
}
