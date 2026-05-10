import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "stopwatch")
                .font(.system(size: 64))
                .foregroundStyle(AppColors.primary)
            Text(String(localized: "app.name"))
                .font(AppTypography.title)
            Text(String(localized: "onboarding.subtitle"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding()
    }
}

#Preview("ko") {
    ContentView()
        .environment(\.locale, .init(identifier: "ko"))
}

#Preview("en") {
    ContentView()
        .environment(\.locale, .init(identifier: "en"))
}
