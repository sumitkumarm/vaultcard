import XCTest

final class VaultCardUITests: XCTestCase {
    func testAppLaunchesToOnboardingOrVault() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.staticTexts["VaultCard"].exists
                || app.staticTexts["Track every gift card in one place"].exists
                || app.buttons["Get Started"].exists
                || app.buttons["Next"].exists
        )
    }
}
