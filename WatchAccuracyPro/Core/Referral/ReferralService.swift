import Foundation
import UIKit

/// Sprint 6 (P2-20): 친구 초대 레퍼럴 서비스.
/// Branch.io 없이 자체 딥링크 구현. App Store 링크 + 사용자 코드 파라미터.
/// 보상 처리는 Phase 2 서버 연동 시 추가 (현재 단계: 공유 링크 생성만).
enum ReferralService {
    private static let appStoreURL = "https://apps.apple.com/app/ticklab/id6741730681"
    private static let codeKey = "ticklab.referral.code"

    /// Sprint 14 (B1, R4): IDFV는 재설치 시 변경 → 최초 1회 생성 후 UserDefaults에 영구 저장.
    /// 보상 추적이 코드 일관성에 의존하므로 안정적 식별자 필요.
    static var referralCode: String {
        if let saved = UserDefaults.standard.string(forKey: codeKey), !saved.isEmpty {
            return saved
        }
        // 최초 생성 — IDFV 기반 8자, 없으면 랜덤.
        let raw = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let code = String(raw.replacingOccurrences(of: "-", with: "").prefix(8).uppercased())
        UserDefaults.standard.set(code, forKey: codeKey)
        return code
    }

    /// 공유 링크 — App Store URL + 레퍼럴 파라미터.
    static var shareURL: URL {
        URL(string: "\(appStoreURL)?referral=\(referralCode)") ?? URL(string: appStoreURL)!
    }

    /// UIActivityViewController 공유 아이템. (B1: 하드코드 → l10n)
    static var shareItems: [Any] {
        let message = String(format: NSLocalizedString("referral.share.full_message", comment: ""),
                             shareURL.absoluteString, referralCode)
        return [message]
    }
}
