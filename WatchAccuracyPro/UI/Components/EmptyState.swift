import SwiftUI

/// 풀페이지 빈 상태 컴포넌트 — Circle icon + serif title + body + 선택적 CTA.
/// 사용처: CollectionView, JournalFeedView, BrandLeagueView, BadgesView (filter empty)
struct EmptyState: View {
    let icon: String          // SF Symbol name
    let title: String
    let message: String?
    var cta: CTAConfig? = nil

    init(icon: String, title: String, message: String? = nil, cta: CTAConfig? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.cta = cta
    }

    struct CTAConfig {
        let label: String
        let action: () -> Void
    }

    var body: some View {
        VStack(spacing: 14) {
            // Sprint 8 (UX): 애니메이션 시계 아이콘 — Reduce Motion 시 정적 아이콘
            AnimatedEmptyIcon(icon: icon)
            Text(title)
                .font(.system(size: 22, weight: .medium, design: .serif))
                .italic()
                .foregroundStyle(AppColors.ink0)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            if let cta {
                Button(action: cta.action) {
                    Text(cta.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .frame(minHeight: 44)
                        .background(AppColors.primaryDeep)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.vertical, 60)
        .padding(.horizontal, 24)
    }
}

/// 웨이브2-D: 빈 상태 메달리온 — DotRingMark(12-dot 시계 인덱스) 기반 브랜드 메달.
/// 중앙 SF Symbol 유지. 아주 느린 회전(Reduce Motion 시 정적). 이름은 호환 위해 유지.
struct AnimatedEmptyIcon: View {
    let icon: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // 메달 본체 — paper1 + hairline + 얕은 그림자.
            Circle()
                .fill(AppColors.paper1)
                .frame(width: 84, height: 84)
                .overlay(Circle().stroke(AppColors.rule, lineWidth: 1))
                .cardShadow(.low)
            // 은은한 골드 ambient.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.accent.opacity(0.14), .clear],
                        center: .center, startRadius: 0, endRadius: 48
                    )
                )
                .frame(width: 96, height: 96)
            // 12-dot 시계 인덱스 — Reduce Motion 시 정적.
            DotRingMark(size: 72, rotating: !reduceMotion, goldTopDot: true)
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(AppColors.ink2)
                // 아이콘 자체도 살짝 맥동(Reduce Motion 시 정지).
                .symbolEffect(.pulse.wholeSymbol, isActive: !reduceMotion)
        }
    }
}

/// 인라인 로딩 링 — AnimatedEmptyIcon 과 동일한 회전 accent 링 스타일(작게).
/// 툴바/버튼/오버레이 등 좁은 자리의 로딩 표시용(기본 ProgressView 대체).
struct LoadingRing: View {
    var size: CGFloat = 22
    var color: Color = AppColors.accent
    var lineWidth: CGFloat = 2.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { angle = 360 }
            }
    }
}

/// 인라인 (카드 내부) 빈 상태 — 작은 SF symbol + 한 줄 텍스트.
struct InlineEmptyState: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(AppColors.ink3)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.ink3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

#Preview("Full Empty") {
    EmptyState(
        icon: "tray",
        title: "No data yet",
        message: "Start measuring to see your history.",
        cta: .init(label: "Get started") { }
    )
    .background(AppColors.paper0)
}

#Preview("Inline Empty") {
    InlineEmptyState(icon: "chart.line.uptrend.xyaxis", text: "Not enough data yet")
        .padding()
        .background(AppColors.paper1)
}
