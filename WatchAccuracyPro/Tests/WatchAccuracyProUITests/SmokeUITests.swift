import XCTest

final class SmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_app_launches_and_shows_app_name() throws {
        let app = XCUIApplication()
        app.launch()
        // 한국어/영어 어떤 locale에서도 "Watch Accuracy Pro" 그대로 표시
        XCTAssertTrue(app.staticTexts["Watch Accuracy Pro"].waitForExistence(timeout: 5))
    }
}
