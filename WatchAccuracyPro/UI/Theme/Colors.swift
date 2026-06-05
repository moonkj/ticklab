import SwiftUI
import UIKit

/// TickLab v3 design tokens — Pivot Addendum 적용.
/// - Surface: warm white linen base (#FAFAF7)
/// - Primary: Deep Indigo (#1A1B2E) — 짙은 시계 다이얼 톤
/// - Accent: Antique Gold (#C9A961) — 럭셔리 시계 시그니처
/// - Ink: charcoal (#29261B)
enum AppColors {
    // MARK: - Adaptive helper
    /// light/dark 적응형 토큰 빌더. 호출부는 여전히 `Color` 를 받는다(API 시그니처 유지).
    /// `tc.userInterfaceStyle == .dark` 일 때 night 팔레트, 아니면 기존 light 값.
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { tc in tc.userInterfaceStyle == .dark ? dark : light })
    }

    // MARK: - Paper / Surface (배경 계층) — styles.css SSOT (light) + 밤의 워치 (dark)
    /// Surface warm (linen). Main bg. dark=#0F1118 (deep indigo/charcoal).
    static let paper0  = dynamic(
        light: UIColor(red: 0.980, green: 0.980, blue: 0.969, alpha: 1),  // #FAFAF7
        dark:  UIColor(red: 0.059, green: 0.067, blue: 0.094, alpha: 1))  // #0F1118
    /// Surface elevated (cards, modals). dark=#171922.
    static let paper1  = dynamic(
        light: UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1),  // #FFFFFF
        dark:  UIColor(red: 0.090, green: 0.098, blue: 0.133, alpha: 1))  // #171922
    /// Surface cool (sections, muted bg). dark=#1F2230.
    static let paper2  = dynamic(
        light: UIColor(red: 0.969, green: 0.973, blue: 0.980, alpha: 1),  // #F7F8FA
        dark:  UIColor(red: 0.122, green: 0.133, blue: 0.188, alpha: 1))  // #1F2230
    /// Border — gray-200 (light) / #2C3040 (dark).
    static let rule    = dynamic(
        light: UIColor(red: 0.898, green: 0.898, blue: 0.898, alpha: 1),  // #E5E5E5
        dark:  UIColor(red: 0.173, green: 0.188, blue: 0.251, alpha: 1))  // #2C3040
    /// gray-300 (light) / #3A3F52 (dark).
    static let ruleStrong = dynamic(
        light: UIColor(red: 0.831, green: 0.831, blue: 0.831, alpha: 1),  // #D4D4D4
        dark:  UIColor(red: 0.227, green: 0.247, blue: 0.322, alpha: 1))  // #3A3F52

    // MARK: - Ink (text) — Round 129 가독성 향상. dark 는 밝게 반전.
    /// Main text — Deep Indigo (light) / near-white #F2F2F7 (dark).
    static let ink0    = dynamic(
        light: UIColor(red: 0.102, green: 0.106, blue: 0.180, alpha: 1),  // #1A1B2E
        dark:  UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1))  // #F2F2F7
    /// primary-700 (light) / #D6D8E5 (dark).
    static let ink1    = dynamic(
        light: UIColor(red: 0.165, green: 0.173, blue: 0.310, alpha: 1),  // #2A2C4F
        dark:  UIColor(red: 0.839, green: 0.847, blue: 0.898, alpha: 1))  // #D6D8E5
    /// Secondary — gray-700 (light) / #AEB2C2 (dark).
    static let ink2    = dynamic(
        light: UIColor(red: 0.251, green: 0.251, blue: 0.251, alpha: 1),  // #404040
        dark:  UIColor(red: 0.682, green: 0.698, blue: 0.761, alpha: 1))  // #AEB2C2
    /// Tertiary — gray-500 (light) / #7E8295 (dark).
    static let ink3    = dynamic(
        light: UIColor(red: 0.451, green: 0.451, blue: 0.451, alpha: 1),  // #737373
        dark:  UIColor(red: 0.494, green: 0.510, blue: 0.584, alpha: 1))  // #7E8295

    // MARK: - Accent — Antique Gold (v3 brand signature). dark 은 약간 밝게.
    static let accent      = dynamic(
        light: UIColor(red: 0.788, green: 0.663, blue: 0.380, alpha: 1),  // #C9A961 (accent-500)
        dark:  UIColor(red: 0.847, green: 0.725, blue: 0.451, alpha: 1))  // #D8B973 (밝은 gold)
    static let accentDark  = dynamic(
        light: UIColor(red: 0.627, green: 0.533, blue: 0.259, alpha: 1),  // #A08842 (accent-700)
        dark:  UIColor(red: 0.788, green: 0.663, blue: 0.380, alpha: 1))  // #C9A961 (dark 에선 한 단계 밝게)
    static let accentLight = dynamic(
        light: UIColor(red: 0.878, green: 0.773, blue: 0.537, alpha: 1),  // #E0C589 (accent-300)
        dark:  UIColor(red: 0.910, green: 0.820, blue: 0.604, alpha: 1))  // #E8D19A
    /// 옅은 accent 배경 — dark 에선 어두운 gold-tinted surface 로.
    static let accent50    = dynamic(
        light: UIColor(red: 0.980, green: 0.965, blue: 0.910, alpha: 1),  // #FAF6E8
        dark:  UIColor(red: 0.149, green: 0.137, blue: 0.090, alpha: 1))  // #262317
    static let accent100   = dynamic(
        light: UIColor(red: 0.949, green: 0.918, blue: 0.784, alpha: 1),  // #F2EAC8
        dark:  UIColor(red: 0.196, green: 0.176, blue: 0.110, alpha: 1))  // #322D1C
    static let accentTint  = accent.opacity(0.10)

    // MARK: - Primary — Deep Indigo. dark 에선 약간 밝은 indigo surface 로 띄움.
    static let primaryDeep = dynamic(
        light: UIColor(red: 0.102, green: 0.106, blue: 0.180, alpha: 1),  // #1A1B2E (primary-900)
        dark:  UIColor(red: 0.149, green: 0.157, blue: 0.243, alpha: 1))  // #26283E
    static let primary700  = dynamic(
        light: UIColor(red: 0.165, green: 0.173, blue: 0.310, alpha: 1),  // #2A2C4F
        dark:  UIColor(red: 0.220, green: 0.231, blue: 0.376, alpha: 1))  // #383B60
    static let primary500  = dynamic(
        light: UIColor(red: 0.239, green: 0.247, blue: 0.431, alpha: 1),  // #3D3F6E
        dark:  UIColor(red: 0.314, green: 0.325, blue: 0.529, alpha: 1))  // #505387

    // MARK: - Status. dark 은 채도/명도 올려 어두운 배경 위 가독성 확보.
    static let success     = dynamic(
        light: UIColor(red: 0.176, green: 0.478, blue: 0.310, alpha: 1),  // #2D7A4F
        dark:  UIColor(red: 0.349, green: 0.733, blue: 0.510, alpha: 1))  // #59BB82
    static let successTint = success.opacity(0.12)
    static let warning     = dynamic(
        light: UIColor(red: 0.780, green: 0.490, blue: 0.184, alpha: 1),  // #C77D2F
        dark:  UIColor(red: 0.918, green: 0.659, blue: 0.353, alpha: 1))  // #EAA85A
    static let warningTint = warning.opacity(0.14)
    static let danger      = dynamic(
        light: UIColor(red: 0.710, green: 0.212, blue: 0.227, alpha: 1),  // #B5363A
        dark:  UIColor(red: 0.910, green: 0.420, blue: 0.435, alpha: 1))  // #E86B6F
    static let dangerTint  = danger.opacity(0.12)
    static let info        = dynamic(
        light: UIColor(red: 0.239, green: 0.478, blue: 0.722, alpha: 1),  // #3D7AB8
        dark:  UIColor(red: 0.404, green: 0.624, blue: 0.871, alpha: 1))  // #679FDE

    // MARK: - Interactive tint (전역 .tint — 링크·ShareLink·Picker 값·NavigationLink chevron·선택 탭)
    /// light=deep indigo(흰 배경에서 또렷·alert 가독), dark=bright gold(어두운 배경에서 또렷·브랜드 accent).
    /// RootTabView 의 `.tint(...)` 가 앱 전역으로 전파되므로 다크모드 가독성의 단일 진실원.
    static let interactiveTint = dynamic(
        light: UIColor(red: 0.102, green: 0.106, blue: 0.180, alpha: 1),  // #1A1B2E (deep indigo)
        dark:  UIColor(red: 0.847, green: 0.725, blue: 0.451, alpha: 1))  // #D8B973 (bright gold)

    // MARK: - Dark mode surface (night, 비적응 — 항상 딥 인디고)
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

// MARK: - Shadow tokens (Sprint 9 UX)

import SwiftUI

/// 2겹 그림자(contact + ambient)로 깊이감을 부여하는 카드 그림자.
/// - **API 호환**: `level` / `Level(.low/.mid/.high)` 와 `cardShadow(_:)` 시그니처는
///   기존과 동일. 내부만 단겹 → 2겹(가까운 contact + 먼 ambient)으로 승급해
///   기존 모든 호출부가 무수정으로 더 깊고 부드러운 그림자를 받는다.
struct CardShadow: ViewModifier {
    var level: Level
    enum Level { case low, mid, high }

    func body(content: Content) -> some View {
        switch level {
        case .low:
            content
                .shadow(color: .black.opacity(0.05), radius: 3,  x: 0, y: 1)   // contact
                .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 6)   // ambient
        case .mid:
            content
                .shadow(color: .black.opacity(0.06), radius: 3,  x: 0, y: 1)   // contact
                .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 10)  // ambient
        case .high:
            content
                .shadow(color: .black.opacity(0.08), radius: 4,  x: 0, y: 2)   // contact
                .shadow(color: .black.opacity(0.12), radius: 28, x: 0, y: 16)  // ambient
        }
    }
}

extension View {
    func cardShadow(_ level: CardShadow.Level = .low) -> some View {
        modifier(CardShadow(level: level))
    }
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
