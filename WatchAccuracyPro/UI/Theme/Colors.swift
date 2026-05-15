import SwiftUI

/// TickLab v3 design tokens — Pivot Addendum 적용.
/// - Surface: warm white linen base (#FAFAF7)
/// - Primary: Deep Indigo (#1A1B2E) — 짙은 시계 다이얼 톤
/// - Accent: Antique Gold (#C9A961) — 럭셔리 시계 시그니처
/// - Ink: charcoal (#29261B)
enum AppColors {
    // MARK: - Paper / Surface (배경 계층) — styles.css SSOT
    /// Surface warm (linen). Main bg.
    static let paper0  = Color(red: 0.980, green: 0.980, blue: 0.969)   // #FAFAF7
    /// Surface elevated (cards, modals).
    static let paper1  = Color(red: 1.000, green: 1.000, blue: 1.000)   // #FFFFFF
    /// Surface cool (sections, muted bg).
    static let paper2  = Color(red: 0.969, green: 0.973, blue: 0.980)   // #F7F8FA
    /// Border — gray-200.
    static let rule    = Color(red: 0.898, green: 0.898, blue: 0.898)   // #E5E5E5
    static let ruleStrong = Color(red: 0.831, green: 0.831, blue: 0.831) // #D4D4D4 (gray-300)

    // MARK: - Ink (text) — Round 129 가독성 향상 (사용자 보고: 폰트 안 보임).
    /// Main text — Deep Indigo (= primary-900).
    static let ink0    = Color(red: 0.102, green: 0.106, blue: 0.180) // #1A1B2E
    static let ink1    = Color(red: 0.165, green: 0.173, blue: 0.310) // #2A2C4F (primary-700)
    /// Secondary — gray-700 (이전 gray-600 #525252 → #404040 으로 진하게).
    static let ink2    = Color(red: 0.251, green: 0.251, blue: 0.251) // #404040 (gray-700)
    /// Tertiary — gray-500 (이전 gray-400 #A3A3A3 → #737373 으로 진하게).
    static let ink3    = Color(red: 0.451, green: 0.451, blue: 0.451) // #737373 (gray-500)

    // MARK: - Accent — Antique Gold (v3 brand signature)
    static let accent      = Color(red: 0.788, green: 0.663, blue: 0.380)  // #C9A961 (accent-500)
    static let accentDark  = Color(red: 0.627, green: 0.533, blue: 0.259)  // #A08842 (accent-700)
    static let accentLight = Color(red: 0.878, green: 0.773, blue: 0.537)  // #E0C589 (accent-300)
    static let accent50    = Color(red: 0.980, green: 0.965, blue: 0.910)  // #FAF6E8
    static let accent100   = Color(red: 0.949, green: 0.918, blue: 0.784)  // #F2EAC8
    static let accentTint  = accent.opacity(0.10)

    // MARK: - Primary — Deep Indigo
    static let primaryDeep = Color(red: 0.102, green: 0.106, blue: 0.180)  // #1A1B2E (primary-900)
    static let primary700  = Color(red: 0.165, green: 0.173, blue: 0.310)  // #2A2C4F
    static let primary500  = Color(red: 0.239, green: 0.247, blue: 0.431)  // #3D3F6E

    // MARK: - Status
    static let success     = Color(red: 0.176, green: 0.478, blue: 0.310) // #2D7A4F
    static let successTint = success.opacity(0.12)
    static let warning     = Color(red: 0.780, green: 0.490, blue: 0.184) // #C77D2F
    static let warningTint = warning.opacity(0.14)
    static let danger      = Color(red: 0.710, green: 0.212, blue: 0.227) // #B5363A
    static let dangerTint  = danger.opacity(0.12)
    static let info        = Color(red: 0.239, green: 0.478, blue: 0.722) // #3D7AB8

    // MARK: - Dark mode (Phase 2 placeholder)
    static let surfaceNight = Color(red: 0.059, green: 0.067, blue: 0.094) // #0F1118

    // MARK: - Semantic aliases (기존 코드 호환 — 점진 제거 예정)
    static let primary       = accent        // 기존 코드의 "primary" = brand color = 이제 gold
    static let secondary     = ink2
    static let background    = paper0
    static let surface       = paper1
    static let textPrimary   = ink0
    static let textSecondary = ink2
    static let textMuted     = ink3
    static let border        = rule
}

// MARK: - Radius tokens

enum AppRadius {
    static let pill: CGFloat = 999
    static let xs: CGFloat = 8
    static let sm: CGFloat = 10
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

// MARK: - Shadow tokens

enum AppShadow {
    /// Card subtle shadow.
    static let cardX: CGFloat = 0
    static let cardY: CGFloat = 2
    static let cardBlur: CGFloat = 8
    static let cardOpacity: Double = 0.04

    /// Modal / overlay shadow.
    static let modalX: CGFloat = 0
    static let modalY: CGFloat = 30
    static let modalBlur: CGFloat = 60
    static let modalOpacity: Double = 0.50
}
