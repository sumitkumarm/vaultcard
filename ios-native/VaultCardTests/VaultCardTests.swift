import SwiftData
import XCTest
@testable import VaultCard

@MainActor
final class VaultCardTests: XCTestCase {
    func testBalanceFreshnessStatesAreMutuallyExclusive() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let recentlyUpdated = freshnessCard(lastFetchedAt: now.addingTimeInterval(-60), failureCount: 0)
        let neverUpdated = freshnessCard(lastFetchedAt: nil, failureCount: 0)
        let failed = freshnessCard(lastFetchedAt: now.addingTimeInterval(-60), failureCount: 1)
        let stale = freshnessCard(
            lastFetchedAt: now.addingTimeInterval(-VaultCard.balanceFreshnessInterval - 1),
            failureCount: 0
        )

        XCTAssertEqual(recentlyUpdated.balanceFreshness(at: now), .upToDate)
        XCTAssertEqual(neverUpdated.balanceFreshness(at: now), .needsRefresh)
        XCTAssertEqual(failed.balanceFreshness(at: now), .needsRefresh)
        XCTAssertEqual(stale.balanceFreshness(at: now), .needsRefresh)
        let boundary = freshnessCard(lastFetchedAt: now.addingTimeInterval(-7 * 86_400), failureCount: 0)
        XCTAssertEqual(boundary.balanceFreshness(at: now), .needsRefresh)
        XCTAssertEqual(boundary.balanceFreshness(at: now.addingTimeInterval(-1)), .upToDate)
        XCTAssertEqual(boundary.balanceFreshness(at: now, refreshAfterDays: 14), .upToDate)
        XCTAssertEqual(recentlyUpdated.balanceFreshness(at: now, refreshAfterDays: 1), .upToDate)
        XCTAssertEqual(failed.balanceFreshness(at: now, refreshAfterDays: 365), .needsRefresh)

    }

    func testTimingSettingsMigrateAndPersistConfiguredValues() throws {
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.refreshAfterDays, 7)
        XCTAssertEqual(legacy.notificationPreferences.expiryWarningDays, 30)
        XCTAssertTrue(legacy.notificationPreferences.expiryWarning)
        var configured = legacy
        configured.refreshAfterDays = 14
        configured.notificationPreferences.expiryWarningDays = 45
        configured.notificationPreferences.expiryWarning = false
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(configured))
        XCTAssertEqual(restored, configured)
        let outOfRange = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"refreshAfterDays":0,"notificationPreferences":{"expiryWarningDays":999}}"#.utf8))
        XCTAssertEqual(outOfRange.refreshAfterDays, 1)
        XCTAssertEqual(outOfRange.notificationPreferences.expiryWarningDays, 365)
    }

    func testCardValidationAndNetworkInference() {
        XCTAssertEqual(CardRules.inferNetwork("4111 1111 1111 1111"), .visa)
        XCTAssertEqual(CardRules.inferNetwork("5555 5555 5555 4444"), .mastercard)
        XCTAssertTrue(CardRules.isValidCardNumber("4111 1111 1111 1111"))
        XCTAssertFalse(CardRules.isValidCardNumber("4111 1111 1111 1112"))
        XCTAssertEqual(CardRules.formatExpiryInput("0129"), "01/29")
        XCTAssertTrue(CardRules.validateCVV("123"))
        XCTAssertFalse(CardRules.validateCVV("12"))
    }

    private func freshnessCard(lastFetchedAt: Date?, failureCount: Int) -> VaultCard {
        VaultCard(
            id: UUID().uuidString,
            nickname: nil,
            network: .visa,
            last4: "1111",
            expiry: "09/29",
            balance: lastFetchedAt == nil ? nil : 25,
            transactions: [],
            lastFetchedAt: lastFetchedAt,
            fetchFailureCount: failureCount,
            addedAt: Date(timeIntervalSince1970: 0),
            refreshBlockedUntil: nil,
            credentialVersion: 1
        )
    }

    func testCardNumberDisplayAndCredentialExpiryFormatting() {
        XCTAssertEqual(CardRules.formatCardNumber("4111111111111111"), "4111 1111 1111 1111")
        XCTAssertEqual(CardRules.formatCardNumber("5555-5555 5555-4444"), "5555 5555 5555 4444")

        let credentials = CardCredentials(cardNumber: "4111111111111111", expiry: "09/29", cvv: "123", pin: "")
        XCTAssertEqual(credentials.expiryMonth, "09")
        XCTAssertEqual(credentials.expiryYear, "29")
    }

    func testScanTextExtractionHappyAndFailurePaths() {
        let scanner = VisionCardScanner()
        let result = scanner.extractCandidates(from: "Card 4111 1111 1111 1111 exp: 09/29 cvv: 123")
        XCTAssertEqual(result.cardNumber, "4111111111111111")
        XCTAssertEqual(result.expiry, "09/29")
        XCTAssertEqual(result.cvv, "123")
        XCTAssertEqual(result.network, .visa)

        let failed = scanner.extractCandidates(from: "no useful card text")
        XCTAssertFalse(failed.hasCandidateData)
        XCTAssertEqual(failed.confidence, 0.45)
    }

    func testScanRejectsInvalidPanAndDoesNotGuessUnlabeledCVV() {
        let scanner = VisionCardScanner()
        let result = scanner.extractCandidates(from: """
        4111 1111 1111 1112
        5555 5555 5555 4444
        09/29
        reference 999
        """)

        XCTAssertEqual(result.cardNumber, "5555555555554444")
        XCTAssertEqual(result.expiry, "09/29")
        XCTAssertNil(result.cvv)
        XCTAssertEqual(result.network, .mastercard)
    }

    func testScanRecognizesLabeledSecurityCodeVariants() {
        let scanner = VisionCardScanner()
        let cases: [(text: String, expectedCVV: String)] = [
            ("Card number: 4111-1111-1111-1111 Expires 09 / 29 Security Code 321", "321"),
            ("Card 4111 1111 1111 1111\nEXP 09/29\nC V V : 1 2 3", "123"),
            ("5555 5555 5555 4444\n12/30\nSecurity Code\n987", "987"),
            ("SEC ID: 6 5 4", "654"),
            ("Card verification number 321", "321"),
            ("CSC 987", "987")
        ]

        for testCase in cases {
            XCTAssertEqual(
                scanner.extractCandidates(from: testCase.text).cvv,
                testCase.expectedCVV,
                testCase.text
            )
        }

        let normalized = scanner.extractCandidates(from: cases[0].text)
        XCTAssertEqual(normalized.cardNumber, "4111111111111111")
        XCTAssertEqual(normalized.expiry, "09/29")
        XCTAssertEqual(normalized.confidence, 0.95)
    }

    func testScanInfersIsolatedThreeDigitSecurityValueWithoutCVVLabel() {
        let scanner = VisionCardScanner()
        let result = scanner.extractCandidates(from: """
        4111 1111 1111 1111
        09/29
        742
        """)

        XCTAssertEqual(result.cvv, "742")
        XCTAssertEqual(result.confidence, 0.95)
    }

    func testPreferredAddNavigationDoesNotDuplicate() throws {
        let model = AppModel(environment: try AppEnvironment.uiTesting())
        model.showPreferredAddFlow()
        model.showPreferredAddFlow()
        XCTAssertEqual(model.routePath.count, 1)
        guard let scanRoute = model.routePath.first, case .scan = scanRoute else {
            return XCTFail("The default add action should open scanning directly.")
        }

        model.showVault()
        model.updateSettings { $0.addCardPreference = .manual }
        model.showPreferredAddFlow()
        guard let manualRoute = model.routePath.first, case .manualEntry(prefill: nil) = manualRoute else {
            return XCTFail("The manual preference should open manual entry directly.")
        }
    }

    func testSettingsRepositoryMigratesLegacyDefaultsAndPersistsSwipeArchiveConfirmation() throws {
        let suiteName = "VaultCardTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacy = try XCTUnwrap(#"{"onboardingCompleted":true}"#.data(using: .utf8))
        defaults.set(legacy, forKey: "app_settings")
        let settingsRepository = UserDefaultsSettingsRepository(defaults: defaults)
        let migrated = settingsRepository.load()
        XCTAssertTrue(migrated.onboardingCompleted)
        XCTAssertEqual(migrated.addCardPreference, .scan)
        XCTAssertFalse(migrated.hasSeenSwipeArchiveConfirmation)

        let container = try ModelContainerFactory.makeInMemory()
        let environment = AppEnvironment(
            cardRepository: SwiftDataCardRepository(
                context: ModelContext(container),
                credentialStore: FakeCredentialStore()
            ),
            settingsRepository: settingsRepository,
            biometricService: AlwaysAllowAuthenticationService(),
            notificationService: NoopNotificationService(),
            scanner: StaticCardScanner()
        )
        let model = AppModel(environment: environment)

        XCTAssertFalse(model.settings.hasSeenSwipeArchiveConfirmation)
        model.markSwipeArchiveConfirmationSeen()

        XCTAssertTrue(model.settings.hasSeenSwipeArchiveConfirmation)
        XCTAssertTrue(UserDefaultsSettingsRepository(defaults: defaults).load().hasSeenSwipeArchiveConfirmation)
    }

    func testRepositoryRejectsDuplicateCredential() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let store = FakeCredentialStore()
        let repository = SwiftDataCardRepository(
            context: context,
            credentialStore: store,
            uuid: { "fixed-id" }
        )
        _ = try repository.addCard(validInput())
        XCTAssertThrowsError(try repository.addCard(validInput(nickname: "duplicate")))
        XCTAssertEqual(store.records.count, 1)
    }

    func testRepositoryRollsBackCredentialWhenMetadataSaveFails() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let store = FakeCredentialStore()
        let repository = SwiftDataCardRepository(
            context: context,
            credentialStore: store,
            uuid: { "rollback-id" },
            beforeMetadataSave: { throw VaultError.validation("forced metadata failure") }
        )

        XCTAssertThrowsError(try repository.addCard(validInput()))
        XCTAssertNil(store.records["rollback-id"])
    }

    func testRepositorySurfacesMissingCredentialState() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let store = FakeCredentialStore()
        let repository = SwiftDataCardRepository(context: context, credentialStore: store)
        let id = try repository.addCard(validInput())
        try store.delete(cardID: id)
        XCTAssertThrowsError(try repository.getCredentials(cardID: id)) { error in
            XCTAssertEqual(error as? VaultError, .credentialUnavailable)
        }
    }

    func testRepositorySurfacesDeleteCredentialFailure() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let store = FakeCredentialStore()
        let repository = SwiftDataCardRepository(context: context, credentialStore: store)
        let id = try repository.addCard(validInput())
        store.failDelete = true
        XCTAssertThrowsError(try repository.deleteCard(id: id))
        XCTAssertNotNil(try repository.getCard(id: id))
    }

    func testBalanceResultPersistsTransactionsSeparately() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let repository = SwiftDataCardRepository(context: context, credentialStore: FakeCredentialStore())
        let id = try repository.addCard(validInput())
        let result = BalanceResult(
            balance: 12.34,
            transactions: [CardTransaction(date: Date(timeIntervalSince1970: 100), description: "Store", amount: -3.21)],
            fetchedAt: Date(timeIntervalSince1970: 200)
        )
        try repository.applyBalanceResult(cardID: id, result: result)
        let card = try XCTUnwrap(repository.getCard(id: id))
        XCTAssertEqual(card.balance, 12.34)
        XCTAssertEqual(card.transactions.count, 1)
        XCTAssertEqual(card.fetchFailureCount, 0)
        XCTAssertNotNil(card.refreshBlockedUntil)
    }

    func testArchiveAndUnarchivePersistCardDataCredentialsAndTransactions() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let store = FakeCredentialStore()
        let archiveDate = Date(timeIntervalSince1970: 500)
        let repository = SwiftDataCardRepository(
            context: context,
            credentialStore: store,
            now: { archiveDate },
            uuid: { "archive-card" }
        )
        let id = try repository.addCard(
            CardInput(
                cardNumber: "4111111111111111",
                expiry: "09/29",
                cvv: "123",
                pin: "4567",
                nickname: "Travel"
            )
        )
        let fetchedAt = Date(timeIntervalSince1970: 400)
        let transactions = [
            CardTransaction(
                id: "transaction-1",
                date: Date(timeIntervalSince1970: 300),
                description: "Coffee Shop",
                amount: -7.25
            ),
            CardTransaction(
                id: "transaction-2",
                date: Date(timeIntervalSince1970: 200),
                description: "Gift Load",
                amount: 50
            )
        ]
        try repository.applyBalanceResult(
            cardID: id,
            result: BalanceResult(balance: 42.75, transactions: transactions, fetchedAt: fetchedAt)
        )
        let expectedCredentials = try repository.getCredentials(cardID: id)

        try repository.archiveCard(id: id)
        let archived = try XCTUnwrap(repository.getCard(id: id))
        XCTAssertTrue(archived.isArchived)
        XCTAssertEqual(archived.archivedAt, archiveDate)
        XCTAssertEqual(archived.balance, 42.75)
        XCTAssertEqual(archived.transactions, transactions)
        XCTAssertEqual(try repository.getCredentials(cardID: id), expectedCredentials)

        // A new context proves the archive marker and all non-secret data are saved,
        // while the shared credential store proves secrets remain available.
        let reloadedRepository = SwiftDataCardRepository(
            context: ModelContext(container),
            credentialStore: store,
            now: { archiveDate }
        )
        let persisted = try XCTUnwrap(reloadedRepository.getCard(id: id))
        XCTAssertTrue(persisted.isArchived)
        XCTAssertEqual(persisted.archivedAt, archiveDate)
        XCTAssertEqual(persisted.balance, 42.75)
        XCTAssertEqual(persisted.transactions, transactions)
        XCTAssertEqual(try reloadedRepository.getCredentials(cardID: id), expectedCredentials)

        try reloadedRepository.unarchiveCard(id: id)
        let restored = try XCTUnwrap(reloadedRepository.getCard(id: id))
        XCTAssertFalse(restored.isArchived)
        XCTAssertNil(restored.archivedAt)
        XCTAssertEqual(restored.balance, 42.75)
        XCTAssertEqual(restored.transactions, transactions)
        XCTAssertEqual(try reloadedRepository.getCredentials(cardID: id), expectedCredentials)
    }

    func testAppModelPartitionsActiveAndArchivedCardsAndSupportsBulkArchiveUnarchive() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let store = FakeCredentialStore()
        var nextIDs = ["active-card", "archived-card-1", "archived-card-2"]
        let repository = SwiftDataCardRepository(
            context: context,
            credentialStore: store,
            now: { Date(timeIntervalSince1970: 600) },
            uuid: { nextIDs.removeFirst() }
        )
        let environment = AppEnvironment(
            cardRepository: repository,
            settingsRepository: InMemorySettingsRepository(),
            biometricService: AlwaysAllowAuthenticationService(),
            notificationService: NoopNotificationService(),
            scanner: StaticCardScanner()
        )
        let model = AppModel(environment: environment)
        let activeID = try model.addCard(validInput(nickname: "Active"))
        let archivedID1 = try model.addCard(validInput(nickname: "Archived One"))
        let archivedID2 = try model.addCard(validInput(nickname: "Archived Two"))

        XCTAssertEqual(Set(model.sortedActiveCards.map(\.id)), Set([activeID, archivedID1, archivedID2]))
        XCTAssertTrue(model.sortedArchivedCards.isEmpty)

        try model.archiveCards(ids: [archivedID1, archivedID2])
        XCTAssertEqual(Set(model.sortedActiveCards.map(\.id)), [activeID])
        XCTAssertEqual(Set(model.sortedArchivedCards.map(\.id)), Set([archivedID1, archivedID2]))
        XCTAssertTrue(model.sortedArchivedCards.allSatisfy(\.isArchived))

        try model.unarchiveCards(ids: [archivedID1])
        XCTAssertEqual(Set(model.sortedActiveCards.map(\.id)), Set([activeID, archivedID1]))
        XCTAssertEqual(Set(model.sortedArchivedCards.map(\.id)), [archivedID2])

        try model.unarchiveCards(ids: [archivedID2])
        XCTAssertEqual(Set(model.sortedActiveCards.map(\.id)), Set([activeID, archivedID1, archivedID2]))
        XCTAssertTrue(model.sortedArchivedCards.isEmpty)
    }

    func testSortedCardListsFollowSortSettingAndArchiveMutations() throws {
        let container = try ModelContainerFactory.makeInMemory()
        var nextIDs = ["low-card", "high-card", "archived-card"]
        let repository = SwiftDataCardRepository(
            context: ModelContext(container),
            credentialStore: FakeCredentialStore(),
            uuid: { nextIDs.removeFirst() }
        )
        let environment = AppEnvironment(
            cardRepository: repository,
            settingsRepository: InMemorySettingsRepository(),
            biometricService: AlwaysAllowAuthenticationService(),
            notificationService: NoopNotificationService(),
            scanner: StaticCardScanner()
        )
        let model = AppModel(environment: environment)
        let lowID = try model.addCard(validInput(nickname: "Low"))
        let highID = try model.addCard(validInput(nickname: "High"))
        let archivedID = try model.addCard(validInput(nickname: "Archived"))

        model.applyForegroundRefresh(
            id: lowID,
            result: BalanceResult(balance: 4, transactions: [], fetchedAt: Date(timeIntervalSince1970: 10))
        )
        model.applyForegroundRefresh(
            id: highID,
            result: BalanceResult(balance: 40, transactions: [], fetchedAt: Date(timeIntervalSince1970: 11))
        )
        model.applyForegroundRefresh(
            id: archivedID,
            result: BalanceResult(balance: 25, transactions: [], fetchedAt: Date(timeIntervalSince1970: 12))
        )

        model.setSort(.balanceLowToHigh)
        XCTAssertEqual(model.sortedActiveCards.map(\.id), [lowID, archivedID, highID])
        XCTAssertTrue(model.sortedArchivedCards.isEmpty)

        try model.archiveCard(id: archivedID)
        XCTAssertEqual(model.sortedActiveCards.map(\.id), [lowID, highID])
        XCTAssertEqual(model.sortedArchivedCards.map(\.id), [archivedID])

        model.setSort(.balanceHighToLow)
        XCTAssertEqual(model.sortedActiveCards.map(\.id), [highID, lowID])
        XCTAssertEqual(model.sortedArchivedCards.map(\.id), [archivedID])

        try model.unarchiveCard(id: archivedID)
        XCTAssertEqual(model.sortedActiveCards.map(\.id), [highID, archivedID, lowID])
        XCTAssertTrue(model.sortedArchivedCards.isEmpty)
    }

    func testBulkDeletionRemovesOnlySelectedCardsAndPreservesUnselectedCredentials() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let store = FakeCredentialStore()
        var nextIDs = ["delete-card-1", "delete-card-2", "survivor-card"]
        let repository = SwiftDataCardRepository(
            context: context,
            credentialStore: store,
            uuid: { nextIDs.removeFirst() }
        )
        let environment = AppEnvironment(
            cardRepository: repository,
            settingsRepository: InMemorySettingsRepository(),
            biometricService: AlwaysAllowAuthenticationService(),
            notificationService: NoopNotificationService(),
            scanner: StaticCardScanner()
        )
        let model = AppModel(environment: environment)
        let deletedID1 = try model.addCard(validInput(nickname: "Delete One"))
        let deletedID2 = try model.addCard(validInput(nickname: "Delete Two"))
        let survivorID = try model.addCard(validInput(nickname: "Keep Me"))
        let survivorCredentials = try repository.getCredentials(cardID: survivorID)

        try model.deleteCards(ids: [deletedID1, deletedID2])

        XCTAssertEqual(model.cards.map(\.id), [survivorID])
        XCTAssertNil(try repository.getCard(id: deletedID1))
        XCTAssertNil(try repository.getCard(id: deletedID2))
        XCTAssertThrowsError(try repository.getCredentials(cardID: deletedID1)) { error in
            XCTAssertEqual(error as? VaultError, .cardNotFound)
        }
        XCTAssertThrowsError(try repository.getCredentials(cardID: deletedID2)) { error in
            XCTAssertEqual(error as? VaultError, .cardNotFound)
        }
        XCTAssertEqual(try repository.getCredentials(cardID: survivorID), survivorCredentials)
        XCTAssertEqual(Set(store.records.keys), [survivorID])
    }

    func testGiftCardMallBridgeDoesNotSaveAPIClosingBalance() throws {
        let trustedURL = URL(string: "https://www.mycardwallet.com/chs/mygift/")!
        let untrustedURL = URL(string: "https://example.com/")!
        let message: [String: Any] = [
            "namespace": GiftCardMallBridge.handlerName,
            "parserVersion": GiftCardMallBridge.parserVersion,
            "kind": "networkCapture",
            "pageHost": "www.mycardwallet.com",
            "url": "/api/card/getCardBalanceSummary",
            "requestBody": #"{"rmsSessionId":"session-1"}"#,
            "responseBody": #"{"success":true,"access_token":"token-1","result":{"balances":{"closingBalance":42.5,"currencyCode":"USD"}}}"#,
            "status": 200
        ]
        XCTAssertNil(try GiftCardMallBridge.parseSummary(message, sourceURL: untrustedURL))
        XCTAssertNil(try GiftCardMallBridge.parseSummary(message, sourceURL: trustedURL))
    }

    func testBalancePortalRoutesMatchCardNetwork() {
        XCTAssertEqual(GiftCardMallBridge.balanceURL(for: .visa).absoluteString, "https://www.mycardwallet.com/chs/mygift/")
        let mastercard = GiftCardMallBridge.balanceURL(for: .mastercard)
        XCTAssertEqual(mastercard.absoluteString, "https://www.mycardwallet.com/chs/mcgift/")
        XCTAssertTrue(GiftCardMallBridge.isAllowed(mastercard))
        XCTAssertFalse(GiftCardMallBridge.isAllowed(URL(string: "https://www.mycardwallet.com/chs/mcgift-lookalike/")!))
    }

    func testGiftCardMallBridgeTrustsOnlyHTTPSCanonicalRedirectRouteAndMainFrameOrigin() {
        let canonicalURL = URL(string: "https://www.mycardwallet.com/chs/mygift/")!
        let nestedPortalURL = URL(string: "https://www.mycardwallet.com/chs/mygift/cards/123")!
        let legacyURL = URL(string: "https://mygift.giftcardmall.com/")!

        XCTAssertTrue(GiftCardMallBridge.isAllowed(canonicalURL))
        XCTAssertTrue(GiftCardMallBridge.isAllowed(nestedPortalURL))
        XCTAssertTrue(GiftCardMallBridge.isAllowed(legacyURL))
        XCTAssertTrue(GiftCardMallBridge.isTrustedMainFrame(
            isMainFrame: true,
            scheme: "https",
            host: "www.mycardwallet.com",
            port: 443,
            pageURL: canonicalURL
        ))

        XCTAssertTrue(GiftCardMallBridge.isTrustedMainFrame(
            isMainFrame: true, scheme: "https", host: "www.mycardwallet.com", port: 0, pageURL: canonicalURL
        ))

        XCTAssertFalse(GiftCardMallBridge.isAllowed(URL(string: "http://www.mycardwallet.com/chs/mygift/")!))
        XCTAssertFalse(GiftCardMallBridge.isAllowed(URL(string: "https://mycardwallet.com/chs/mygift/")!))
        XCTAssertFalse(GiftCardMallBridge.isAllowed(URL(string: "https://www.mycardwallet.com.evil.example/chs/mygift/")!))
        XCTAssertFalse(GiftCardMallBridge.isAllowed(URL(string: "https://www.mycardwallet.com/")!))
        XCTAssertFalse(GiftCardMallBridge.isAllowed(URL(string: "https://www.mycardwallet.com/chs/mygift-lookalike/")!))
        XCTAssertFalse(GiftCardMallBridge.isAllowed(URL(string: "https://www.mycardwallet.com:8443/chs/mygift/")!))
        XCTAssertFalse(GiftCardMallBridge.isTrustedMainFrame(
            isMainFrame: true,
            scheme: "http",
            host: "www.mycardwallet.com",
            port: 80,
            pageURL: canonicalURL
        ))
        XCTAssertFalse(GiftCardMallBridge.isTrustedMainFrame(
            isMainFrame: true,
            scheme: "https",
            host: "mycardwallet.com",
            port: 443,
            pageURL: canonicalURL
        ))
        XCTAssertFalse(GiftCardMallBridge.isTrustedMainFrame(
            isMainFrame: true,
            scheme: "https",
            host: "www.mycardwallet.com",
            port: 8443,
            pageURL: canonicalURL
        ))
        XCTAssertFalse(GiftCardMallBridge.isTrustedMainFrame(
            isMainFrame: false,
            scheme: "https",
            host: "www.mycardwallet.com",
            port: 443,
            pageURL: canonicalURL
        ))
    }

    func testGiftCardMallBridgeParsesDOMBalanceCapture() throws {
        let trustedURL = URL(string: "https://mygift.giftcardmall.com/card")!
        let message: [String: Any] = [
            "namespace": GiftCardMallBridge.handlerName,
            "parserVersion": GiftCardMallBridge.parserVersion,
            "kind": "domBalance",
            "source": "availableBalanceSummary",
            "pageHost": "mygift.giftcardmall.com",
            "balance": 23.56
        ]

        let summary = try XCTUnwrap(GiftCardMallBridge.parseSummary(message, sourceURL: trustedURL))
        XCTAssertEqual(summary.balance, 23.56)
        var unlabelled = message
        unlabelled.removeValue(forKey: "source")
        XCTAssertNil(try GiftCardMallBridge.parseSummary(unlabelled, sourceURL: trustedURL))
        XCTAssertNil(try GiftCardMallBridge.parseSummary(message, sourceURL: URL(string: "https://example.com/")!))
    }

    func testGiftCardMallTransactionParserHandlesNestedSearchResults() throws {
        let trustedURL = URL(string: "https://mygift.giftcardmall.com/transactions")!
        let summary = GiftCardMallSummaryCapture(
            balance: 42.50,
            currencyCode: "USD",
            accessToken: "",
            rmsSessionId: ""
        )
        let message: [String: Any] = [
            "namespace": GiftCardMallBridge.handlerName,
            "parserVersion": GiftCardMallBridge.parserVersion,
            "kind": "networkCapture",
            "pageHost": "mygift.giftcardmall.com",
            "url": "/api/card/getCardTransactions",
            "responseBody": #"{"success":true,"result":{"transactionHistory":{"items":[{"transactionDateTime":"2026-08-30T17:30:00Z","transactionAmount":"($4.25)","merchantName":"Neighborhood Market"}]}}}"#,
            "status": 200
        ]

        let result = try XCTUnwrap(GiftCardMallBridge.parseTransactions(message, sourceURL: trustedURL, summary: summary))
        XCTAssertEqual(result.balance, 42.50)
        XCTAssertEqual(result.transactions.count, 1)
        XCTAssertEqual(result.transactions.first?.description, "Neighborhood Market")
        XCTAssertEqual(result.transactions.first?.amount, -4.25)
    }

    func testGiftCardMallTransactionParserHandlesLiveResponseShapeAndFractionalDate() throws {
        let trustedURL = URL(string: "https://mygift.giftcardmall.com/transactions")!
        let summary = GiftCardMallSummaryCapture(
            balance: 18.25,
            currencyCode: "USD",
            accessToken: "",
            rmsSessionId: ""
        )
        let message: [String: Any] = [
            "namespace": GiftCardMallBridge.handlerName,
            "parserVersion": GiftCardMallBridge.parserVersion,
            "kind": "networkCapture",
            "pageHost": "mygift.giftcardmall.com",
            "url": "/api/card/getCardTransactions",
            "responseBody": #"{"success":true,"result":{"transactions":[{"allowDispute":false,"amount":-8.75,"currency":"USD","merchantDescription":"Neighborhood Market","settlementDate":"2026-08-31T14:22:01.1234567","transactionDate":"2026-08-30T12:10:11.7654321","transactionType":"Purchase"}]}}"#,
            "status": 200
        ]

        let result = try XCTUnwrap(GiftCardMallBridge.parseTransactions(message, sourceURL: trustedURL, summary: summary))
        XCTAssertEqual(result.transactions.count, 1)
        XCTAssertEqual(result.transactions.first?.amount, -8.75)
        XCTAssertEqual(result.transactions.first?.description, "Neighborhood Market")
    }

    func testEmbeddedAutofillDoesNotRequireASecondAuthentication() async throws {
        var environment = try AppEnvironment.uiTesting()
        environment.biometricService = RejectingAuthenticationService()
        let id = try environment.cardRepository.addCard(validInput())
        let model = AppModel(environment: environment)

        let credentials = try await model.credentialsForAutofill(id: id)
        XCTAssertEqual(credentials.cardNumber, "4111111111111111")
    }

    func testBulkSaveAllowsMissingCVVAndCanCompleteItLater() async throws {
        let environment = try AppEnvironment.uiTesting()
        let model = AppModel(environment: environment)
        let rows = [
            BulkCardRow(cardNumber: "4111111111111111", expiry: "05/28", code: "123", codeIsPIN: false, sourceRow: 1),
            BulkCardRow(cardNumber: "5555555555554444", expiry: "08/28", code: "0123", codeIsPIN: true, sourceRow: 2)
        ]
        let ids = try model.saveBulkRows(rows).savedCardIDs
        XCTAssertEqual(model.cards.count, 2)
        XCTAssertEqual(try environment.cardRepository.getCredentials(cardID: ids[1]).pin, "0123")
        XCTAssertEqual(try environment.cardRepository.getCredentials(cardID: ids[1]).cvv, "")
        try await model.saveCVV("456", cardID: ids[1])
        let updated = try environment.cardRepository.getCredentials(cardID: ids[1])
        XCTAssertEqual(updated.cvv, "456")
        XCTAssertEqual(updated.pin, "0123")
    }

    func testBulkPartialFailureIdentifiesSavedRowsWithoutDiscardingEarlierInvalidRow() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let store = FakeCredentialStore()
        var writes = 0
        let repository = SwiftDataCardRepository(context: ModelContext(container), credentialStore: store,
            beforeMetadataSave: {
                writes += 1
                if writes == 2 { throw VaultError.validation("Storage unavailable") }
            })
        let model = AppModel(environment: AppEnvironment(cardRepository: repository,
            settingsRepository: InMemorySettingsRepository(), biometricService: AlwaysAllowAuthenticationService(),
            notificationService: NoopNotificationService(), scanner: StaticCardScanner()))
        let rows = BulkCardParser.parse("4000000000000003,09/29,123\n4111111111111111,09/29,123\n5555555555554444,09/29,123")
        do {
            _ = try model.saveBulkRows(rows)
            XCTFail("Expected second write to fail")
        } catch let error as BulkCardSaveError {
            XCTAssertEqual(error.savedRowIDs, [rows[1].id])
            XCTAssertEqual(error.savedIDs.count, 1)
            XCTAssertTrue(error.duplicateRowIDs.isEmpty)
        }
        XCTAssertEqual(model.cards.count, 1)
        XCTAssertEqual(store.records.count, 1)
    }

    private func validInput(nickname: String = "Test") -> CardInput {
        CardInput(cardNumber: "4111111111111111", expiry: "09/29", cvv: "123", nickname: nickname)
    }
}

private struct RejectingAuthenticationService: BiometricAuthenticating {
    func authenticate(reason: String) async -> Bool { false }
}

final class FakeCredentialStore: CredentialStore {
    var records: [String: CardCredentials] = [:]
    var failDelete = false

    func writeNew(_ credentials: CardCredentials, cardID: String) throws {
        if records[cardID] != nil {
            throw VaultError.duplicateCredential
        }
        records[cardID] = credentials
    }

    func update(_ credentials: CardCredentials, cardID: String) throws {
        records[cardID] = credentials
    }

    func read(cardID: String, expiry: String) throws -> CardCredentials {
        guard var credentials = records[cardID] else { throw VaultError.credentialUnavailable }
        credentials.expiry = expiry
        return credentials
    }

    func delete(cardID: String) throws {
        if failDelete {
            throw VaultError.keychainFailure("delete failed")
        }
        records.removeValue(forKey: cardID)
    }
}
