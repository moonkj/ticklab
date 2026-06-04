import SwiftUI

/// 시계 보관함 색상 팔레트 (v1.1.1).
/// 기존 마감재 4종 + 신규 4종. 설정(UserPreferences.watchBoxColor)에서 선택, 보관함 전역 적용.
/// 외함/받침대 그라디언트를 색상별로 정의해 3D 보관함 룩을 유지한다.
enum WatchBoxColor: String, CaseIterable, Identifiable {
    case walnut, ebony, leather, linen     // 기존
    case navy, burgundy, forest, graphite  // 신규

    var id: String { rawValue }

    var label: String {
        switch self {
        // 기존 4종은 이미 8개국어 번역된 watchbox.material.* 키 재사용.
        case .walnut:   return String(localized: "watchbox.material.walnut")
        case .ebony:    return String(localized: "watchbox.material.ebony")
        case .leather:  return String(localized: "watchbox.material.leather")
        case .linen:    return String(localized: "watchbox.material.linen")
        case .navy:     return String(localized: "watchbox.color.navy")
        case .burgundy: return String(localized: "watchbox.color.burgundy")
        case .forest:   return String(localized: "watchbox.color.forest")
        case .graphite: return String(localized: "watchbox.color.graphite")
        }
    }

    /// 외함 색상 (3색 LinearGradient).
    var outerColors: [Color] {
        switch self {
        case .walnut:   return [Color(red: 0.36, green: 0.23, blue: 0.12),
                                Color(red: 0.55, green: 0.35, blue: 0.17),
                                Color(red: 0.29, green: 0.17, blue: 0.09)]
        case .ebony:    return [Color(red: 0.102, green: 0.106, blue: 0.180),
                                Color(red: 0.165, green: 0.133, blue: 0.200),
                                Color(red: 0.059, green: 0.059, blue: 0.102)]
        case .leather:  return [Color(red: 0.227, green: 0.122, blue: 0.071),
                                Color(red: 0.361, green: 0.180, blue: 0.102),
                                Color(red: 0.165, green: 0.071, blue: 0.031)]
        case .linen:    return [Color(red: 0.910, green: 0.863, blue: 0.753),
                                Color(red: 0.949, green: 0.922, blue: 0.851),
                                Color(red: 0.788, green: 0.725, blue: 0.549)]
        case .navy:     return [Color(red: 0.13, green: 0.16, blue: 0.30),
                                Color(red: 0.20, green: 0.25, blue: 0.42),
                                Color(red: 0.09, green: 0.11, blue: 0.22)]
        case .burgundy: return [Color(red: 0.32, green: 0.10, blue: 0.13),
                                Color(red: 0.46, green: 0.16, blue: 0.20),
                                Color(red: 0.24, green: 0.07, blue: 0.10)]
        case .forest:   return [Color(red: 0.12, green: 0.24, blue: 0.16),
                                Color(red: 0.18, green: 0.34, blue: 0.22),
                                Color(red: 0.08, green: 0.17, blue: 0.11)]
        case .graphite: return [Color(red: 0.20, green: 0.21, blue: 0.23),
                                Color(red: 0.30, green: 0.31, blue: 0.33),
                                Color(red: 0.14, green: 0.15, blue: 0.16)]
        }
    }

    /// 받침대(pillow) 색상.
    var pillowColors: (top: Color, bottom: Color) {
        switch self {
        case .walnut:   return (Color(red: 0.165, green: 0.129, blue: 0.102), Color(red: 0.059, green: 0.039, blue: 0.024))
        case .ebony:    return (Color(red: 0.122, green: 0.137, blue: 0.188), Color(red: 0.031, green: 0.039, blue: 0.063))
        case .leather:  return (Color(red: 0.231, green: 0.141, blue: 0.094), Color(red: 0.078, green: 0.039, blue: 0.020))
        case .linen:    return (Color(red: 0.545, green: 0.498, blue: 0.361), Color(red: 0.290, green: 0.255, blue: 0.192))
        case .navy:     return (Color(red: 0.160, green: 0.190, blue: 0.320), Color(red: 0.055, green: 0.075, blue: 0.160))
        case .burgundy: return (Color(red: 0.240, green: 0.090, blue: 0.110), Color(red: 0.110, green: 0.035, blue: 0.050))
        case .forest:   return (Color(red: 0.110, green: 0.200, blue: 0.140), Color(red: 0.045, green: 0.095, blue: 0.065))
        case .graphite: return (Color(red: 0.180, green: 0.190, blue: 0.205), Color(red: 0.075, green: 0.080, blue: 0.090))
        }
    }

    /// 텍스트/악센트 전경색.
    var fgColor: Color {
        switch self {
        case .walnut, .leather, .burgundy, .forest: return Color(red: 0.949, green: 0.902, blue: 0.800)
        case .ebony, .navy, .graphite:              return Color(red: 0.788, green: 0.663, blue: 0.380)  // gold
        case .linen:                                 return Color(red: 0.290, green: 0.263, blue: 0.216)
        }
    }

    /// 설정 화면 스와치(대표 단색).
    var swatch: Color { outerColors[1] }

    /// 저장값 → 케이스 (불명 시 walnut).
    static func resolve(_ raw: String) -> WatchBoxColor { WatchBoxColor(rawValue: raw) ?? .walnut }
}
