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

    /// 디자인 tk-display-l = 48px/56 line-height, weight 700, letter -0.03em (-1.44pt).
    private var tagline: some View {
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                // Round 124 (Hard Rule 3): 인라인 한국어 → Localizable.
                Text(String(localized: "welcome.hero.line1"))
                Text(String(localized: "welcome.hero.line2"))
                HStack(spacing: 0) {
                    Text(String(localized: "welcome.hero.accent")).foregroundStyle(AppColors.accent).fontWeight(.bold)
                    Text(String(localized: "welcome.hero.suffix"))
                }
            }
            .font(.system(size: 48, weight: .bold))
            .foregroundStyle(AppColors.ink0)
            .tracking(-1.44)
            .multilineTextAlignment(.center)
            .lineSpacing(8)
            .lineLimit(3)
            .minimumScaleFactor(0.6)
            // Subtitle tk-body-lg = 17/24.
            Text(String(localized: "welcome.subtitle"))
                .font(.system(size: 17))
                .foregroundStyle(AppColors.ink2)
        }
        .padding(.horizontal, 24)
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
                    pageView(feature).tag(idx)
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

    private func pageView(_ feature: Feature) -> some View {
        VStack(spacing: 32) {
            Spacer()
            // 240×240 illustration container — accent50 (paper2 너무 옅음).
            ZStack {
                RoundedRectangle(cornerRadius: 36)
                    .fill(AppColors.accent50)
                illustration(for: feature)
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

    @ViewBuilder private func illustration(for feature: Feature) -> some View {
        switch feature {
        case .measure:   illustrationMeasure
        case .collect:   illustrationCollect
        case .analyze:   illustrationAnalyze
        case .community: illustrationCommunity
        }
    }

    // Page 0 — waveform + dots + "+5.2 s/d". Round 158: 시각 무게 중심 (100,100) 으로 재정렬.
    // Round 19 (Sora): TabView swipe 중 매 frame Canvas re-draw 비용 회피 — .drawingGroup 으로 Metal-backed offscreen.
    private var illustrationMeasure: some View {
        Canvas { ctx, size in
            let s = size.width / 200.0
            // radial gold gradient — center 를 정중앙으로.
            let bgPath = Path(ellipseIn: CGRect(
                x: (100 - 90) * s, y: (100 - 90) * s,
                width: 180 * s, height: 180 * s
            ))
            ctx.fill(bgPath, with: .radialGradient(
                Gradient(colors: [AppColors.accent.opacity(0.25), .clear]),
                center: CGPoint(x: 100 * s, y: 100 * s),
                startRadius: 0,
                endRadius: 90 * s
            ))
            // waveform path — y-axis 를 y=90 으로 살짝 위로 올려 text 와 균형.
            var p = Path()
            p.move(to: CGPoint(x: 20 * s, y: 90 * s))
            p.addQuadCurve(to: CGPoint(x: 60 * s, y: 90 * s), control: CGPoint(x: 40 * s, y: 50 * s))
            p.addQuadCurve(to: CGPoint(x: 100 * s, y: 90 * s), control: CGPoint(x: 80 * s, y: 130 * s))
            p.addQuadCurve(to: CGPoint(x: 140 * s, y: 90 * s), control: CGPoint(x: 120 * s, y: 50 * s))
            p.addQuadCurve(to: CGPoint(x: 180 * s, y: 90 * s), control: CGPoint(x: 160 * s, y: 130 * s))
            ctx.stroke(p, with: .color(AppColors.primary500), lineWidth: 2 * s)
            // 4 dots @ y=90.
            for (i, xPos) in [40.0, 80.0, 120.0, 160.0].enumerated() {
                let color: Color = i % 2 == 0 ? AppColors.success : AppColors.accent
                let r = 4.0 * s
                let rect = CGRect(
                    x: (xPos - 4) * s, y: (90 - 4) * s,
                    width: 2 * r, height: 2 * r
                )
                ctx.fill(Path(ellipseIn: rect), with: .color(color))
            }
            // Round 158: "+5.2 s/d" → "+0.8 s/d" (정상 워치 범위, ±1 s/d body 카피와 일치).
            let text = Text("+0.8 \(String(localized: "unit.seconds_per_day"))")
                .font(.system(size: 16 * s, weight: .medium, design: .monospaced))
                .foregroundColor(AppColors.ink0)
            ctx.draw(text, at: CGPoint(x: 100 * s, y: 140 * s), anchor: .center)
        }
        .drawingGroup()
    }

    // Page 1 — journal card with photo placeholder (jsx 200×200 viewBox port).
    // Round 19 (Sora): .drawingGroup 으로 TabView transform 비용 절감.
    private var illustrationCollect: some View {
        Canvas { ctx, size in
            let s = size.width / 200.0
            // White card 120×140 at (40,30) radius 6, border #E5E5E5.
            let cardRect = CGRect(x: 40 * s, y: 30 * s, width: 120 * s, height: 140 * s)
            ctx.fill(
                Path(roundedRect: cardRect, cornerRadius: 6 * s),
                with: .color(.white)
            )
            ctx.stroke(
                Path(roundedRect: cardRect, cornerRadius: 6 * s),
                with: .color(AppColors.rule),
                lineWidth: 1
            )
            // 6px gold accent stripe (left).
            let stripeRect = CGRect(x: 40 * s, y: 30 * s, width: 6 * s, height: 140 * s)
            ctx.fill(Path(stripeRect), with: .color(AppColors.accent))
            // Text placeholder lines.
            var line1 = Path()
            line1.move(to: CGPoint(x: 60 * s, y: 60 * s))
            line1.addLine(to: CGPoint(x: 140 * s, y: 60 * s))
            ctx.stroke(line1, with: .color(AppColors.rule), lineWidth: 1)
            var line2 = Path()
            line2.move(to: CGPoint(x: 60 * s, y: 80 * s))
            line2.addLine(to: CGPoint(x: 120 * s, y: 80 * s))
            ctx.stroke(line2, with: .color(AppColors.rule), lineWidth: 1)
            // Photo placeholder rect 80×50 at (60,95), accent-100 fill.
            let photoRect = CGRect(x: 60 * s, y: 95 * s, width: 80 * s, height: 50 * s)
            ctx.fill(
                Path(roundedRect: photoRect, cornerRadius: 4 * s),
                with: .color(AppColors.accent100)
            )
            // Center gold circle r=14 at (100,120).
            let circleRect = CGRect(
                x: (100 - 14) * s, y: (120 - 14) * s,
                width: 28 * s, height: 28 * s
            )
            ctx.fill(Path(ellipseIn: circleRect), with: .color(AppColors.accent))
        }
        .drawingGroup()
    }

    // Page 2 — 분석: 상승 트렌드 라인 + 막대 + 별. (측정 게이지 대신 '분석' 축 표현 — 정체성 균형)
    // Round 19 (Sora): .drawingGroup 으로 TabView transform 비용 절감.
    private var illustrationAnalyze: some View {
        Canvas { ctx, size in
            let s = size.width / 200.0
            let baseY = 150.0
            let xs: [Double] = [50, 85, 120, 155]
            let barH: [Double] = [38, 64, 52, 92]
            // 막대 — 마지막(최고)만 골드, 나머지는 옅은 indigo.
            for (i, x) in xs.enumerated() {
                let h = barH[i] * s
                let rect = CGRect(x: (x - 13) * s, y: baseY * s - h, width: 26 * s, height: h)
                let col = i == xs.count - 1 ? AppColors.accent : AppColors.primary500.opacity(0.45)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 5 * s), with: .color(col))
            }
            // baseline.
            var base = Path()
            base.move(to: CGPoint(x: 36 * s, y: baseY * s))
            base.addLine(to: CGPoint(x: 168 * s, y: baseY * s))
            ctx.stroke(base, with: .color(AppColors.rule), lineWidth: 1)
            // 트렌드 라인(상승) + 노드.
            let pts: [(Double, Double)] = [(50, 112), (85, 84), (120, 96), (155, 52)]
            var line = Path()
            for (i, pt) in pts.enumerated() {
                let p = CGPoint(x: pt.0 * s, y: pt.1 * s)
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            ctx.stroke(line, with: .color(AppColors.primaryDeep),
                       style: StrokeStyle(lineWidth: 2.5 * s, lineCap: .round, lineJoin: .round))
            for pt in pts {
                ctx.fill(Path(ellipseIn: CGRect(x: (pt.0 - 3) * s, y: (pt.1 - 3) * s, width: 6 * s, height: 6 * s)),
                         with: .color(AppColors.accent))
            }
            // sparkle.
            ctx.fill(starPath(center: CGPoint(x: 168 * s, y: 42 * s), radius: 9 * s), with: .color(AppColors.accent))
            // 라벨.
            let label = Text(String(localized: "welcome.illustration.trend"))
                .font(.system(size: 12 * s, weight: .medium))
                .foregroundColor(AppColors.ink0)
            ctx.draw(label, at: CGPoint(x: 100 * s, y: 180 * s), anchor: .center)
        }
        .drawingGroup()
    }

    // Page — 커뮤니티: 겹쳐진 사진 카드 + 하트(좋아요) + 떠다니는 하트. 익명 사진 피드 축 표현.
    private var illustrationCommunity: some View {
        Canvas { ctx, size in
            let s = size.width / 200.0
            // 뒤 카드(살짝 어긋난 두 번째 게시물).
            ctx.fill(Path(roundedRect: CGRect(x: 62 * s, y: 40 * s, width: 88 * s, height: 108 * s), cornerRadius: 10 * s),
                     with: .color(AppColors.accent100))
            // 앞 카드(흰 배경 + 테두리).
            let front = CGRect(x: 48 * s, y: 54 * s, width: 96 * s, height: 116 * s)
            ctx.fill(Path(roundedRect: front, cornerRadius: 10 * s), with: .color(.white))
            ctx.stroke(Path(roundedRect: front, cornerRadius: 10 * s), with: .color(AppColors.rule), lineWidth: 1)
            // 사진 영역(상단) + 시계 실루엣 느낌 원.
            ctx.fill(Path(roundedRect: CGRect(x: 48 * s, y: 54 * s, width: 96 * s, height: 72 * s), cornerRadius: 10 * s),
                     with: .color(AppColors.primary500.opacity(0.16)))
            ctx.fill(Path(ellipseIn: CGRect(x: (96 - 17) * s, y: (90 - 17) * s, width: 34 * s, height: 34 * s)),
                     with: .color(AppColors.accent.opacity(0.55)))
            // 하단 — 하트(좋아요) + 캡션 라인.
            ctx.fill(heartPath(center: CGPoint(x: 64 * s, y: 144 * s), size: 12 * s), with: .color(AppColors.danger))
            var caption = Path()
            caption.move(to: CGPoint(x: 84 * s, y: 144 * s)); caption.addLine(to: CGPoint(x: 130 * s, y: 144 * s))
            ctx.stroke(caption, with: .color(AppColors.rule), lineWidth: 2.5 * s)
            // 떠다니는 작은 하트(골드).
            ctx.fill(heartPath(center: CGPoint(x: 150 * s, y: 58 * s), size: 9 * s), with: .color(AppColors.accent))
            // 라벨.
            let label = Text(String(localized: "welcome.illustration.community"))
                .font(.system(size: 12 * s, weight: .medium))
                .foregroundColor(AppColors.ink0)
            ctx.draw(label, at: CGPoint(x: 100 * s, y: 184 * s), anchor: .center)
        }
        .drawingGroup()
    }

    /// 하트 path — 두 원(위) + 삼각(아래). 작은 일러스트용 근사.
    private func heartPath(center c: CGPoint, size r: CGFloat) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.62, width: r, height: r))
        p.addEllipse(in: CGRect(x: c.x, y: c.y - r * 0.62, width: r, height: r))
        p.move(to: CGPoint(x: c.x - r * 0.92, y: c.y + r * 0.02))
        p.addLine(to: CGPoint(x: c.x + r * 0.92, y: c.y + r * 0.02))
        p.addLine(to: CGPoint(x: c.x, y: c.y + r * 1.08))
        p.closeSubpath()
        return p
    }

    /// 4-point star path (sparkle).
    private func starPath(center: CGPoint, radius: CGFloat) -> Path {
        var p = Path()
        let inner = radius * 0.3
        let points: [(Double, Double)] = [
            (0, -1),    (0.3, -0.3),
            (1, 0),     (0.3, 0.3),
            (0, 1),     (-0.3, 0.3),
            (-1, 0),    (-0.3, -0.3),
        ]
        for (i, pt) in points.enumerated() {
            let r = i % 2 == 0 ? radius : inner
            let x = center.x + r * CGFloat(pt.0)
            let y = center.y + r * CGFloat(pt.1)
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
        return p
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
