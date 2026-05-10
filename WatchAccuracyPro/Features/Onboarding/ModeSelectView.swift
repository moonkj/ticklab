import SwiftUI

struct ModeSelectView: View {
    @Environment(UserPreferences.self) private var preferences
    let onSelect: (UserMode) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(String(localized: "mode.select.title"))
                .font(AppTypography.title)
                .padding(.top, 32)
            Text(String(localized: "mode.select.subtitle"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                ModeCard(
                    icon: "leaf.fill",
                    title: String(localized: "mode.beginner.title"),
                    subtitle: String(localized: "mode.beginner.subtitle"),
                    isSelected: preferences.userMode == .beginner
                ) { onSelect(.beginner) }

                ModeCard(
                    icon: "wrench.and.screwdriver.fill",
                    title: String(localized: "mode.expert.title"),
                    subtitle: String(localized: "mode.expert.subtitle"),
                    isSelected: preferences.userMode == .expert
                ) { onSelect(.expert) }
            }
            .padding(.horizontal, 16)

            Spacer()
        }
    }
}

private struct ModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(AppTypography.headline)
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.primary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? AppColors.primary : .clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ModeSelectView(onSelect: { _ in })
        .environment(UserPreferences())
}
