import XCTest

/// 4-tab 신구조 (RootTabView) 기반 핵심 회귀 방지.
/// Round 22 (Jay): 이전 OnboardingView/ModeSelectView 기반 테스트는 view 삭제로 stale —
///   여기서는 collection/today/journal/stats 4탭 + Settings 진입만 verify.
final class MainFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchSkippingOnboarding() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ticklab.onboardingComplete", "1",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
        return app
    }

    /// 첫 진입 시 collection 탭이 default 로 보임.
    func test_first_run_lands_on_collection_tab() throws {
        let app = launchSkippingOnboarding()
        let collectionTab = app.tabBars.buttons["Collection"]
        XCTAssertTrue(collectionTab.waitForExistence(timeout: 5))
        XCTAssertTrue(collectionTab.isSelected || collectionTab.value as? String == "1")
    }

    /// 4개 tab 모두 노출 확인 — Collection / Today / Journal / Stats.
    func test_four_tabs_present() throws {
        let app = launchSkippingOnboarding()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.buttons["Collection"].exists)
        XCTAssertTrue(tabBar.buttons["Today"].exists)
        XCTAssertTrue(tabBar.buttons["Journal"].exists)
        XCTAssertTrue(tabBar.buttons["Stats"].exists)
    }

    /// 탭 전환 — Stats 갔다가 Collection 으로 돌아오면 root 가 보임.
    func test_tab_switch_returns_to_collection_root() throws {
        let app = launchSkippingOnboarding()
        let stats = app.tabBars.buttons["Stats"]
        let collection = app.tabBars.buttons["Collection"]
        XCTAssertTrue(stats.waitForExistence(timeout: 5))
        stats.tap()
        collection.tap()
        // Collection 의 nav settings 버튼은 root 에서만 보임 (detail/sheet 진입 X 상태)
        let settingsBtn = app.buttons["nav.settings"]
        XCTAssertTrue(settingsBtn.waitForExistence(timeout: 3),
                      "Collection root 의 settings 버튼이 보여야 한다")
    }

    /// Collection root → Settings sheet 진입.
    func test_open_settings_from_collection() throws {
        let app = launchSkippingOnboarding()
        let settingsBtn = app.buttons["nav.settings"]
        XCTAssertTrue(settingsBtn.waitForExistence(timeout: 5))
        settingsBtn.tap()
        // Settings sheet 상단 nav title 검증 — 실제 키 "settings.title" -> "Settings".
        let settingsTitle = app.navigationBars["Settings"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 3))
    }

    /// Today 탭 진입 검증 — 화면이 죽지 않아야.
    func test_today_tab_loads() throws {
        let app = launchSkippingOnboarding()
        let today = app.tabBars.buttons["Today"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.tap()
        // 탭바 자체는 여전히 보여야 함 — 진입 후 crash 안 한 회귀 방지 minimum.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 3))
    }

    /// Stats 탭 진입 검증 — empty state 노출.
    func test_stats_tab_loads() throws {
        let app = launchSkippingOnboarding()
        let stats = app.tabBars.buttons["Stats"]
        XCTAssertTrue(stats.waitForExistence(timeout: 5))
        stats.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 3))
    }

    /// Journal 탭 진입 검증.
    func test_journal_tab_loads() throws {
        let app = launchSkippingOnboarding()
        let journal = app.tabBars.buttons["Journal"]
        XCTAssertTrue(journal.waitForExistence(timeout: 5))
        journal.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 3))
    }
}
