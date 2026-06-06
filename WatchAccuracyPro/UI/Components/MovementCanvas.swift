import SwiftUI

/// 측정 데이터로 **실제 구동**되는 무브먼트 모션 — 밸런스휠(SHM) + 이스케이프먼트 + 팔레트포크 + 헤어스프링.
///
/// 경쟁 앱은 장식 애니메이션이지만 우리는 **실측값으로 움직인다**:
/// - `bph` → 진동 주파수(밸런스 SHM) + 이스케이프먼트 스텝 속도.
/// - `amplitudeDegrees` → 밸런스 진폭. **DSP 가 이미 신뢰도 게이팅**해서 신뢰 낮은 캘리버는 nil
///   (Hard Rule #9). nil 이면 nominal 대표 스윙(실측 주장 X) → 규칙 자동 충족.
///
/// 사용처: 결과·상세 화면 전용. **측정 라이브 화면엔 절대 미사용**(Hard Rule #4 16ms).
/// Reduce Motion 시 정적 단면(타임라인 정지). 화면당 1개 권장.
struct MovementCanvas: View {
    var bph: Int = 28_800
    /// 실측 진폭(신뢰 캘리버만 non-nil). nil 이면 nominal 대표 스윙.
    var amplitudeDegrees: Double? = nil
    var height: CGFloat = 190

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var nominalAmplitude: Double { 285 }                       // 건강한 무브먼트 대표 스윙
    private var swingDegrees: Double { min(320, max(140, amplitudeDegrees ?? nominalAmplitude)) }
    private var beatHz: Double { Double(max(3600, bph)) / 3600.0 }     // beats/sec
    private var oscHz: Double { beatHz / 2.0 }                         // full oscillations/sec

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { ctx in
            Canvas { gc, size in
                let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
                draw(gc, size: size, t: t)
            }
        }
        .frame(height: height)
        .background(
            RadialGradient(colors: [Color(red: 0.11, green: 0.12, blue: 0.20),
                                    Color(red: 0.06, green: 0.07, blue: 0.12)],
                           center: .init(x: 0.4, y: 0.45), startRadius: 8, endRadius: 240)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.accent.opacity(0.25), lineWidth: 1))
        .accessibilityHidden(true)   // 시각 전용 — 수치는 메트릭이 음성 안내
    }

    private func draw(_ gc: GraphicsContext, size: CGSize, t: Double) {
        let W = size.width, H = size.height
        let s = W / 420.0
        let cx = W * 0.36, cy = H * 0.5
        let rb = 78 * s
        let swingRad = swingDegrees * .pi / 180
        let theta = reduceMotion ? swingRad * 0.55 : swingRad * cos(2 * .pi * oscHz * t)
        let gold = AppColors.accent, goldL = AppColors.accentLight, goldD = AppColors.accentDark

        // ── 헤어스프링 (아르키메데스 나선, theta 로 미세 호흡) ──
        var hs = gc
        hs.translateBy(x: cx, y: cy)
        hs.rotate(by: .radians(theta * 0.15))
        var spiral = Path()
        let turns = 4.0, b = (rb * 0.62) / (turns * .pi * 2)
        var a = 0.0
        while a < turns * .pi * 2 {
            let r = 6 * s + b * a
            let p = CGPoint(x: CGFloat(cos(a)) * r, y: CGFloat(sin(a)) * r)
            if a == 0 { spiral.move(to: p) } else { spiral.addLine(to: p) }
            a += 0.16
        }
        hs.stroke(spiral, with: .color(gold.opacity(0.5)), lineWidth: 1.1 * s)

        // ── 이스케이프먼트 휠 (15 톱니, beat 마다 1스텝) ──
        let ex = cx + rb + 46 * s, ey = cy - 30 * s, re = 30 * s
        let escapeAngle = reduceMotion ? 0 : floor(beatHz * t) * (.pi * 2 / 15)
        let ew = gearPath(cx: ex, cy: ey, rOuter: re, rInner: re * 0.7, teeth: 15, rot: escapeAngle)
        gc.fill(ew, with: .color(Color(red: 0.15, green: 0.16, blue: 0.27)))
        gc.stroke(ew, with: .color(goldD), lineWidth: 1.2 * s)
        gc.fill(circle(ex, ey, 5 * s), with: .color(gold))

        // ── 팔레트 포크 (밸런스 위상에 맞춰 진동) ──
        let fpx = ex - 4 * s, fpy = ey + 40 * s
        let forkSwing = reduceMotion ? 0.2 : 0.28 * (cos(2 * .pi * oscHz * t) >= 0 ? 1.0 : -1.0)
        var fk = gc
        fk.translateBy(x: fpx, y: fpy)
        fk.rotate(by: .radians(forkSwing))
        let cap = StrokeStyle(lineWidth: 3.2 * s, lineCap: .round)
        fk.stroke(line(0, -22 * s, 0, 16 * s), with: .color(goldL), style: cap)
        fk.stroke(line(0, -22 * s, -9 * s, -30 * s), with: .color(goldL), style: cap)
        fk.stroke(line(0, -22 * s, 9 * s, -30 * s), with: .color(goldL), style: cap)
        fk.fill(circle(-9 * s, -30 * s, 2.6 * s), with: .color(AppColors.danger))
        fk.fill(circle(9 * s, -30 * s, 2.6 * s), with: .color(AppColors.danger))
        fk.fill(circle(0, 16 * s, 4 * s), with: .color(gold))

        // ── 밸런스 휠 (SHM 진동) ──
        var bw = gc
        bw.translateBy(x: cx, y: cy)
        bw.rotate(by: .radians(theta))
        let rim = circle(0, 0, rb)
        bw.stroke(rim, with: .linearGradient(Gradient(colors: [goldL, goldD, goldL]),
                                             startPoint: CGPoint(x: -rb, y: -rb),
                                             endPoint: CGPoint(x: rb, y: rb)), lineWidth: 6 * s)
        bw.stroke(circle(0, 0, rb - 9 * s), with: .color(gold.opacity(0.35)), lineWidth: 1.5 * s)
        for k in 0..<3 {
            var sp = bw
            sp.rotate(by: .radians(Double(k) * .pi * 2 / 3))
            sp.stroke(line(0, 0, 0, -(rb - 3 * s)), with: .color(goldD), lineWidth: 4 * s)
            sp.fill(circle(0, -(rb - 2 * s), 3 * s), with: .color(gold))
        }
        bw.fill(circle(0, 0, 7 * s), with: .color(gold))
        bw.fill(circle(0, 0, 3 * s), with: .color(Color(red: 0.09, green: 0.10, blue: 0.17)))
    }

    // MARK: - Path helpers
    private func gearPath(cx: CGFloat, cy: CGFloat, rOuter: CGFloat, rInner: CGFloat, teeth: Int, rot: Double) -> Path {
        var p = Path()
        let steps = teeth * 2
        for i in 0...steps {
            let ang = rot + Double(i) / Double(steps) * .pi * 2
            let r = (i % 2 == 0) ? rOuter : rInner
            let pt = CGPoint(x: cx + CGFloat(cos(ang)) * r, y: cy + CGFloat(sin(ang)) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
    private func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
    private func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
        var p = Path(); p.move(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x2, y: y2)); return p
    }
}

/// 밸런스휠 단독 — 프레임 중앙에서 SHM 진동(헤어스프링 포함). 배경 투명(다른 요소 위에 얹기 좋게).
/// 결과화면 RateDial 중앙(인장 자리)에 인장 크기로 넣어 그 자리에서 돌게 하는 용도.
/// BPH → 진동 주파수, amplitudeDegrees(신뢰 시 non-nil) → 진폭. Reduce Motion 정적.
struct BalanceWheelLive: View {
    var bph: Int = 28_800
    var amplitudeDegrees: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var swingDeg: Double { min(320, max(140, amplitudeDegrees ?? 285)) }
    private var oscHz: Double { Double(max(3600, bph)) / 3600.0 / 2.0 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { ctx in
            Canvas { gc, size in
                let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
                draw(gc, size: size, t: t)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ gc: GraphicsContext, size: CGSize, t: Double) {
        let cx = size.width / 2, cy = size.height / 2
        let rb = min(size.width, size.height) / 2 * 0.86
        let s = rb / 78
        let swingRad = swingDeg * .pi / 180
        let theta = reduceMotion ? swingRad * 0.5 : swingRad * cos(2 * .pi * oscHz * t)
        let gold = AppColors.accent, goldL = AppColors.accentLight, goldD = AppColors.accentDark
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
            var p = Path(); p.move(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x2, y: y2)); return p
        }
        // 헤어스프링
        var hs = gc
        hs.translateBy(x: cx, y: cy); hs.rotate(by: .radians(theta * 0.12))
        var spiral = Path()
        let turns = 3.5, b = (rb * 0.6) / (turns * .pi * 2)
        var a = 0.0
        while a < turns * .pi * 2 {
            let r = 5 * s + b * a
            let p = CGPoint(x: CGFloat(cos(a)) * r, y: CGFloat(sin(a)) * r)
            if a == 0 { spiral.move(to: p) } else { spiral.addLine(to: p) }
            a += 0.18
        }
        hs.stroke(spiral, with: .color(gold.opacity(0.4)), lineWidth: 1.0 * s)
        // 밸런스휠
        var bw = gc
        bw.translateBy(x: cx, y: cy); bw.rotate(by: .radians(theta))
        bw.stroke(circle(0, 0, rb), with: .linearGradient(Gradient(colors: [goldL, goldD, goldL]),
                                                          startPoint: CGPoint(x: -rb, y: -rb),
                                                          endPoint: CGPoint(x: rb, y: rb)), lineWidth: 6 * s)
        bw.stroke(circle(0, 0, rb - 9 * s), with: .color(gold.opacity(0.35)), lineWidth: 1.4 * s)
        for k in 0..<3 {
            var sp = bw
            sp.rotate(by: .radians(Double(k) * .pi * 2 / 3))
            sp.stroke(line(0, 0, 0, -(rb - 3 * s)), with: .color(goldD), lineWidth: 4 * s)
            sp.fill(circle(0, -(rb - 2 * s), 3 * s), with: .color(gold))
        }
        bw.fill(circle(0, 0, 7 * s), with: .color(gold))
        bw.fill(circle(0, 0, 3 * s), with: .color(AppColors.paper0))
    }
}

/// 톱니바퀴 Shape — teeth 개 클럽 톱니.
struct GearShape: Shape {
    var teeth: Int = 12
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rO = min(rect.width, rect.height) / 2
        let rI = rO * 0.74
        var p = Path()
        let stp = Double.pi * 2 / Double(teeth)
        func pt(_ r: CGFloat, _ a: Double) -> CGPoint { CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r) }
        for i in 0..<teeth {
            let a = Double(i) * stp
            if i == 0 { p.move(to: pt(rI, a)) } else { p.addLine(to: pt(rI, a)) }
            p.addLine(to: pt(rO, a + stp * 0.22))
            p.addLine(to: pt(rO, a + stp * 0.5))
            p.addLine(to: pt(rI, a + stp * 0.72))
        }
        p.closeSubpath()
        return p
    }
}

/// 앰비언트 틱톡 기어 — 1초에 한 톱니씩 스텝(Timer + easeOut, 60fps 아님 → 배터리 안전).
/// "항상 살아있는 무브먼트" 브랜드 시그니처. Reduce Motion 정적. 측정 라이브 화면엔 미사용.
struct TickingGearView: View {
    var teeth: Int = 12
    var size: CGFloat = 18
    var color: Color = AppColors.accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            GearShape(teeth: teeth)
                .fill(color.opacity(0.85))
                .rotationEffect(.degrees(Double(step) * 360.0 / Double(teeth)))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: step)
            Circle().fill(AppColors.paper0).frame(width: size * 0.26, height: size * 0.26)
        }
        .frame(width: size, height: size)
        .onReceive(timer) { _ in if !reduceMotion { step += 1 } }
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 16) {
        MovementCanvas(bph: 28_800, amplitudeDegrees: 278)
        BalanceWheelLive(bph: 28_800, amplitudeDegrees: 278).frame(width: 90, height: 90)
        HStack { TickingGearView(); TickingGearView(teeth: 10, size: 22, color: .accentColor) }
    }
    .padding()
    .background(AppColors.paper0)
}
