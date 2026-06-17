import SwiftData
import XCTest
@testable import VaultCard

@MainActor
final class VaultCardTests: XCTestCase {
    func testCardValidationAndNetworkInference() {
        XCTAssertEqual(CardRules.inferNetwork("4111 1111 1111 1111"), .visa)
        XCTAssertEqual(CardRules.inferNetwork("5555 5555 5555 4444"), .mastercard)
        XCTAssertTrue(CardRules.isValidCardNumber("4111 1111 1111 1111"))
        XCTAssertFalse(CardRules.isValidCardNumber("4111 1111 1111 1112"))
        XCTAssertEqual(CardRules.formatExpiryInput("0129"), "01/29")
        XCTAssertTrue(CardRules.validateCVV("123"))
        XCTAssertFalse(CardRules.validateCVV("12"))
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

    private func validInput(nickname: String = "Test") -> CardInput {
        CardInput(cardNumber: "4111111111111111", expiry: "09/29", cvv: "123", nickname: nickname)
    }
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
