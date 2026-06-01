import XCTest
@testable import WatchAccuracyPro

/// CommunityService JWT 정적 헬퍼 — 만료/익명/페이로드 디코드. 네트워크 없음.
/// CommunityService 가 @MainActor 라 정적 멤버 접근도 MainActor — 테스트도 MainActor 로.
@MainActor
final class CommunityJWTTests: XCTestCase {

    /// 테스트용 JWT 생성(header.payload.sig, base64url, 패딩 제거).
    private func makeJWT(_ payload: [String: Any]) -> String {
        func b64url(_ d: Data) -> String {
            d.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = b64url(Data("{}".utf8))
        let body = b64url(try! JSONSerialization.data(withJSONObject: payload))
        return "\(header).\(body).sig"
    }

    func test_not_expired_for_future_exp() {
        let jwt = makeJWT(["exp": Date().timeIntervalSince1970 + 3600])
        XCTAssertFalse(CommunityService.isJWTExpired(jwt))
    }

    func test_expired_for_past_exp() {
        let jwt = makeJWT(["exp": Date().timeIntervalSince1970 - 3600])
        XCTAssertTrue(CommunityService.isJWTExpired(jwt))
    }

    func test_expired_within_60s_buffer() {
        // exp 가 30초 후 → 60초 버퍼 안 → 만료로 간주.
        let jwt = makeJWT(["exp": Date().timeIntervalSince1970 + 30])
        XCTAssertTrue(CommunityService.isJWTExpired(jwt))
    }

    func test_malformed_jwt_treated_expired() {
        XCTAssertTrue(CommunityService.isJWTExpired("not-a-jwt"))
        XCTAssertTrue(CommunityService.isJWTExpired("only.two"))
    }

    func test_missing_exp_treated_expired() {
        let jwt = makeJWT(["sub": "abc"])
        XCTAssertTrue(CommunityService.isJWTExpired(jwt))
    }

    func test_decode_payload() {
        let jwt = makeJWT(["sub": "user-123", "is_anonymous": true])
        let payload = CommunityService.decodeJWTPayload(jwt)
        XCTAssertEqual(payload?["sub"] as? String, "user-123")
        XCTAssertNil(CommunityService.decodeJWTPayload("garbage"))
    }

    func test_is_anonymous() {
        XCTAssertTrue(CommunityService.isAnonymousJWT(makeJWT(["is_anonymous": true])))
        XCTAssertFalse(CommunityService.isAnonymousJWT(makeJWT(["is_anonymous": false])))
        XCTAssertFalse(CommunityService.isAnonymousJWT(makeJWT(["sub": "x"])))  // 클레임 없으면 false
    }
}
