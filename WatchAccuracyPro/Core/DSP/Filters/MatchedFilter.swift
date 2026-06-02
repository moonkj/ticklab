import Foundation

/// 캘리버 family 별 신호경로 프로파일 dispatch — escapement + bph 기반.
/// BandPassSpec.spec(for:escapement:) 의 single source of truth (밴드패스 설정에 사용).
enum MatchedFilterProfile: Equatable {
    case bypass                               // coAxial / springDrive / quartz / detent
    case vintage18k                           // 18000 BPH swissLever (ETA 2750 등)
    case swissLever21600                      // ETA 2824, SW200 vintage
    case swissLever28800Classic               // ETA 2892, Rolex 3135, IWC 35111 (Round 156: Modern 통합)
    case highBeat36000                        // Zenith El Primero, GS 9S86

    var centerFrequencyHz: Double? {
        switch self {
        case .bypass: return nil
        case .vintage18k: return 4_000
        case .swissLever21600: return 5_000
        case .swissLever28800Classic: return 5_800
        case .highBeat36000: return 7_500
        }
    }
    var durationMs: Double? {
        switch self {
        case .bypass: return nil
        case .vintage18k: return 9.0
        case .swissLever21600: return 6.0
        case .swissLever28800Classic: return 5.0
        case .highBeat36000: return 3.5
        }
    }

    /// escapement + bph → profile. 안 맞으면 .bypass (Round 37 회피).
    /// Round 156 (Hyemi #4 fix): swissLever28800Modern 는 resolve 에서 도달 불가능한 dead path 였음
    /// (25_200..<31_500 → Classic 만 반환). 향후 composite Gabor template 도입 시 별도 함수로 분리하여 추가 예정.
    static func resolve(escapement: Escapement, bph: Int) -> MatchedFilterProfile {
        switch escapement {
        case .coAxial, .springDrive, .quartz, .detentEscapement:
            return .bypass
        case .swissLever, .siliconEscapement:
            switch bph {
            case ..<19_800: return .vintage18k
            case 19_800..<25_200: return .swissLever21600
            case 25_200..<31_500: return .swissLever28800Classic
            case 31_500...: return .highBeat36000
            default: return .bypass
            }
        }
    }
}
