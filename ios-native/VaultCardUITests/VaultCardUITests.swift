import XCTest

final class VaultCardUITests: XCTestCase {
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

        // Keep the swipe above the keyboard and floating tray so it scrolls the form.
        let form = app.scrollViews.firstMatch
        let scrollStart = form.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.45))
        let scrollEnd = form.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.2))
        let cvv = app.secureTextFields["manual.cvv"]
        scrollStart.press(forDuration: 0.05, thenDragTo: scrollEnd)
        cvv.tap()
        cvv.typeText("123")

        let nickname = app.textFields["manual.nickname"]
        scrollStart.press(forDuration: 0.05, thenDragTo: scrollEnd)
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

    func testSettingsFinalRowClearsFloatingTray() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        completeOnboardingIfNeeded(app)

        let settings = app.buttons["tray.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let version = app.staticTexts["Version"]
        let versionRow = app.cells.containing(.staticText, identifier: "Version").firstMatch
        for _ in 0..<6 {
            if versionRow.isHittable { break }
            app.swipeUp()
        }

        XCTAssertTrue(version.exists)
        XCTAssertTrue(versionRow.exists)
        XCTAssertTrue(versionRow.isHittable)

        let addButton = app.buttons["cards.add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        let trayVerticalPadding: CGFloat = 8
        let intendedContentGap: CGFloat = 12
        let trayTop = addButton.frame.minY - trayVerticalPadding
        XCTAssertLessThanOrEqual(
            versionRow.frame.maxY + intendedContentGap,
            trayTop + 1,
            "The final Settings row must remain fully above the floating tray."
        )
    }

    func testVaultPrivacyFooterClearsFloatingTray() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-seed-cards"]
        app.launch()

        let addButton = app.buttons["cards.add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        let footer = app.staticTexts["cards.privacy.footer"]
        let footerRow = app.cells.containing(.staticText, identifier: "cards.privacy.footer").firstMatch
        let trayVerticalPadding: CGFloat = 8
        let intendedContentGap: CGFloat = 12
        let trayTop = addButton.frame.minY - trayVerticalPadding

        for _ in 0..<6 {
            if footerRow.exists, footerRow.frame.maxY + intendedContentGap <= trayTop + 1 { break }
            app.swipeUp()
        }

        XCTAssertTrue(footer.exists)
        XCTAssertTrue(footerRow.exists)
        XCTAssertLessThanOrEqual(
            footerRow.frame.maxY + intendedContentGap,
            trayTop + 1,
            "The Vault privacy footer must remain fully above the floating tray."
        )
    }

    func testActivitySearchFiltersAndSort() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-seed-cards", "--ui-testing-seed-activity"]
        app.launch()
        app.buttons["cards.activity"].tap()

        let search = app.textFields["activity.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(search.isHittable)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "activity.transaction."))
        XCTAssertEqual(rows.count, 3)
        search.tap()
        search.typeText("coffee\n")
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows.element(boundBy: 0).label.contains("Corner Coffee"))
        app.buttons["activity.search.clear"].tap()
        XCTAssertEqual(rows.count, 3)

        app.buttons["activity.sort"].tap()
        app.buttons["Highest amount"].tap()
        XCTAssertTrue(rows.element(boundBy: 0).label.contains("Book Shop"))
        XCTAssertTrue(app.buttons["activity.sort"].label.contains("Highest amount"))

        app.buttons["activity.filters"].tap()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "activity.filter.card.", "Test Aurora")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        let cardID = String(card.identifier.dropFirst("activity.filter.card.".count))
        card.tap()
        app.buttons["activity.filters.apply"].tap()
        XCTAssertEqual(rows.count, 1)
        let chip = app.buttons["activity.filter.remove.card." + cardID]
        XCTAssertTrue(chip.exists)
        XCTAssertTrue(chip.label.contains("1111"))
        chip.tap()
        XCTAssertEqual(rows.count, 3)

        search.tap()
        search.typeText("no such merchant\n")
        XCTAssertEqual(rows.count, 0)
        XCTAssertTrue(app.buttons["activity.reset"].isHittable)
        app.buttons["activity.reset"].tap()
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(app.buttons["activity.sort"].label.contains("Newest first"))
        XCTAssertTrue(rows.element(boundBy: 0).label.contains("Corner Coffee"))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Activity redesigned"
        attachment.lifetime = .keepAlways
        add(attachment)
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
