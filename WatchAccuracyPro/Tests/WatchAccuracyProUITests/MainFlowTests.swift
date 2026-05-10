import XCTest

/// 핵심 사용자 플로우의 회귀 방지 — 빌드 깨지지 않게.
/// 실 측정(마이크 권한 + 신호) 이 필요한 부분은 manual QA 로 분리.
final class MainFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func freshLaunch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ticklab.onboardingComplete", "0",
            "-ticklab.modeChosenOnce", "0",
            "-ticklab.userMode", "beginner",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ] + arguments
        app.launch()
        return app
    }

    func test_first_run_shows_onboarding_and_proceeds_to_mode_select() throws {
        let app = freshLaunch()

        // Onboarding "Next" 또는 "Get Started" 버튼이 보여야 함
        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()
        nextButton.tap()

        let getStarted = app.buttons["Get Started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 3))
        getStarted.tap()

        // ModeSelect 화면
        let beginner = app.staticTexts["I'm new to this"]
        XCTAssertTrue(beginner.waitForExistence(timeout: 3))
    }

    func test_skip_to_collection_when_onboarding_already_done() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ticklab.onboardingComplete", "1",
            "-ticklab.modeChosenOnce", "1",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        // Empty Collection 화면 — "Add your first watch" 표시
        let addFirst = app.staticTexts["Add your first watch"]
        XCTAssertTrue(addFirst.waitForExistence(timeout: 5))
    }

    func test_open_settings_from_collection() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ticklab.onboardingComplete", "1",
            "-ticklab.modeChosenOnce", "1",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        let settingsButton = app.navigationBars.buttons["gearshape"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        let glossary = app.staticTexts["Glossary"]
        XCTAssertTrue(glossary.waitForExistence(timeout: 3))
    }
}
