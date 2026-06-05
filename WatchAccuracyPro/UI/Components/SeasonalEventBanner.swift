import SwiftUI

/// Sprint 5 (P3-12): 시즌 이벤트 배너.
/// FeatureFlags.seasonalEventEnabled = true 일 때만 표시.
struct SeasonalEventBanner: View {
    @StateObject private var flags = FeatureFlags.shared

    private var bannerColor: Color {
        switch flags.seasonalEventColor {
        case "gold":  return Color(red: 0.85, green: 0.70, blue: 0.22)
        case "red":   return Color(red: 0.80, green: 0.10, blue: 0.10)
        default:      return AppColors.accentDark
        }
    }

    var body: some View {
        if flags.seasonalEventEnabled && !flags.seasonalEventTitle.isEmpty {
            HStack(spacing: 10) {
                ConceptGlyph(systemName: "gift.fill", size: 14, color: .white)
                Text(flags.seasonalEventTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(bannerColor)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
