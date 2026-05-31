import Foundation
import StoreKit
import SwiftUI
import UIKit

/// Sprint 1 (P1-6): 스마트 리뷰 요청 — 2단계 필터.
///
/// Apple SKStoreReviewController.requestReview 정책:
///   - 365일 내 최대 3회 노출 (시스템 강제)
///   - 사용자가 어떤 별점 줬는지 앱은 모름
///
/// 본 서비스의 추가 정책:
///   - 골든 모멘트(측정 ≥3회 + 신뢰도 ≥80%, 또는 시계 등록 ≥3개) 진입 시에만 트리거
///   - 마지막 요청 후 최소 60일 경과 (cooldown)
///   - 사용자가 한 번 트리거된 세션에서는 다시 요청하지 않음 (UserDefaults flag)
///
/// 호출 측은 골든 모멘트마다 `requestReviewIfAppropriate(from:)` 만 호출 — 내부 필터가 결정.
@MainActor
enum ReviewRequestService {
    private static let lastRequestKey = "ticklab.review.lastRequest"
    private static let cumulativeQualifyingMomentsKey = "ticklab.review.qualifyingMoments"
    private static let cooldownDays: TimeInterval = 60 * 24 * 60 * 60

    /// 골든 모멘트 발생 시 호출. 본 함수는 정책 평가만 — 실제 노출은 시스템이 결정.
    /// `qualifyingMomentReached` 호출 카운트를 기준으로 임계 도달 시 1회 요청.
    static func qualifyingMomentReached(threshold: Int = 3) {
        let count = UserDefaults.standard.integer(forKey: cumulativeQualifyingMomentsKey) + 1
        UserDefaults.standard.set(count, forKey: cumulativeQualifyingMomentsKey)
        guard count >= threshold else { return }
        guard shouldRequest() else { return }
        request()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastRequestKey)
        UserDefaults.standard.set(0, forKey: cumulativeQualifyingMomentsKey)
    }

    private static func shouldRequest() -> Bool {
        let last = UserDefaults.standard.double(forKey: lastRequestKey)
        guard last > 0 else { return true }
        let elapsed = Date().timeIntervalSince1970 - last
        return elapsed >= cooldownDays
    }

    private static func request() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        AppStore.requestReview(in: scene)
    }
}
