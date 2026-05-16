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
            ZStack {
                Circle()
                    .fill(AppColors.paper1)
                    .frame(width: 72, height: 72)
                    .overlay(Circle().stroke(AppColors.rule, lineWidth: 1))
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(AppColors.ink2)
            }
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
