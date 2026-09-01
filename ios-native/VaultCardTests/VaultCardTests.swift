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

        let cards = [recentlyUpdated, neverUpdated, failed, stale]
        let upToDateCount = cards.filter { $0.balanceFreshness(at: now) == .upToDate }.count
        let needsRefreshCount = cards.filter { $0.balanceFreshness(at: now) == .needsRefresh }.count
        XCTAssertEqual(upToDateCount + needsRefreshCount, cards.count)
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

    func testCardNumberDisplayAndGiftCardMallAutofillFormatting() {
        XCTAssertEqual(CardRules.formatCardNumber("4111111111111111"), "4111 1111 1111 1111")
        XCTAssertEqual(CardRules.formatCardNumber("5555-5555 5555-4444"), "5555 5555 5555 4444")

        let credentials = CardCredentials(cardNumber: "4111111111111111", expiry: "09/29", cvv: "123", pin: "")
        XCTAssertEqual(credentials.expiryMonth, "09")
        XCTAssertEqual(credentials.expiryYear, "29")

        let script = GiftCardMallBridge.autofillScript(credentials: credentials)
        XCTAssertTrue(script.contains("setTimeout(fill"))
        XCTAssertTrue(script.contains("\"29\""))
        XCTAssertFalse(script.contains("\"2029\""))
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

    func testScanNormalizesSpacedExpiryAndLabeledSecurityCode() {
        let scanner = VisionCardScanner()
        let result = scanner.extractCandidates(from: "Card number: 4111-1111-1111-1111 Expires 09 / 29 Security Code 321")

        XCTAssertEqual(result.cardNumber, "4111111111111111")
        XCTAssertEqual(result.expiry, "09/29")
        XCTAssertEqual(result.cvv, "321")
        XCTAssertEqual(result.confidence, 0.95)
    }

    func testScanRecognizesCVVWithOCRSpacingAndLineBreaks() {
        let scanner = VisionCardScanner()
        let spaced = scanner.extractCandidates(from: "Card 4111 1111 1111 1111\nEXP 09/29\nC V V : 1 2 3")
        XCTAssertEqual(spaced.cvv, "123")

        let lineBreak = scanner.extractCandidates(from: "5555 5555 5555 4444\n12/30\nSecurity Code\n987")
        XCTAssertEqual(lineBreak.cvv, "987")
        XCTAssertEqual(lineBreak.confidence, 0.95)
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

    func testScanRecognizesAlternativeSecurityCodeLabels() {
        let scanner = VisionCardScanner()
        XCTAssertEqual(scanner.extractCandidates(from: "SEC ID: 6 5 4").cvv, "654")
        XCTAssertEqual(scanner.extractCandidates(from: "Card verification number 321").cvv, "321")
        XCTAssertEqual(scanner.extractCandidates(from: "CSC 987").cvv, "987")
    }

    func testSuggestedNicknameIsStableAdjectiveCharacterPair() {
        let first = CardRules.suggestedNickname(for: "4111111111111111")
        XCTAssertEqual(first, CardRules.suggestedNickname(for: "4111 1111 1111 1111"))
        XCTAssertEqual(first.split(separator: " ").count, 2)
        XCTAssertNotEqual(first, CardRules.suggestedNickname(for: "4111111111111111", avoiding: [first]))
    }

    func testLegacySettingsDefaultToScanAndAddNavigationDoesNotDuplicate() throws {
        let legacy = try XCTUnwrap(#"{"onboardingCompleted":true}"#.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertTrue(decoded.onboardingCompleted)
        XCTAssertEqual(decoded.addCardPreference, .scan)

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

        XCTAssertEqual(Set(model.activeCards.map(\.id)), Set([activeID, archivedID1, archivedID2]))
        XCTAssertTrue(model.archivedCards.isEmpty)
        XCTAssertEqual(Set(model.sortedCards.map(\.id)), Set([activeID, archivedID1, archivedID2]))

        try model.archiveCards(ids: [archivedID1, archivedID2])
        XCTAssertEqual(Set(model.activeCards.map(\.id)), [activeID])
        XCTAssertEqual(Set(model.archivedCards.map(\.id)), Set([archivedID1, archivedID2]))
        XCTAssertEqual(Set(model.sortedCards.map(\.id)), [activeID])
        XCTAssertEqual(Set(model.sortedArchivedCards.map(\.id)), Set([archivedID1, archivedID2]))
        XCTAssertTrue(model.archivedCards.allSatisfy(\.isArchived))

        try model.unarchiveCards(ids: [archivedID1])
        XCTAssertEqual(Set(model.activeCards.map(\.id)), Set([activeID, archivedID1]))
        XCTAssertEqual(Set(model.archivedCards.map(\.id)), [archivedID2])

        try model.unarchiveCards(ids: [archivedID2])
        XCTAssertEqual(Set(model.activeCards.map(\.id)), Set([activeID, archivedID1, archivedID2]))
        XCTAssertTrue(model.archivedCards.isEmpty)
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

    func testSchemaV2ArchivedAtDefaultsToNilForLegacyStyleCard() {
        let card = VaultCard(
            id: "legacy-card",
            nickname: "Legacy",
            network: .visa,
            last4: "1111",
            expiry: "09/29",
            balance: 12,
            transactions: [],
            lastFetchedAt: Date(timeIntervalSince1970: 100),
            fetchFailureCount: 0,
            addedAt: Date(timeIntervalSince1970: 0),
            refreshBlockedUntil: nil,
            credentialVersion: 1
        )

        XCTAssertNil(card.archivedAt)
        XCTAssertFalse(card.isArchived)
        XCTAssertNil(SchemaV2.CardMetadataRecord(card: card).archivedAt)
    }

    func testHtmlBalanceParserParsesBalanceAndTransactionsFixture() throws {
        let html = """
        <html>
          <span class="balance-amount">$18.75</span>
          <table class="transactions"><tbody>
            <tr><td>2026-06-01</td><td>Market</td><td>-4.25</td></tr>
          </tbody></table>
        </html>
        """
        let result = try HtmlBalanceParser.parse(html, config: ParserConfig.bundled(), fetchedAt: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(result.balance, 18.75)
        XCTAssertEqual(result.transactions.count, 1)
        XCTAssertEqual(result.transactions.first?.description, "Market")
    }

    func testGiftCardMallBridgeRejectsUntrustedHostAndParsesFixture() throws {
        let trustedURL = URL(string: "https://mygift.giftcardmall.com/")!
        let untrustedURL = URL(string: "https://example.com/")!
        let message: [String: Any] = [
            "namespace": GiftCardMallBridge.handlerName,
            "parserVersion": GiftCardMallBridge.parserVersion,
            "kind": "networkCapture",
            "pageHost": "mygift.giftcardmall.com",
            "url": "/api/card/getCardBalanceSummary",
            "requestBody": #"{"rmsSessionId":"session-1"}"#,
            "responseBody": #"{"success":true,"access_token":"token-1","result":{"balances":{"closingBalance":42.5,"currencyCode":"USD"}}}"#,
            "status": 200
        ]
        XCTAssertNil(try GiftCardMallBridge.parseSummary(message, sourceURL: untrustedURL))
        let summary = try XCTUnwrap(GiftCardMallBridge.parseSummary(message, sourceURL: trustedURL))
        XCTAssertEqual(summary.balance, 42.5)
        XCTAssertEqual(summary.currencyCode, "USD")
    }

    func testGiftCardMallBridgeCapturesDOMBalanceAndInstallsAllCapturePaths() throws {
        let trustedURL = URL(string: "https://mygift.giftcardmall.com/card")!
        let message: [String: Any] = [
            "namespace": GiftCardMallBridge.handlerName,
            "parserVersion": GiftCardMallBridge.parserVersion,
            "kind": "domBalance",
            "pageHost": "mygift.giftcardmall.com",
            "balance": 27.45
        ]

        let summary = try XCTUnwrap(GiftCardMallBridge.parseSummary(message, sourceURL: trustedURL))
        XCTAssertEqual(summary.balance, 27.45)

        let script = GiftCardMallBridge.installScript()
        XCTAssertTrue(script.contains("XMLHttpRequest.prototype.send"))
        XCTAssertTrue(script.contains("MutationObserver"))
        XCTAssertTrue(script.contains("scrollIntoView"))
        XCTAssertTrue(script.contains("domBalance"))
        XCTAssertTrue(script.contains("autoScrollEnabled"))
        XCTAssertTrue(script.contains("if (autoScrollEnabled)"))
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
