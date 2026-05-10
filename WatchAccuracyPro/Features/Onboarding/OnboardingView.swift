import SwiftUI

struct OnboardingView: View {
    @State private var page: Int = 0
    let onComplete: () -> Void

    private let pages: [Page] = [
        .init(icon: "stopwatch", title: String(localized: "onboarding.page1.title"), body: String(localized: "onboarding.page1.body")),
        .init(icon: "waveform", title: String(localized: "onboarding.page2.title"), body: String(localized: "onboarding.page2.body")),
        .init(icon: "globe", title: String(localized: "onboarding.page3.title"), body: String(localized: "onboarding.page3.body"))
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { idx in
                    OnboardingPageView(page: pages[idx])
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            PrimaryButton(
                page == pages.count - 1
                    ? String(localized: "onboarding.cta.start")
                    : String(localized: "onboarding.cta.next")
            ) {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onComplete()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

private struct Page: Identifiable {
    let icon: String
    let title: String
    let body: String
    var id: String { title }
}

private struct OnboardingPageView: View {
    let page: Page

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: page.icon)
                .font(.system(size: 88, weight: .light))
                .foregroundStyle(AppColors.primary)
            Text(page.title)
                .font(AppTypography.largeTitle)
                .multilineTextAlignment(.center)
            Text(page.body)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
