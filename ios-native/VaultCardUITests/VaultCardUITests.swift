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

        XCTAssertTrue(app.buttons["scan.enterManually"].waitForExistence(timeout: 5))
        app.buttons["scan.enterManually"].tap()

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

        XCTAssertTrue(app.buttons["detail.reveal"].waitForExistence(timeout: 5))
        let refresh = app.buttons["detail.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["detail.reveal"].frame.height, refresh.frame.height, accuracy: 1)
        XCTAssertEqual(app.buttons["detail.reveal"].frame.width, refresh.frame.width, accuracy: 1)
        XCTAssertTrue(app.staticTexts["**** **** **** 1111"].waitForExistence(timeout: 5))

        app.buttons["detail.reveal"].tap()
        XCTAssertTrue(app.staticTexts["4111 1111 1111 1111"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["123"].waitForExistence(timeout: 5))

        let backToVault = app.buttons["BackButton"]
        XCTAssertTrue(backToVault.waitForExistence(timeout: 5))
        backToVault.tap()
        // A single saved card is shown directly; the stack expand/collapse affordance
        // is only meaningful when there are multiple cards.
        XCTAssertFalse(app.buttons["cards.stack.expand"].exists)
        let singleCard = app.buttons["card.row.1111"]
        XCTAssertTrue(singleCard.waitForExistence(timeout: 5))
        singleCard.swipeLeft()
        let swipeDelete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(swipeDelete.waitForExistence(timeout: 5))
        swipeDelete.tap()

        let confirmDelete = app.alerts["Remove card?"].buttons["Delete"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.tap()

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
        XCTAssertTrue(app.buttons["scan.enterManually"].waitForExistence(timeout: 5))
        app.buttons["scan.enterManually"].tap()

        XCTAssertTrue(app.textFields["manual.cardNumber"].waitForExistence(timeout: 5))
        app.textFields["manual.cardNumber"].tap()
        app.textFields["manual.cardNumber"].typeText("123")
        app.buttons["manual.save"].tap()

        let validationMessage = app.staticTexts["Enter a valid Visa or Mastercard number."]
        XCTAssertTrue(validationMessage.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(validationMessage.frame.height, 24)
    }

    func testDefaultAddOpensScannerAndDisablesCurrentAddAction() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        completeOnboardingIfNeeded(app)

        let addButton = app.buttons["cards.add"].firstMatch.exists ? app.buttons["cards.add"].firstMatch : app.buttons["cards.empty.add"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        XCTAssertTrue(app.buttons["scan.enterManually"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["scan.textFallbackToggle"].exists)
        XCTAssertTrue(app.buttons["cards.add"].exists)
        XCTAssertFalse(app.buttons["cards.add"].isEnabled)
    }

    func testFloatingTraySupportsTapsAndScrubNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        completeOnboardingIfNeeded(app)

        let vault = app.buttons["tray.vault"]
        let settings = app.buttons["tray.settings"]
        XCTAssertTrue(vault.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.waitForExistence(timeout: 5))

        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        vault.tap()
        XCTAssertTrue(app.navigationBars["Vault"].waitForExistence(timeout: 5))

        let vaultCenter = vault.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let settingsCenter = settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        vaultCenter.press(forDuration: 0.4, thenDragTo: settingsCenter)

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        settingsCenter.press(forDuration: 0.4, thenDragTo: vaultCenter)

        XCTAssertTrue(app.navigationBars["Vault"].waitForExistence(timeout: 5))
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
