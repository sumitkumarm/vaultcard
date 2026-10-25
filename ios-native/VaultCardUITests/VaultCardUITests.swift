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

    func testBulkReviewAddsAllCardsAndCompletesMissingCVV() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-bulk"]
        app.launch()
        completeOnboardingIfNeeded(app)
        app.buttons["cards.add"].firstMatch.tap()
        let bulk = app.buttons["add.bulk"]
        for _ in 0..<3 where !bulk.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(bulk.waitForExistence(timeout: 5))
        bulk.tap()
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Card from row")).firstMatch.exists)
        let confirm = app.buttons["bulk.confirm"]
        for _ in 0..<5 where !confirm.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertEqual(confirm.label, "Confirm & Add 2 Cards")
        let beforeSave = XCTAttachment(screenshot: app.screenshot())
        beforeSave.name = "Bulk card review with optional CVV"
        beforeSave.lifetime = .keepAlways
        add(beforeSave)
        confirm.tap()
        XCTAssertTrue(app.navigationBars["Vault"].waitForExistence(timeout: 5))
        let expand = app.buttons["cards.stack.expand"]
        if expand.waitForExistence(timeout: 3), expand.isHittable { expand.tap() }
        let missingCodeCard = app.buttons["card.row.4444"]
        for _ in 0..<3 where !missingCodeCard.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(missingCodeCard.waitForExistence(timeout: 5))
        missingCodeCard.tap()
        let addCVV = app.buttons["detail.addCVV"]
        XCTAssertTrue(addCVV.waitForExistence(timeout: 5))
        addCVV.tap()
        let code = app.secureTextFields["missingCVV.value"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.tap()
        code.typeText("456")
        app.buttons["missingCVV.save"].tap()
        XCTAssertTrue(app.buttons["detail.refresh"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["detail.addCVV"].exists)
    }

    func testEmptyBulkCaptureFitsWithoutScrolling() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        completeOnboardingIfNeeded(app)

        let addButton = app.buttons["cards.add"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        let bulkButton = app.buttons["add.bulk"]
        XCTAssertTrue(bulkButton.waitForExistence(timeout: 5))
        bulkButton.tap()

        let scroll = app.scrollViews["bulk.scroll"]
        let firstCaptureOption = app.buttons["bulk.capture.camera"]
        let privacyFooter = app.descendants(matching: .any)["bulk.privacy.footer"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        XCTAssertTrue(firstCaptureOption.waitForExistence(timeout: 5))
        XCTAssertTrue(privacyFooter.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No cards yet"].exists)
        XCTAssertFalse(app.buttons["bulk.confirm"].exists)
        XCTAssertTrue(firstCaptureOption.isHittable)
        XCTAssertTrue(privacyFooter.isHittable)
        XCTAssertGreaterThanOrEqual(firstCaptureOption.frame.minY, scroll.frame.minY - 1)
        XCTAssertLessThanOrEqual(privacyFooter.frame.maxY, scroll.frame.maxY + 1)

        let captureTopBeforeSwipe = firstCaptureOption.frame.minY
        let privacyBottomBeforeSwipe = privacyFooter.frame.maxY
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Empty bulk capture"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        scroll.swipeUp()

        XCTAssertEqual(firstCaptureOption.frame.minY, captureTopBeforeSwipe, accuracy: 1)
        XCTAssertEqual(privacyFooter.frame.maxY, privacyBottomBeforeSwipe, accuracy: 1)
    }

    func testHomeFundsTotalDoesNotChangeWithSearch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-seed-cards", "--ui-testing-seed-activity"]
        app.launch()
        let total = app.staticTexts["funds.total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertEqual(total.label, "$300.00")
        let search = app.textFields["Search cards"]
        search.tap()
        search.typeText("Test Atlas\n")
        XCTAssertEqual(total.label, "$300.00")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Unused funds across active cards"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testBalanceLoadFailureOffersRetry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-seed-cards", "--ui-testing-web-failure"]
        app.launch()
        openSeededCardForBalance(app)
        app.buttons["detail.refresh"].tap()
        let retry = app.buttons["balance.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Balance page couldn’t be loaded"].exists)
        XCTAssertTrue(retry.isHittable)
    }

    func testZeroBalanceRefreshAutoArchivesAndOffersUndo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-seed-cards", "--ui-testing-zero-refresh"]
        app.launch()
        openSeededCardForBalance(app)
        app.buttons["detail.refresh"].tap()
        let popup = app.alerts["Card archived"]
        XCTAssertTrue(popup.waitForExistence(timeout: 5))
        XCTAssertTrue(popup.buttons["Done"].exists)
        XCTAssertTrue(popup.buttons["Keep This Card"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Zero balance automatic archive with undo"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        popup.buttons["Keep This Card"].tap()
        XCTAssertFalse(popup.exists)
        XCTAssertTrue(app.navigationBars["Check Balance"].exists)
        app.navigationBars["Check Balance"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["detail.archive"].waitForExistence(timeout: 5))
    }

    func testDisabledAutoArchiveOffersOneTimeAndAlwaysChoices() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-seed-cards", "--ui-testing-zero-refresh"]
        app.launch()
        app.buttons["tray.settings"].tap()
        let toggle = app.switches["Archive $0 cards automatically"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["tray.vault"].tap()
        openSeededCardForBalance(app)
        app.buttons["detail.refresh"].tap()
        let popup = app.alerts["No balance left"]
        XCTAssertTrue(popup.waitForExistence(timeout: 5))
        XCTAssertTrue(popup.buttons["Not Now"].exists)
        XCTAssertTrue(popup.buttons["Archive This Card"].exists)
        XCTAssertTrue(popup.buttons["Always Archive $0 Cards"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Zero balance archive choices"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        popup.buttons["Always Archive $0 Cards"].tap()
        XCTAssertFalse(popup.exists)
        app.navigationBars["Check Balance"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["detail.restore"].waitForExistence(timeout: 5))
        app.buttons["tray.settings"].tap()
        XCTAssertEqual(app.switches["Archive $0 cards automatically"].value as? String, "1")
    }

    func testZeroBalanceListFilterAndBulkArchive() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-seed-cards", "--ui-testing-seed-activity", "--ui-testing-seed-zero-card"]
        app.launch()
        let zeroFilter = app.buttons["cards.filter.$0-balance"]
        XCTAssertTrue(zeroFilter.waitForExistence(timeout: 5))
        if !zeroFilter.isHittable {
            app.scrollViews.firstMatch.swipeLeft()
        }
        zeroFilter.tap()
        XCTAssertTrue(app.staticTexts["Test Aurora"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Test Nova"].exists)
        app.buttons["cards.archived"].tap()
        app.buttons["Archive $0 Cards (1)"].tap()
        let popup = app.alerts.firstMatch
        XCTAssertTrue(popup.waitForExistence(timeout: 5))
        popup.buttons["cards.archiveZero.confirm"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No matching cards"].waitForExistence(timeout: 5))
    }

    func testCreditsAndDebitsAppearDistinctlyInActivityAndDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-seed-cards", "--ui-testing-seed-activity", "--ui-testing-seed-signed-activity"]
        app.launch()
        openSeededCardForBalance(app)
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Credit")).firstMatch.waitForExistence(timeout: 5))
        let detail = XCTAttachment(screenshot: app.screenshot())
        detail.name = "Quiet debits and highlighted credits"
        detail.lifetime = .keepAlways
        add(detail)
        app.buttons["tray.vault"].tap()
        app.buttons["cards.activity"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Credit")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "activity.transaction.", "Debit")).firstMatch.exists)
        let activity = XCTAttachment(screenshot: app.screenshot())
        activity.name = "Credits and debits in activity"
        activity.lifetime = .keepAlways
        add(activity)
    }

    private func openSeededCardForBalance(_ app: XCUIApplication, last4: String = "1111") {
        let expand = app.buttons["cards.stack.expand"]
        if expand.waitForExistence(timeout: 5), expand.isHittable { expand.tap() }
        let row = app.buttons["card.row." + last4]
        for _ in 0..<6 {
            if row.exists, row.frame.minY > 120, row.frame.maxY < app.frame.height - 180 { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["detail.refresh"].waitForExistence(timeout: 5))
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
