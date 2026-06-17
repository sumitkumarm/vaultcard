import XCTest

final class VaultCardUITests: XCTestCase {
    func testAppLaunchesToOnboardingOrVault() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(
            app.staticTexts["VaultCard"].exists
                || app.staticTexts["Track every gift card in one place"].exists
                || app.buttons["Get Started"].exists
                || app.buttons["Next"].exists
        )
    }

    func testManualCardLifecycleHappyPath() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        completeOnboardingIfNeeded(app)

        let addButton = app.buttons["cards.add"].firstMatch.exists ? app.buttons["cards.add"].firstMatch : app.buttons["cards.empty.add"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(app.buttons["add.manual"].waitForExistence(timeout: 5))
        app.buttons["add.manual"].tap()

        let cardNumber = app.textFields["manual.cardNumber"]
        XCTAssertTrue(cardNumber.waitForExistence(timeout: 5))
        cardNumber.tap()
        cardNumber.typeText("4111111111111111")

        let expiry = app.textFields["manual.expiry"]
        expiry.tap()
        expiry.typeText("0929")

        let cvv = app.secureTextFields["manual.cvv"]
        cvv.tap()
        cvv.typeText("123")

        let nickname = app.textFields["manual.nickname"]
        nickname.tap()
        nickname.typeText("Groceries")

        app.buttons["manual.save"].tap()

        XCTAssertTrue(app.staticTexts["Sensitive Details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["**** **** **** 1111"].waitForExistence(timeout: 5))

        app.buttons["detail.reveal"].tap()
        XCTAssertTrue(app.staticTexts["4111111111111111"].waitForExistence(timeout: 5))

        app.buttons["detail.delete"].tap()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        app.buttons["Delete"].tap()

        XCTAssertTrue(app.staticTexts["No cards yet"].waitForExistence(timeout: 5))
    }

    func testManualCardValidationFailurePath() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        completeOnboardingIfNeeded(app)

        let addButton = app.buttons["cards.add"].firstMatch.exists ? app.buttons["cards.add"].firstMatch : app.buttons["cards.empty.add"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        XCTAssertTrue(app.buttons["add.manual"].waitForExistence(timeout: 5))
        app.buttons["add.manual"].tap()

        XCTAssertTrue(app.textFields["manual.cardNumber"].waitForExistence(timeout: 5))
        app.textFields["manual.cardNumber"].tap()
        app.textFields["manual.cardNumber"].typeText("123")
        app.buttons["manual.save"].tap()

        XCTAssertTrue(app.staticTexts["Enter a valid Visa or Mastercard number."].waitForExistence(timeout: 5))
    }

    private func completeOnboardingIfNeeded(_ app: XCUIApplication) {
        let primary = app.buttons["onboarding.primary"]
        if primary.waitForExistence(timeout: 3) {
            primary.tap()
            primary.tap()
            primary.tap()
        }
    }
}
