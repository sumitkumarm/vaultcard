import SwiftData
import XCTest
@testable import VaultCard

@MainActor
final class DuplicateCardCleanupTests: XCTestCase {
    func testStartupRemovesOnlyUncheckedExactMatchesAndPreservesOriginalHistory() async throws {
        let (model, repository, _, settings) = try makeModel()
        let original = try repository.addCard(input())
        let transaction = CardTransaction(date: Date(), description: "Purchase", amount: -12)
        try repository.applyBalanceResult(cardID: original, result: BalanceResult(balance: 38, transactions: [transaction], fetchedAt: Date()))
        let copies = try [repository.addCard(input()), repository.addCard(input(cvv: ""))]
        let sameSuffix = try repository.addCard(input(number: "4000000000061111"))
        let checkedCopy = try repository.addCard(input())
        try repository.applyBalanceResult(cardID: checkedCopy, result: BalanceResult(balance: 10, transactions: [], fetchedAt: Date()))
        let before = try XCTUnwrap(repository.getCard(id: original))

        await model.start()

        XCTAssertEqual(Set(model.cards.map(\.id)), [original, sameSuffix, checkedCopy])
        XCTAssertEqual(try repository.getCard(id: original), before)
        XCTAssertEqual(try repository.getCredentials(cardID: original).cvv, "123")
        for id in copies { XCTAssertThrowsError(try repository.getCredentials(cardID: id)) }
        XCTAssertTrue(settings.load().hasCleanedUncheckedDuplicates)
        XCTAssertTrue(model.alertMessage?.contains("Removed 2 unchecked duplicate cards") == true)
        XCTAssertEqual(try model.removeUncheckedDuplicateCards(), 0)
    }

    func testCleanupPreservesMissingSecurityDetailsAndLeavesConflictsAndRenewalsAlone() throws {
        let (model, repository, _, _) = try makeModel()
        let original = try repository.addCard(input(cvv: ""))
        try repository.applyBalanceResult(cardID: original, result: BalanceResult(balance: 25, transactions: [], fetchedAt: Date()))
        let supplement = try repository.addCard(input(pin: "0123"))
        let conflicting = try repository.addCard(input(cvv: "456"))
        let renewal = try repository.addCard(input(expiry: "10/30"))

        XCTAssertEqual(try model.removeUncheckedDuplicateCards(), 1)
        XCTAssertNil(try repository.getCard(id: supplement))
        XCTAssertNotNil(try repository.getCard(id: conflicting))
        XCTAssertNotNil(try repository.getCard(id: renewal))
        let saved = try repository.getCredentials(cardID: original)
        XCTAssertEqual(saved.cvv, "123")
        XCTAssertEqual(saved.pin, "0123")
        XCTAssertEqual(try repository.getCard(id: original)?.balance, 25)
    }

    func testUnavailableCredentialsPreventDeletionAndLeaveCleanupPending() async throws {
        let (model, repository, store, settings) = try makeModel()
        let original = try repository.addCard(input())
        try repository.applyBalanceResult(cardID: original, result: BalanceResult(balance: 25, transactions: [], fetchedAt: Date()))
        let copy = try repository.addCard(input())
        try store.delete(cardID: original)

        await model.start()

        XCTAssertEqual(model.cards.count, 2)
        XCTAssertNotNil(try repository.getCard(id: copy))
        XCTAssertEqual(try repository.getCredentials(cardID: copy).cvv, "123")
        XCTAssertFalse(settings.load().hasCleanedUncheckedDuplicates)
        XCTAssertNotNil(model.alertMessage)
    }

    private func makeModel() throws -> (AppModel, SwiftDataCardRepository, InMemoryCredentialStore, InMemorySettingsRepository) {
        let container = try ModelContainerFactory.makeInMemory()
        let store = InMemoryCredentialStore()
        let repository = SwiftDataCardRepository(context: ModelContext(container), credentialStore: store)
        let settings = InMemorySettingsRepository()
        let model = AppModel(environment: AppEnvironment(cardRepository: repository, settingsRepository: settings,
            biometricService: AlwaysAllowAuthenticationService(), notificationService: NoopNotificationService(), scanner: StaticCardScanner()))
        return (model, repository, store, settings)
    }

    private func input(number: String = "4111111111111111", expiry: String = "09/29", cvv: String = "123", pin: String = "") -> CardInput {
        CardInput(cardNumber: number, expiry: expiry, cvv: cvv, pin: pin)
    }
}
