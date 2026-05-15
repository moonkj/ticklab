import XCTest
@testable import WatchAccuracyPro

/// 한국어/영어 Localizable.strings 의 키 집합이 일치하는지 검증.
/// Round 6 (Hyemi): paired 검수 자동화 — 새 키가 한쪽에만 추가되는 실수 방지.
final class LocalizationParityTests: XCTestCase {
    func test_ko_and_en_keys_match() throws {
        let bundle = Bundle.main
        guard
            let koPath = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "ko"),
            let enPath = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en")
        else {
            // 테스트 번들 fallback
            let koURL = bundle.url(forResource: "ko", withExtension: "lproj")?
                .appendingPathComponent("Localizable.strings")
            let enURL = bundle.url(forResource: "en", withExtension: "lproj")?
                .appendingPathComponent("Localizable.strings")
            try XCTSkipIf(koURL == nil || enURL == nil, "Localizable.strings not in test bundle")
            return
        }
        let koDict = try parse(path: koPath)
        let enDict = try parse(path: enPath)
        let koKeys = Set(koDict.keys)
        let enKeys = Set(enDict.keys)

        let missingInEn = koKeys.subtracting(enKeys)
        let missingInKo = enKeys.subtracting(koKeys)

        XCTAssertTrue(
            missingInEn.isEmpty,
            "EN 에 누락된 키: \(missingInEn.sorted())"
        )
        XCTAssertTrue(
            missingInKo.isEmpty,
            "KO 에 누락된 키: \(missingInKo.sorted())"
        )
    }

    private func parse(path: String) throws -> [String: String] {
        guard let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            throw NSError(domain: "LocalizationParity", code: -1)
        }
        return dict
    }
}
