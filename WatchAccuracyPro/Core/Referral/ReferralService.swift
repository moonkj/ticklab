import Foundation
import UIKit

/// Sprint 6 (P2-20): 친구 초대 레퍼럴 서비스.
/// Branch.io 없이 자체 딥링크 구현. App Store 링크 + 사용자 코드 파라미터.
/// 보상 처리는 Phase 2 서버 연동 시 추가 (현재 단계: 공유 링크 생성만).
enum ReferralService {
    private static let appStoreURL = "https://apps.apple.com/app/ticklab/id6741730681"

    /// 사용자별 고유 레퍼럴 코드 — device hash 첫 8자.
    static var referralCode: String {
        let raw = UIDevice.current.identifierForVendor?.uuidString ?? "TICKLAB"
        return String(raw.replacingOccurrences(of: "-", with: "").prefix(8).uppercased())
    }

    /// 공유 링크 — App Store URL + 레퍼럴 파라미터.
    static var shareURL: URL {
        let code = referralCode
        return URL(string: "\(appStoreURL)?referral=\(code)") ?? URL(string: appStoreURL)!
    }

    /// UIActivityViewController 공유 아이템.
    static var shareItems: [Any] {
        let message = "TickLab — 내 시계의 모든 기록 📱\n\(shareURL.absoluteString)\n초대 코드: \(referralCode)"
        return [message]
    }
}
