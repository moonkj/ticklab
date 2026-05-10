import XCTest

final class SmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_app_launches_and_first_run_shows_onboarding() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ticklab.onboardingComplete", "0", "-ticklab.modeChosenOnce", "0"]
        app.launch()
        // 첫 실행: onboarding 첫 페이지에 "다음" 또는 "시작하기" 또는 "Next"/"Get Started" 버튼이 있어야 한다
        let nextOrStart = app.buttons.element(matching: NSPredicate(format:
            "label IN {'다음', '시작하기', 'Next', 'Get Started', 'Continue'}"
        ))
        XCTAssertTrue(nextOrStart.waitForExistence(timeout: 5),
                      "Onboarding이 표시되어야 한다")
    }
}
