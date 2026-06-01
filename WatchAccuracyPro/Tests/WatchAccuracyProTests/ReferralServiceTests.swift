import XCTest
@testable import WatchAccuracyPro

/// ReferralService — 레퍼럴 코드(영구), 공유 URL, 공유 아이템.
/// codeKey 는 UserDefaults.standard 백킹이라 setUp 에서 정리하고 tearDown 에서 복원한다.
final class ReferralServiceTests: XCTestCase {

    private let codeKey = "ticklab.referral.code"
    private let defaults = UserDefaults.standard
    private var snapshot: Any?

    override func setUp() {
        super.setUp()
        snapshot = defaults.object(forKey: codeKey)
    }

    override func tearDown() {
        if let snapshot {
            defaults.set(snapshot, forKey: codeKey)
        } else {
            defaults.removeObject(forKey: codeKey)
        }
        snapshot = nil
        super.tearDown()
    }

    func test_referralCode_returns_saved_value_when_present() {
        defaults.set("SAVED123", forKey: codeKey)
        XCTAssertEqual(ReferralService.referralCode, "SAVED123")
    }

    func test_referralCode_is_stable_across_reads() {
        defaults.removeObject(forKey: codeKey)
        let first = ReferralService.referralCode
        let second = ReferralService.referralCode
        XCTAssertEqual(first, second, "최초 생성 후 영구 저장 → 동일 코드 반환")
        XCTAssertFalse(first.isEmpty)
    }

    func test_referralCode_generated_when_unset_is_persisted() {
        defaults.removeObject(forKey: codeKey)
        let code = ReferralService.referralCode
        XCTAssertEqual(defaults.string(forKey: codeKey), code, "생성된 코드는 UserDefaults 에 저장")
    }

    func test_referralCode_generated_is_uppercase_and_bounded_length() {
        defaults.removeObject(forKey: codeKey)
        let code = ReferralService.referralCode
        XCTAssertEqual(code, code.uppercased(), "코드는 대문자")
        XCTAssertLessThanOrEqual(code.count, 8, "IDFV 기반 8자 prefix")
        XCTAssertFalse(code.contains("-"), "하이픈은 제거됨")
    }

    func test_shareURL_contains_referral_parameter() {
        defaults.set("ABC12345", forKey: codeKey)
        let url = ReferralService.shareURL
        XCTAssertTrue(url.absoluteString.contains("referral=ABC12345"))
        XCTAssertTrue(url.absoluteString.hasPrefix("https://apps.apple.com/app/ticklab/"))
    }

    func test_shareItems_contains_url_and_code() {
        defaults.set("ABC12345", forKey: codeKey)
        let items = ReferralService.shareItems
        XCTAssertEqual(items.count, 1)
        let message = try? XCTUnwrap(items.first as? String)
        XCTAssertNotNil(message)
        XCTAssertTrue(message!.contains(ReferralService.shareURL.absoluteString),
                      "공유 메시지에 share URL 포함")
        XCTAssertTrue(message!.contains("ABC12345"), "공유 메시지에 레퍼럴 코드 포함")
    }
}
