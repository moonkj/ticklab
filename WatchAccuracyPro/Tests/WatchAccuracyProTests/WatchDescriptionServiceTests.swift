import XCTest
@testable import WatchAccuracyPro

/// PURE 커버리지: WatchDescriptionService.ruleBased — rule-based 폴백은 nonisolated·결정적.
/// LLM(callAI) 경로는 FoundationModels/네트워크 의존이라 테스트 대상에서 제외.
@MainActor
final class WatchDescriptionServiceTests: XCTestCase {

    private let service = WatchDescriptionService.shared

    // MARK: - specSummary grounding

    func test_ruleBased_includes_specSummary_when_present() {
        let specs = "케이스 40mm · 파워리저브 42h · lift angle 52°"
        let result = service.ruleBased(movement: .automatic, specSummary: specs)
        XCTAssertTrue(result.contains(specs), "specSummary 가 결과에 grounding 되어야 함")
        XCTAssertFalse(result.isEmpty)
    }

    func test_ruleBased_specSummary_appears_before_concept_with_newline() {
        let specs = "케이스 41mm"
        let result = service.ruleBased(movement: .manual, specSummary: specs)
        // "\(specs)\n\(concept)" 구조 — specs 가 맨 앞.
        XCTAssertTrue(result.hasPrefix(specs))
        XCTAssertTrue(result.contains("\n"))
    }

    // MARK: - empty / whitespace specSummary → concept only

    func test_ruleBased_empty_specSummary_returns_concept_only_no_leading_newline() {
        let result = service.ruleBased(movement: .automatic, specSummary: "")
        XCTAssertFalse(result.isEmpty, "스펙이 없어도 무브먼트 개념 설명은 항상 반환")
        XCTAssertFalse(result.hasPrefix("\n"), "빈 스펙이면 앞에 개행이 붙지 않아야 함")
    }

    func test_ruleBased_whitespace_specSummary_treated_as_empty() {
        let resultEmpty = service.ruleBased(movement: .quartz, specSummary: "")
        let resultSpaces = service.ruleBased(movement: .quartz, specSummary: "   ")
        XCTAssertEqual(resultEmpty, resultSpaces, "공백만 있는 스펙은 빈 스펙과 동일 처리")
    }

    // MARK: - all movement types produce non-empty, distinct concepts

    func test_ruleBased_allMovements_nonEmpty() {
        for movement in WatchMovementType.allCases {
            let result = service.ruleBased(movement: movement, specSummary: "")
            XCTAssertFalse(result.isEmpty, "\(movement) 폴백이 비어 있으면 안 됨")
        }
    }

    func test_ruleBased_movementTypes_have_distinct_concepts() {
        // 각 무브먼트 타입은 서로 다른 localized 개념 설명을 사용해야 함.
        let auto = service.ruleBased(movement: .automatic, specSummary: "")
        let manual = service.ruleBased(movement: .manual, specSummary: "")
        let quartz = service.ruleBased(movement: .quartz, specSummary: "")
        XCTAssertNotEqual(auto, manual)
        XCTAssertNotEqual(auto, quartz)
        XCTAssertNotEqual(manual, quartz)
    }
}
