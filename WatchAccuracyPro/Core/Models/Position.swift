import Foundation

enum Position: String, Codable, CaseIterable, Sendable {
    case dialUp     = "DU"
    case dialDown   = "DD"
    case crownUp    = "CU"
    case crownDown  = "CD"
    case crownLeft  = "PL"
    case crownRight = "PR"
    case unknown    = "UNKNOWN"

    var localizedName: String {
        switch self {
        case .dialUp:     return String(localized: "position.dial_up")
        case .dialDown:   return String(localized: "position.dial_down")
        case .crownUp:    return String(localized: "position.crown_up")
        case .crownDown:  return String(localized: "position.crown_down")
        case .crownLeft:  return String(localized: "position.crown_left")
        case .crownRight: return String(localized: "position.crown_right")
        case .unknown:    return String(localized: "position.unknown")
        }
    }
}
