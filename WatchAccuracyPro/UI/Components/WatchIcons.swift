import SwiftUI

// MARK: - Custom horology vector icons
//
// SF Symbol(기본 아이콘) 대신 시계 브랜드에 맞춘 커스텀 벡터 아이콘 세트.
// 전부 코드 드로잉(Path/Shape) — 외부 이미지 파일 없이 크기·색 자유, 어떤 해상도에서도 선명.
// 색은 단색 토큰 1개를 받아 라인/필 스타일을 통일한다(프리미엄 모노라인).

/// 밸런스 휠 — 기계식 무브먼트의 심장(진동자). 림 + 타이밍 스크루 4 + 스포크 3 + 허브.
/// 측정·로딩·브랜드 마크에 어울리는 시그니처 아이콘.
struct BalanceWheelIcon: View {
    var size: CGFloat = 26
    var color: Color = AppColors.ink2
    /// 허브 중앙 보석홀 색(배경과 대비). 메달리온 위에선 paper1.
    var holeColor: Color = AppColors.paper1

    var body: some View {
        ZStack {
            // 림(바깥 링) — 가늘고 깔끔하게.
            Circle()
                .stroke(color, lineWidth: size * 0.07)
                .frame(width: size * 0.9, height: size * 0.9)
            // 6 스포크 — 3 크로스바(0/60/120°), 얇게. (기존 굵은 별표 → 얇게 + 큰 허브로 정돈)
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: size * 0.055, height: size * 0.84)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
            // 타이밍 스크루 6개 — 각 스포크 끝(림 위) 작은 균형추. 작게 해서 핸들 아닌 밸런스휠 느낌.
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: size * 0.085, height: size * 0.085)
                    .offset(y: -size * 0.45)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
            // 허브(스태프) — 크게 해서 중앙 교차를 가림(별표 방지) + 보석홀.
            Circle().fill(color).frame(width: size * 0.27, height: size * 0.27)
            Circle().fill(holeColor).frame(width: size * 0.12, height: size * 0.12)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 용두(크라운) — 케이스 우측의 조작 노브. 톱니 림 + 스템.
struct CrownIcon: View {
    var size: CGFloat = 26
    var color: Color = AppColors.ink2

    var body: some View {
        ZStack {
            // 스템(가는 축).
            RoundedRectangle(cornerRadius: size * 0.04)
                .fill(color)
                .frame(width: size * 0.16, height: size * 0.30)
                .offset(x: size * 0.42)
            // 톱니 림(크라운 헤드).
            CogShape(teeth: 9, innerRatio: 0.80)
                .fill(color)
                .frame(width: size * 0.78, height: size * 0.78)
            // 중앙 구멍.
            Circle().fill(AppColors.paper1).frame(width: size * 0.22, height: size * 0.22)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 다이얼 + 핸즈 — 시·분침이 있는 시계 정면.
struct DialHandsIcon: View {
    var size: CGFloat = 26
    var color: Color = AppColors.ink2

    var body: some View {
        ZStack {
            Circle().stroke(color, lineWidth: size * 0.075)
                .frame(width: size * 0.9, height: size * 0.9)
            // 12시 인덱스 강조.
            ForEach(0..<12, id: \.self) { i in
                Capsule().fill(color.opacity(i % 3 == 0 ? 1 : 0.4))
                    .frame(width: size * 0.04, height: size * (i % 3 == 0 ? 0.10 : 0.06))
                    .offset(y: -size * 0.37)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
            // 분침.
            Capsule().fill(color).frame(width: size * 0.05, height: size * 0.34)
                .offset(y: -size * 0.10)
                .rotationEffect(.degrees(40))
            // 시침.
            Capsule().fill(color).frame(width: size * 0.06, height: size * 0.22)
                .offset(y: -size * 0.04)
                .rotationEffect(.degrees(-70))
            Circle().fill(color).frame(width: size * 0.1, height: size * 0.1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 인증 seal(로제트) — 주화 가장자리 같은 갈래 메달 + 안쪽 링 + 중앙 점.
/// 딜러 배지처럼 "공식/인증" 표시에 사용. 단색이라 골드 배경 위에서 또렷.
struct DealerSealIcon: View {
    var size: CGFloat = 11
    var color: Color = AppColors.primaryDeep

    var body: some View {
        ZStack {
            CogShape(teeth: 12, innerRatio: 0.84)
                .fill(color)
            Circle()
                .stroke(AppColors.accentLight.opacity(0.9), lineWidth: size * 0.06)
                .frame(width: size * 0.56, height: size * 0.56)
            Circle()
                .fill(AppColors.accentLight.opacity(0.9))
                .frame(width: size * 0.16, height: size * 0.16)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Shapes

/// 톱니/갈래 윤곽 — 바깥/안쪽 반경을 번갈아 찍어 코인 엣지·코그 모양을 만든다.
struct CogShape: Shape {
    var teeth: Int = 12
    /// 안쪽 반경 비율(1에 가까울수록 얕은 갈래).
    var innerRatio: CGFloat = 0.84

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rOuter = min(rect.width, rect.height) / 2
        let rInner = rOuter * innerRatio
        let total = teeth * 2
        for i in 0..<total {
            let r = i.isMultiple(of: 2) ? rOuter : rInner
            let a = Double(i) / Double(total) * 2 * .pi - .pi / 2
            let pt = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Balance-wheel loader (메달리온 + 가운데 커스텀 밸런스 휠)

/// 로딩 인디케이터 — 실제 시계처럼 **좌우로 똑딱똑딱 진동(beat)하는 밸런스 휠**.
/// 일반 스피너(도는 점/링)와 명확히 다른, 기계식 무브먼트 메타포의 로딩.
/// Reduce Motion 시 정지.
struct BalanceWheelLoader: View {
    var size: CGFloat = 72
    /// 진동 진폭(도). 클수록 크게 뛴다.
    var amplitude: Double = 34
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = false

    var body: some View {
        ZStack {
            // 은은한 골드 ambient.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.accent.opacity(0.16), .clear],
                        center: .center, startRadius: 0, endRadius: size * 0.62
                    )
                )
                .frame(width: size * 1.25, height: size * 1.25)
            // 밸런스 휠 — 좌우 진동.
            BalanceWheelIcon(size: size, color: AppColors.ink1, holeColor: AppColors.paper0)
                .rotationEffect(.degrees(reduceMotion ? 0 : (beat ? amplitude : -amplitude)))
        }
        .frame(width: size * 1.25, height: size * 1.25)
        .onAppear {
            guard !reduceMotion else { return }
            // 똑딱 — easeInOut 왕복으로 시계 비트 느낌.
            withAnimation(.easeInOut(duration: 0.46).repeatForever(autoreverses: true)) {
                beat = true
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Watch icons") {
    VStack(spacing: 28) {
        HStack(spacing: 24) {
            BalanceWheelIcon(size: 40)
            CrownIcon(size: 40)
            DialHandsIcon(size: 40)
        }
        HStack(spacing: 8) {
            Text("하늘").font(.system(size: 16, weight: .semibold))
            DealerBadge()
        }
        BalanceWheelLoader()
    }
    .padding(40)
    .background(AppColors.paper0)
}

/// 메인스프링(태엽) — 배럴 안에 감긴 나선 코일. '태엽 감기' 액션/알림 아이콘.
/// 아르키메데스 나선(3바퀴) + 중심 아버(arbor). 회전시키면 감기는 느낌.
struct MainspringIcon: View {
    var size: CGFloat = 22
    var color: Color = AppColors.ink0
    /// 코일을 감싸는 배럴(통) 테두리 표시 여부.
    var showsBarrel: Bool = true

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = canvasSize.width
            let c = CGPoint(x: s / 2, y: s / 2)
            let lw = s * 0.085

            if showsBarrel {
                // 배럴 — 옅은 바깥 원.
                ctx.stroke(Path(ellipseIn: CGRect(x: lw, y: lw, width: s - 2 * lw, height: s - 2 * lw)),
                           with: .color(color.opacity(0.28)), lineWidth: lw * 0.9)
            }
            // 나선 코일 — 안에서 바깥으로.
            var spiral = Path()
            let turns = 3.0
            let maxR = s * (showsBarrel ? 0.36 : 0.42)
            let minR = s * 0.05
            let steps = 200
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let angle = t * turns * 2 * .pi - .pi / 2
                let r = minR + (maxR - minR) * t
                let p = CGPoint(x: c.x + CGFloat(cos(angle)) * r, y: c.y + CGFloat(sin(angle)) * r)
                if i == 0 { spiral.move(to: p) } else { spiral.addLine(to: p) }
            }
            ctx.stroke(spiral, with: .color(color), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            // 중심 아버.
            let ar = s * 0.07
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - ar, y: c.y - ar, width: 2 * ar, height: 2 * ar)), with: .color(color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
