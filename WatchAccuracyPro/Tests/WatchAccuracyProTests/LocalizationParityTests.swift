import XCTest
@testable import WatchAccuracyPro

/// 다국어 Localizable.strings 의 키 집합이 모든 locale 에서 일치하는지 검증.
/// Round 6 (Hyemi): paired 검수 자동화 — 새 키가 한쪽에만 추가되는 실수 방지.
/// 8개 언어 지원 확장 — en 을 기준 reference 로 모든 locale 키 매칭 검사.
final class LocalizationParityTests: XCTestCase {
    /// 지원 locale 목록 — Info.plist CFBundleLocalizations 와 동기 유지.
    private static let supportedLocales = ["ko", "en", "ja", "es", "fr", "hi", "zh-Hans", "zh-Hant"]

    func test_ko_and_en_keys_match() throws {
        let bundle = Bundle.main
        guard
            let koPath = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "ko"),
            let enPath = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en")
        else {
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

    /// 모든 지원 locale 이 en 과 동일한 키 집합을 갖는지 검증.
    func test_all_locales_match_english() throws {
        let bundle = Bundle.main
        guard let enPath = bundle.path(
            forResource: "Localizable", ofType: "strings",
            inDirectory: nil, forLocalization: "en"
        ) else {
            throw XCTSkip("en Localizable.strings not in test bundle")
        }
        let enKeys = Set(try parse(path: enPath).keys)

        for locale in Self.supportedLocales where locale != "en" {
            guard let path = bundle.path(
                forResource: "Localizable", ofType: "strings",
                inDirectory: nil, forLocalization: locale
            ) else {
                XCTFail("\(locale).lproj/Localizable.strings 가 번들에 없음 — Info.plist CFBundleLocalizations + xcodeproj knownRegions 확인 필요")
                continue
            }
            let dict = try parse(path: path)
            let keys = Set(dict.keys)
            let missing = enKeys.subtracting(keys)
            let extra = keys.subtracting(enKeys)
            XCTAssertTrue(
                missing.isEmpty,
                "\(locale).lproj 에 누락된 키 (\(missing.count)개): \(missing.sorted().prefix(10).joined(separator: ", "))…"
            )
            XCTAssertTrue(
                extra.isEmpty,
                "\(locale).lproj 에 en 에 없는 추가 키 (\(extra.count)개): \(extra.sorted().prefix(10).joined(separator: ", "))…"
            )
        }
    }

    private func parse(path: String) throws -> [String: String] {
        guard let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            throw NSError(domain: "LocalizationParity", code: -1)
        }
        return dict
    }

    /// Round 19 (Jay): NSDictionary 가 중복 키를 silently collapse 하던 문제 검출.
    /// raw line scan 으로 같은 키가 2 번 이상 등장하는 경우 탐지.
    func test_no_duplicate_keys() throws {
        let bundle = Bundle.main
        let candidates: [(String, String)] = ["ko", "en"].compactMap { lang in
            guard let path = bundle.path(
                forResource: "Localizable", ofType: "strings",
                inDirectory: nil, forLocalization: lang
            ) else { return nil }
            return (lang, path)
        }
        try XCTSkipIf(candidates.isEmpty, "Localizable.strings not in test bundle")
        for (lang, path) in candidates {
            // Round (3-2): Xcode 가 빌드 시 .strings 를 UTF-16 으로 변환 — encoding 자동 추정 사용.
            var detected: String.Encoding = .utf8
            let content: String
            if let auto = try? String(contentsOfFile: path, usedEncoding: &detected) {
                content = auto
            } else {
                content = try String(contentsOfFile: path, encoding: .utf16)
            }
            let pattern = #"^\s*"([^"]+)"\s*="#
            let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            var counts: [String: Int] = [:]
            regex.enumerateMatches(in: content, range: range) { match, _, _ in
                guard let m = match, m.numberOfRanges > 1,
                      let r = Range(m.range(at: 1), in: content) else { return }
                let key = String(content[r])
                counts[key, default: 0] += 1
            }
            let duplicates = counts.filter { $0.value > 1 }.keys.sorted()
            XCTAssertTrue(
                duplicates.isEmpty,
                "\(lang).lproj 에 중복 key: \(duplicates) — NSDictionary 가 silently collapse 하므로 마지막 값만 유효."
            )
        }
    }
}
