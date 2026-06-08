import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 플랫폼/디바이스 능력 단일 소스. 기능별 지원 여부를 여기서만 분기해 화면 곳곳의 하드코딩을 막는다.
///
/// 측정 지원 정책:
/// - **iPhone**: 지원 (마이크를 시계에 근접시켜 이스케이프먼트 비트 측정).
/// - **iPad**: 미지원 — 폼팩터상 마이크를 시계에 붙이기 어려워 측정 정확도 확보 곤란(개발자 결정).
///   컬렉션·생활기록·분석·커뮤니티 등 나머지 기능은 전부 지원.
/// - **Apple Watch(watchOS)**: 향후 지원 예정. 아래 `supportsMeasurement` 의 `.watch` 분기만 켜면
///   되도록 설계(워치 마이크 기반 측정 + WatchConnectivity 동기화는 별도 watchOS 타깃에서 구현).
enum AppDevice {
    enum Platform { case phone, pad, watch, mac, other }

    static var platform: Platform {
        #if os(watchOS)
        return .watch
        #elseif canImport(UIKit)
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: return .phone
        case .pad:   return .pad
        case .mac:   return .mac
        default:     return .other
        }
        #else
        return .other
        #endif
    }

    var isPad: Bool { Self.platform == .pad }

    /// 마이크-근접 음향 측정 지원 플랫폼. 현재 iPhone 전용.
    /// Apple Watch 지원 착수 시 `.watch` 분기를 true 로 켜면 측정 진입이 열린다(단일 게이트).
    static var supportsMeasurement: Bool {
        switch platform {
        case .phone: return true
        // TODO(watchOS): Apple Watch 측정 지원 시 활성화 — 워치 마이크 캡처 + 결과 WatchConnectivity 동기화.
        // case .watch: return true
        default: return false
        }
    }
}

/// 로케일 인식 숫자 파싱 — `.decimalPad`/`.numberPad` 입력은 사용자 로케일 소수점 구분자(쉼표 등)를
/// 쓰므로, `Decimal(string:)`/`Double(string:)`(`.`만 인정)로 파싱하면 유럽/일부 로케일에서 값이 손상된다.
/// (예: 독일 사용자 "1.500,50" → Decimal(string:) = 1.5). NumberFormatter(current locale)로 파싱.
enum LocalizedNumber {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .current
        f.generatesDecimalNumbers = true
        return f
    }()

    static func decimal(_ raw: String) -> Decimal? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if let n = formatter.number(from: t) { return n.decimalValue }
        return Decimal(string: t)   // 폴백: POSIX('.') 형식(붙여넣기 등)
    }

    static func double(_ raw: String) -> Double? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if let n = formatter.number(from: t) { return n.doubleValue }
        return Double(t)
    }
}
