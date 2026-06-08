import SwiftData
import SwiftUI
import UIKit

/// TickLab — 4스텝 온보딩. 측정 단독이 아닌 '시계 라이프 플랫폼' 5축을 균형 있게 소개([[project_app_identity]]).
///
/// 0) WelcomeHero — 로고 + 태그라인 + 시작 CTA (skip = 끝으로)
/// 1) FeatureCarousel — 3p: 측정·진단 / 컬렉션·기록 / 분석
/// 2) QuickWatchAdd — 인기 시계 그리드(skip OK)
/// 3) FirstResultPlaceholder — 첫 사용 안내 + 컬렉션으로 이동
struct WelcomeFlowView: View {
    let onComplete: () -> Void
    @Environment(UserPreferences.self) private var preferences
    @State private var step: Int = 0

    var body: some View {
        ZStack {
            AppColors.paper0.ignoresSafeArea()
            Group {
                switch step {
                case 0: WelcomeHero(onNext: next, onSkip: skipToEnd)
                case 1: FeatureCarousel(onNext: next, onSkip: skipToEnd)
                case 2: QuickWatchAdd(onNext: next, onSkip: next)
                // 브랜드 리그 참여 명시 동의(Apple 5.1.1/5.1.2) — '참여하기' 누를 때만 opt-in ON.
                case 3: BrandLeagueConsentStep(
                            onJoin: { preferences.brandLeagueOptIn = true; next() },
                            onSkip: next)
                // Round 113 fix (사용자 보고: "측정 못함"): mock FirstMeasurement step 제거.
                // QuickAdd 후 바로 Mode picker (FirstResult) — 실제 측정은 컬렉션에서.
                default: FirstResultPlaceholder(onFinish: finish)
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .id(step)
        }
    }

    private func next() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            step += 1
        }
    }

    private func skipToEnd() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 4 }
    }

    private func finish() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onComplete()
    }
}

// MARK: - Step 1: Hero (디자인 SSOT screens-onboarding.jsx WelcomeView)
private struct WelcomeHero: View {
    let onNext: () -> Void
    let onSkip: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // 웨이브2-D: hero 등장 연출(로고→tagline 순차 fade-up).
    @State private var breathe = false
    @State private var logoIn = false
    @State private var taglineIn = false

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(String(localized: "welcome.skip"), action: onSkip)
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.ink2)
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                Spacer()
                logoMark
                    .padding(.bottom, 36)
                    .opacity(reduceMotion ? 1 : (logoIn ? 1 : 0))
                    .offset(y: reduceMotion ? 0 : (logoIn ? 0 : 12))
                tagline
                    .opacity(reduceMotion ? 1 : (taglineIn ? 1 : 0))
                    .offset(y: reduceMotion ? 0 : (taglineIn ? 0 : 12))
                Spacer()
                Spacer()
                ctaSection
            }
        }
        .onAppear { runEntrance() }
    }

    private func runEntrance() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.5)) { logoIn = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.18)) { taglineIn = true }
        // 미묘한 호흡 글로우 — 아주 느리게 반복.
        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
            breathe = true
        }
    }

    /// 12 dot ring + TL (디자인 SSOT screens-onboarding.jsx WelcomeView).
    /// jsx 명세: 140×140 rounded 32 primary-900 / radial glow inset -20 / SVG 100×100 viewBox
    /// dots r=2.6(12시 gold) r=1.6(나머지 white 70%) / TL SF Pro Display 28px 600 letter -0.04em
    /// Round 58: outer frame 180×180 (= jsx 140 + inset -20 area) 명시 고정.
    /// 웨이브2-D: 인라인 12-dot 루프 → DotRingMark(미묘한 호흡 글로우).
    private var logoMark: some View {
        ZStack {
            // Outer ambient glow — radial gold (inset -20 → 180×180). 호흡으로 세기 변조.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.accent.opacity(breathe ? 0.45 : 0.30), .clear],
                        center: .center, startRadius: 0, endRadius: 90
                    )
                )
                .frame(width: 180, height: 180)
            // Logo body — deep indigo rounded square.
            RoundedRectangle(cornerRadius: 32)
                .fill(AppColors.primaryDeep)
                .frame(width: 140, height: 140)
                .shadow(color: AppColors.primaryDeep.opacity(0.35), radius: 20, x: 0, y: 18)
            // 12-dot ring (viewBox 100×100, r=38, dot r=5.2/3.2) — DotRingMark 로 통일.
            ZStack {
                DotRingMark(size: 100, rotating: false, goldTopDot: true)
                // TL — SF Pro Display 28pt semibold (sans-serif 강조).
                Text("TL")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-1.5)
                    .foregroundStyle(AppColors.accent)
                    .offset(y: 4)
            }
            .frame(width: 100, height: 100)
        }
    }

    /// 첫 화면 — 로고 애니메이션은 유지하고, 아래엔 한 줄 소개만 표시(사용자 요청).
    private var tagline: some View {
        Text(String(localized: "onboard.welcome.sub"))
            .font(.system(size: 16))
            .foregroundStyle(AppColors.ink2)
            .multilineTextAlignment(.center)
            .lineSpacing(5)
            .padding(.horizontal, 32)
    }

    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button(action: onNext) {
                Text(String(localized: "welcome.cta_start"))
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.primaryDeep)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
            }
            .buttonStyle(.plain)
            Text(String(localized: "welcome.footer"))
                .font(.system(size: 11))
                .foregroundStyle(AppColors.ink3)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }
}

// MARK: - Step 2: Feature carousel (디자인 SSOT screens-onboarding.jsx FeatureCarouselView)
private struct FeatureCarousel: View {
    let onNext: () -> Void
    let onSkip: () -> Void
    @State private var page: Int = 0

    /// 온보딩 기능 페이지 — '시계 라이프 플랫폼' 축들([[project_app_identity]]).
    /// 측정은 가장 중요한 기능이 아니라 마지막 '일부'로. 리드는 컬렉션·기록.
    private enum Feature {
        case collect, analyze, community, measure
        var titleKey: String {
            switch self {
            case .collect:   return "feature.collect.title"
            case .analyze:   return "feature.analyze.title"
            case .community: return "feature.community.title"
            case .measure:   return "feature.measure.title"
            }
        }
        var bodyKey: String {
            switch self {
            case .collect:   return "feature.collect.body"
            case .analyze:   return "feature.analyze.body"
            case .community: return "feature.community.body"
            case .measure:   return "feature.measure.body"
            }
        }
    }

    /// 컬렉션·기록 → 분석 → (커뮤니티) → 측정. 커뮤니티는 활성 시에만 노출(게이트와 정합).
    private var pages: [Feature] {
        var p: [Feature] = [.collect, .analyze]
        if FeatureFlags.shared.communityEnabled { p.append(.community) }
        p.append(.measure)
        return p
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar — back / skip. Round 159: page 0 에서는 back 숨김 (동작 안 함).
            HStack {
                if page > 0 {
                    Button {
                        withAnimation { page -= 1 }
                    } label: {
                        Text(String(localized: "welcome.nav.back"))
                            .font(.system(size: 15))
                            .foregroundStyle(AppColors.ink2)
                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
                Spacer()
                Button(action: onSkip) {
                    Text(String(localized: "welcome.skip"))
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.ink2)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            // Carousel pages with abstract illustration.
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { idx, feature in
                    pageView(feature, active: idx == page).tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Custom dots (tk-pgdots — 8px dot, active 24px pill).
            HStack(spacing: 6) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? AppColors.accent : AppColors.ruleStrong)
                        .frame(width: i == page ? 24 : 8, height: 8)
                        .animation(.easeOut(duration: 0.2), value: page)
                }
            }
            .padding(.bottom, 16)

            // 사용자 보고 fix: founderCard 는 클릭 destination 미정의 + Pro 정책 변경됨 → 제거.
            VStack(spacing: 12) {
                Button {
                    if page < pages.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onNext()
                    }
                } label: {
                    Text(String(localized: page < pages.count - 1 ? "common.next" : "welcome.carousel.final_cta"))
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.primaryDeep)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    private func pageView(_ feature: Feature, active: Bool) -> some View {
        VStack(spacing: 32) {
            Spacer()
            // 240×240 일러스트 컨테이너 — 진입(active) 시 히어로 애니메이션 재생.
            ZStack {
                RoundedRectangle(cornerRadius: 36)
                    .fill(AppColors.accent50)
                Group {
                    switch feature {
                    case .collect:   CollectHero(active: active)
                    case .analyze:   AnalyzeHero(active: active)
                    case .community: CommunityHero(active: active)
                    case .measure:   MeasureHero(active: active)
                    }
                }
                .frame(width: 200, height: 200)
            }
            .frame(width: 240, height: 240)
            VStack(spacing: 12) {
                Text(String(localized: String.LocalizationValue(feature.titleKey)))
                    .font(.system(size: 32, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(AppColors.ink0)
                    .multilineTextAlignment(.center)
                Text(String(localized: String.LocalizationValue(feature.bodyKey)))
                    .font(.system(size: 17))
                    .foregroundStyle(AppColors.ink2)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
        }
    }

}

// MARK: - 온보딩 히어로 (진입 시 재생) — ticklab-onboarding 목업 포팅

/// 사인파 — .trim 으로 좌→우 드로잉.
private struct SineWaveShape: Shape {
    var periods: Double = 2
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let steps = 80
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let x = rect.width * CGFloat(t)
            let y = rect.midY - CGFloat(sin(t * .pi * 2 * periods)) * rect.height * 0.42
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

private struct TrendLineShape: Shape {
    let points: [(Double, Double)]
    func path(in r: CGRect) -> Path {
        var p = Path()
        for (i, pt) in points.enumerated() {
            let cp = CGPoint(x: r.minX + r.width * pt.0, y: r.minY + r.height * pt.1)
            if i == 0 { p.move(to: cp) } else { p.addLine(to: cp) }
        }
        return p
    }
}

/// 시계 다이얼 — 틱·서브다이얼·바늘 (목업 dial()).
private struct DialMark: View {
    var ring: Color = Color(white: 0.82)
    var face: Color = Color(red: 0.98, green: 0.98, blue: 0.97)
    var acc: Color = Color(white: 0.23)
    var body: some View {
        Canvas { ctx, sz in
            let s = min(sz.width, sz.height); let u = s / 100
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            func P(_ ang: Double, _ r: Double) -> CGPoint { CGPoint(x: c.x + CGFloat(cos(ang)) * CGFloat(r) * u, y: c.y + CGFloat(sin(ang)) * CGFloat(r) * u) }
            func rect(_ rr: Double) -> CGRect { CGRect(x: c.x - CGFloat(rr) * u, y: c.y - CGFloat(rr) * u, width: CGFloat(rr) * 2 * u, height: CGFloat(rr) * 2 * u) }
            ctx.fill(Path(ellipseIn: rect(45)), with: .color(face))
            ctx.stroke(Path(ellipseIn: rect(46.5)), with: .color(ring), lineWidth: 3 * u)
            for i in 0..<12 {
                let a = Double(i) * 30 * .pi / 180 - .pi / 2
                let r1 = i % 3 == 0 ? 33.0 : 35.0
                var t = Path(); t.move(to: P(a, r1)); t.addLine(to: P(a, 39))
                ctx.stroke(t, with: .color(acc.opacity(0.55)), lineWidth: (i % 3 == 0 ? 2.0 : 1.0) * u)
            }
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 7 * u, y: c.y - 34 * u - 7 * u, width: 14 * u, height: 14 * u)), with: .color(acc.opacity(0.45)), lineWidth: 0.9 * u)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 7 * u, y: c.y + 34 * u - 7 * u, width: 14 * u, height: 14 * u)), with: .color(acc.opacity(0.45)), lineWidth: 0.9 * u)
            var h1 = Path(); h1.move(to: c); h1.addLine(to: P(-(.pi / 2), 20)); ctx.stroke(h1, with: .color(acc), style: StrokeStyle(lineWidth: 2.6 * u, lineCap: .round))
            var h2 = Path(); h2.move(to: c); h2.addLine(to: P(-0.3, 15)); ctx.stroke(h2, with: .color(acc), style: StrokeStyle(lineWidth: 2 * u, lineCap: .round))
            ctx.fill(Path(ellipseIn: rect(2.6)), with: .color(acc))
        }
    }
}

/// 만족 기분 — 흰 원 + 골드 링 + 눈썹 아치 + 미소 (목업 moodSatisfied()).
private struct MoodSatisfied: View {
    var body: some View {
        Canvas { ctx, sz in
            let s = min(sz.width, sz.height); let u = s / 100
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: c.x + CGFloat(x - 50) * u, y: c.y + CGFloat(y - 50) * u) }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 43 * u, y: c.y - 43 * u, width: 86 * u, height: 86 * u)), with: .color(.white))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 43 * u, y: c.y - 43 * u, width: 86 * u, height: 86 * u)), with: .color(AppColors.accent), lineWidth: 4 * u)
            var b1 = Path(); b1.move(to: P(37, 45)); b1.addQuadCurve(to: P(45, 45), control: P(41, 40))
            ctx.stroke(b1, with: .color(AppColors.accent), style: StrokeStyle(lineWidth: 3.2 * u, lineCap: .round))
            var b2 = Path(); b2.move(to: P(55, 45)); b2.addQuadCurve(to: P(63, 45), control: P(59, 40))
            ctx.stroke(b2, with: .color(AppColors.accent), style: StrokeStyle(lineWidth: 3.2 * u, lineCap: .round))
            var sm = Path(); sm.move(to: P(38, 57)); sm.addQuadCurve(to: P(62, 57), control: P(50, 69))
            ctx.stroke(sm, with: .color(AppColors.accent), style: StrokeStyle(lineWidth: 3.4 * u, lineCap: .round))
        }
    }
}

/// 측정 — 파형 드로잉 + 4점 팝 + 밸런스 휠 진동 + rate 카운트업.
private struct MeasureHero: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var rm
    @State private var wave: CGFloat = 0
    @State private var beat = false
    @State private var dots = false
    @State private var rate: Double = 0
    @State private var runID = 0   // 카운트업 세대 토큰 — 페이지 재진입 시 옛 closure 무효화
    private let dotPos: [(CGFloat, CGFloat)] = [(-62, -37), (-20, 9), (22, -37), (64, 9)]
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [AppColors.accent.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 96)).frame(width: 200, height: 200)
            SineWaveShape(periods: 2).trim(from: 0, to: wave)
                .stroke(AppColors.primary500, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                .frame(width: 168, height: 56).offset(y: -14)
            ForEach(0..<4, id: \.self) { i in
                Circle().fill(i % 2 == 0 ? AppColors.success : AppColors.accent)
                    .frame(width: 8, height: 8).offset(x: dotPos[i].0, y: dotPos[i].1)
                    .scaleEffect(dots ? 1 : 0).opacity(dots ? 1 : 0)
            }
            BalanceWheelIcon(size: 44, color: AppColors.accent, holeColor: .clear)
                .rotationEffect(.degrees(rm ? 0 : (beat ? 140 : -140)))
                .offset(x: 66, y: -64)
            Text(String(format: "+%.1f %@", rate, String(localized: "unit.seconds_per_day")))
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.success).offset(y: 64)
        }
        .frame(width: 200, height: 200)
        .onChange(of: active) { _, on in if on { play() } else { runID += 1; wave = 0; dots = false; rate = 0 } }
        .onAppear { if active { play() } }
    }
    private func play() {
        runID += 1
        if rm { wave = 1; dots = true; rate = 0.8; return }
        wave = 0; dots = false; rate = 0
        withAnimation(.easeOut(duration: 0.9)) { wave = 1 }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.85)) { dots = true }
        withAnimation(.easeInOut(duration: 0.58).repeatForever(autoreverses: true)) { beat = true }
        let myRun = runID
        for i in 1...18 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(i)) { if runID == myRun { rate = 0.8 * Double(i) / 18.0 } } }
    }
}

/// 컬렉션·기록 — 다이어리 카드 스택 + 다이얼 + 라인 + 기분 팝.
private struct CollectHero: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var rm
    @State private var b2 = false
    @State private var b1 = false
    @State private var front = false
    @State private var mood = false
    @State private var lines: CGFloat = 0
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(AppColors.accent100).frame(width: 116, height: 148)
                .offset(x: 26, y: 4).opacity(b2 ? 1 : 0).offset(y: b2 ? 0 : 12)
            RoundedRectangle(cornerRadius: 14).fill(AppColors.accent50).frame(width: 116, height: 148)
                .offset(x: 13, y: 10).opacity(b1 ? 1 : 0).offset(y: b1 ? 0 : 12)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 9).fill(AppColors.paper2)
                    .frame(height: 70).overlay(DialMark().frame(width: 54, height: 54))
                line(0.82); line(0.6); line(0.72, gold: true)
            }
            .padding(12).frame(width: 122, height: 156)
            .background(RoundedRectangle(cornerRadius: 14).fill(AppColors.paper1))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
            .offset(x: -6).opacity(front ? 1 : 0).offset(y: front ? 6 : 18)
            MoodSatisfied().frame(width: 42, height: 42).offset(x: 54, y: -78)
                .scaleEffect(mood ? 1 : 0).opacity(mood ? 1 : 0)
        }
        .frame(width: 200, height: 200)
        .onChange(of: active) { _, on in if on { play() } else { reset() } }
        .onAppear { if active { play() } }
    }
    private func line(_ w: CGFloat, gold: Bool = false) -> some View {
        Capsule().fill(gold ? AppColors.accent.opacity(0.5) : AppColors.rule)
            .frame(width: 90 * w, height: 5).scaleEffect(x: lines, anchor: .leading)
    }
    private func reset() { b2 = false; b1 = false; front = false; mood = false; lines = 0 }
    private func play() {
        if rm { b2 = true; b1 = true; front = true; mood = true; lines = 1; return }
        reset()
        withAnimation(.easeOut(duration: 0.4).delay(0.05)) { b2 = true }
        withAnimation(.easeOut(duration: 0.4).delay(0.15)) { b1 = true }
        withAnimation(.easeOut(duration: 0.45).delay(0.28)) { front = true }
        withAnimation(.easeOut(duration: 0.4).delay(0.5)) { lines = 1 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.7)) { mood = true }
    }
}

/// 분석 — 막대 grow + 추세선 드로잉 + 별 팝.
private struct AnalyzeHero: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var rm
    @State private var grow: CGFloat = 0
    @State private var line: CGFloat = 0
    @State private var spark = false
    private let heights: [CGFloat] = [54, 78, 62, 104]
    private let trendPts: [(Double, Double)] = [(0.121, 0.509), (0.374, 0.291), (0.626, 0.436), (0.879, 0.055)]
    var body: some View {
        ZStack {
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(i == 3 ? AppColors.accent : AppColors.primary500.opacity(0.45))
                        .frame(width: 30, height: heights[i])
                        .scaleEffect(y: grow, anchor: .bottom)
                }
            }
            .frame(width: 174, height: 110, alignment: .bottom).offset(y: 6)
            Rectangle().fill(AppColors.rule).frame(width: 174, height: 1).offset(y: 61)
            TrendLineShape(points: trendPts).trim(from: 0, to: line)
                .stroke(AppColors.primaryDeep, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                .frame(width: 174, height: 110).offset(y: 6)
            Image(systemName: "sparkle").font(.system(size: 18)).foregroundStyle(AppColors.accent)
                .scaleEffect(spark ? 1 : 0).opacity(spark ? 1 : 0).offset(x: 78, y: -82)
            Text(String(localized: "onboard.analyze.label"))
                .font(.system(size: 12, weight: .medium)).foregroundStyle(AppColors.ink2).offset(y: 88)
        }
        .frame(width: 200, height: 200)
        .onChange(of: active) { _, on in if on { play() } else { grow = 0; line = 0; spark = false } }
        .onAppear { if active { play() } }
    }
    private func play() {
        if rm { grow = 1; line = 1; spark = true; return }
        grow = 0; line = 0; spark = false
        withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { grow = 1 }
        withAnimation(.easeOut(duration: 0.7).delay(0.45)) { line = 1 }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(1.05)) { spark = true }
    }
}

/// 커뮤니티 — 카드 등장 + 다이얼 + 하트 비트 + 코너 하트 + 좋아요 카운트업.
private struct CommunityHero: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var rm
    @State private var card = false
    @State private var peek = false
    @State private var corner = false
    @State private var heart = false
    @State private var likes = 0
    @State private var runID = 0   // 카운트업 세대 토큰 — 페이지 재진입 시 옛 closure 무효화
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(AppColors.accent100)
                .frame(width: 106, height: 126).offset(x: 18, y: -10).opacity(peek ? 0.85 : 0)
            VStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.93, green: 0.94, blue: 0.97))
                    .frame(height: 80).overlay(DialMark(ring: AppColors.accent, acc: AppColors.primary500).frame(width: 54, height: 54))
                HStack(spacing: 7) {
                    Image(systemName: "heart.fill").foregroundStyle(AppColors.danger).font(.system(size: 18)).scaleEffect(heart ? 1.2 : 1)
                    Capsule().fill(AppColors.rule).frame(height: 6)
                }
            }
            .padding(11).frame(width: 128, height: 136)
            .background(RoundedRectangle(cornerRadius: 16).fill(AppColors.paper1))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.rule, lineWidth: 1))
            .offset(x: -6, y: -12).opacity(card ? 1 : 0).scaleEffect(card ? 1 : 0.9)
            Image(systemName: "heart.fill").font(.system(size: 18)).foregroundStyle(AppColors.accent)
                .scaleEffect(corner ? 1 : 0).opacity(corner ? 1 : 0).offset(x: 56, y: -80)
            HStack(spacing: 5) {
                Image(systemName: "heart.fill").font(.system(size: 14)).foregroundStyle(AppColors.danger)
                Text(String(format: String(localized: "onboard.community.likes"), likes))
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(AppColors.ink2)
            }.offset(y: 80).opacity(card ? 1 : 0)
        }
        .frame(width: 200, height: 200)
        .onChange(of: active) { _, on in if on { play() } else { runID += 1; card = false; peek = false; corner = false; likes = 0 } }
        .onAppear { if active { play() } }
    }
    private func play() {
        runID += 1
        if rm { card = true; peek = true; corner = true; likes = 24; return }
        card = false; peek = false; corner = false; likes = 0
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) { card = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.25)) { peek = true }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.9)) { corner = true }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(0.8)) { heart = true }
        let myRun = runID
        for i in 1...24 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.9 + 0.022 * Double(i)) { if runID == myRun { likes = i } } }
    }
}

// MARK: - 브랜드 리그 참여 동의 (Apple 5.1.1/5.1.2 — 명시적 opt-in)
/// 익명 브랜드+착용빈도 업로드 동의. '참여하기' = opt-in ON, '나중에' = OFF 유지.
/// 측정값·사진·시리얼·구매가는 절대 전송하지 않음(문구로 명시).
private struct BrandLeagueConsentStep: View {
    let onJoin: () -> Void
    let onSkip: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(String(localized: "welcome.skip"), action: onSkip)
                    .font(.system(size: 15)).foregroundStyle(AppColors.ink2)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing).contentShape(Rectangle())
            }
            .padding(.horizontal, 24).padding(.top, 12)
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 36).fill(AppColors.accent50)
                Image(systemName: "medal.fill")
                    .font(.system(size: 88, weight: .regular)).foregroundStyle(AppColors.accent)
            }
            .frame(width: 240, height: 240)
            VStack(spacing: 12) {
                Text(String(localized: "onboard.league.title"))
                    .font(.system(size: 30, weight: .semibold)).tracking(-0.5)
                    .foregroundStyle(AppColors.ink0).multilineTextAlignment(.center)
                Text(String(localized: "onboard.league.body"))
                    .font(.system(size: 15)).foregroundStyle(AppColors.ink2)
                    .multilineTextAlignment(.center).lineSpacing(3).padding(.horizontal, 28)
            }
            .padding(.top, 28)
            Spacer()
            VStack(spacing: 8) {
                Button(action: onJoin) {
                    Text(String(localized: "onboard.league.join"))
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(AppColors.primaryDeep).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                }
                .buttonStyle(.plain)
                Button(action: onSkip) {
                    Text(String(localized: "onboard.league.later"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.ink2).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24).padding(.bottom, 30)
        }
    }
}

// MARK: - Step 3: Quick watch add (디자인 SSOT screens-onboarding.jsx QuickWatchAddView)
private struct QuickWatchAdd: View {
    let onNext: () -> Void
    let onSkip: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var selected: Int? = nil
    /// 인기시계 선택 → 등록폼(무브먼트 확인)으로 연결. 폼이 닫히면 다음 단계.
    @State private var pendingWatch: Watch?
    @State private var showEdit = false

    var body: some View {
        VStack(spacing: 0) {
            // NavBar — title "어떤 시계예요?" + back + skip.
            HStack {
                Button(action: onSkip) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppColors.ink0)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "welcome.nav.back"))
                Spacer()
                Text(String(localized: "welcome.pick_watch"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                Spacer()
                Button(String(localized: "welcome.skip")) {
                    selected = nil
                    onNext()
                }
                .font(.system(size: 15))
                .foregroundStyle(AppColors.ink2)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .padding(.horizontal, 16)
            .frame(height: 44)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "welcome.pick_watch.subtitle"))
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.ink2)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(Array(PopularWatches.all.enumerated()), id: \.offset) { idx, item in
                            watchCard(idx: idx, item: item)
                        }
                        // "기타 — 직접 입력" 카드.
                        Button {
                            selected = -1
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 22))
                                    .foregroundStyle(AppColors.ink2)
                                Text(String(localized: "quickwatch.custom.title"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColors.ink2)
                                Text(String(localized: "quickwatch.custom.subtitle"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColors.ink2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 124)
                            .background(selected == -1 ? AppColors.accent50 : AppColors.paper2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(
                                        selected == -1 ? AppColors.accent : AppColors.rule,
                                        style: StrokeStyle(lineWidth: selected == -1 ? 2 : 1, dash: selected == -1 ? [] : [4])
                                    )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                }
            }

            // Bottom CTA.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.clear, AppColors.paper0],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 16)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if let s = selected, s >= 0 {
                        let item = PopularWatches.all[s]
                        // 등록 직후 등록폼(무브먼트 섹션 포함)을 띄워 확인 → 폼이 닫히면 다음 단계.
                        pendingWatch = add(brand: item.brand, model: item.modelName,
                                           caliber: item.caliber, movementType: item.movementType)
                        showEdit = true
                    } else {
                        onNext()   // 직접입력/스킵은 컬렉션에서 추가
                    }
                } label: {
                    Text(String(localized: selected == nil ? "quickwatch.cta.pick"
                                          : selected == -1 ? "quickwatch.cta.custom"
                                          : "quickwatch.cta.next"))
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.primaryDeep)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                }
                .buttonStyle(.plain)
                .opacity(selected == nil ? 0.4 : 1)
                .disabled(selected == nil)
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .background(AppColors.paper0)
            }
        }
        .sheet(isPresented: $showEdit, onDismiss: { onNext() }) {
            if let w = pendingWatch {
                NavigationStack { AddWatchView(existing: w, emphasizeMovement: true) }
            }
        }
    }

    private func watchCard(idx: Int, item: PopularWatchSeed) -> some View {
        let isSel = selected == idx
        return Button {
            // Round 94: 햅틱 피드백 + 즉시 선택 시각 변경.
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeOut(duration: 0.15)) { selected = idx }
        } label: {
            VStack(spacing: 6) {
                WatchSilhouette(model: item.model, tone: item.tone, size: 56)
                Text(item.brand)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.ink2)
                Text(item.modelName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 124)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(isSel ? AppColors.accent50 : AppColors.paper1)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isSel ? AppColors.accent : AppColors.rule,
                        lineWidth: isSel ? 2 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    @discardableResult
    private func add(brand: String, model: String, caliber: String, movementType: WatchMovementType) -> Watch {
        // 인기목록 자동배정 캘리버는 추정치 — 무브먼트 미확정(false). 측정 시 자동감지로 실제 BPH 사용,
        //   등록폼에서 사용자가 확인하면 confirmed=true 로 전환.
        let watch = Watch(brand: brand, model: model, caliber: caliber,
                          movementType: movementType, movementConfirmed: false)
        modelContext.insert(watch)
        try? modelContext.save()
        return watch
    }
}
// MARK: - Step 5: 사용 톤 선택 + 첫 측정 안내 (Round 128: mock 결과 제거).
// 사용자 보고: "측정 안 한 상태인데 결과 화면 — 혼란" → mock verdict 제거, Mode picker + intro 만.
private struct FirstResultPlaceholder: View {
    let onFinish: () -> Void
    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        VStack(spacing: 0) {
            HStack { Color.clear.frame(width: 36, height: 36); Spacer(); Color.clear.frame(width: 36, height: 36) }
                .padding(.horizontal, 16)
                .frame(height: 44)

            ScrollView {
                VStack(spacing: 20) {
                    Spacer().frame(height: 12)
                    introHeader
                    // Round 138 사용자 요청: 사용자 모드 선택 제거 — 항상 .pro (전문 분석).
                    //   UserPreferences.userMode 기본값도 .pro 로 변경됨.
                    measureGuideCard
                }
                .padding(.horizontal, 16)
            }

            Button(action: onFinish) {
                Text(String(localized: "welcome.firstresult.cta"))
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.primaryDeep)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    private var introHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppColors.accent50)
                    .frame(width: 96, height: 96)
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(AppColors.accent)
            }
            Text(String(localized: "welcome.firstresult.ready"))
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(AppColors.ink0)
            Text(String(localized: "welcome.firstresult.body"))
                .font(.system(size: 16))
                .lineSpacing(3)
                .foregroundStyle(AppColors.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    private var measureGuideCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ConceptGlyph(systemName: "mic.circle.fill", size: 28)
                .foregroundStyle(AppColors.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "welcome.firstresult.tip.title"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                Text(String(localized: "welcome.firstresult.tip.body"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink2)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    // Round 148 (Doyoon 4 #2): modeSelectInline / modeCard dead — UserMode 분기 제거 후 잔재. 통째 제거.
}

// 측정 mock 결과(Round 128) 제거 후 잔재였던 COSCBarView / ConfidenceChip 삭제 — 온보딩에서 미사용.
