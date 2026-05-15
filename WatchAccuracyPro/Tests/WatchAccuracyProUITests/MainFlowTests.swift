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

        // Phase 2/3 에서 Settings 가 길어져 Glossary 가 즉시 보이지 않을 수 있음 — section 헤더로 검증.
        let modeSection = app.staticTexts["User mode"]
        XCTAssertTrue(modeSection.waitForExistence(timeout: 5),
                      "Settings 첫 섹션 (User mode) 가 보여야 한다")
    }

    /// Round 9 (Jay): Phase 2 Sync 섹션 표면 노출 검증. 실제 OTA 호출은 안 함.
    func test_settings_shows_phase2_sync_section() throws {
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

        // Settings 안에서 Sync 섹션까지 스크롤. iCloud sync · Auto-update · Check for updates 가 노출되어야 함.
        let syncSection = app.staticTexts["Sync"]
        let scrollView = app.scrollViews.firstMatch
        if !syncSection.waitForExistence(timeout: 2) {
            scrollView.swipeUp()
        }
        XCTAssertTrue(syncSection.waitForExistence(timeout: 3) || app.switches["iCloud sync"].exists,
                      "Sync 섹션 또는 iCloud sync 토글이 노출되어야 한다")
    }
}
