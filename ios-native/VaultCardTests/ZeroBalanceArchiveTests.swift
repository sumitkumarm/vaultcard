import SwiftData
import XCTest
@testable import VaultCard

@MainActor
final class ZeroBalanceArchiveTests: XCTestCase {
    func testMissingSettingMigratesToAutomaticArchivingAndPersistsChanges() throws {
        let legacy = try XCTUnwrap(#"{"onboardingCompleted":true}"#.data(using: .utf8))
        let migrated = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertTrue(migrated.archiveZeroBalanceCardsAutomatically)
        XCTAssertTrue(migrated.askAboutZeroBalanceCards)
        let optedOut = try XCTUnwrap(#"{"archiveZeroBalanceCardsAutomatically":false}"#.data(using: .utf8))
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: optedOut).archiveZeroBalanceCardsAutomatically)

        let (model, settings) = try makeModel()
        XCTAssertTrue(model.settings.archiveZeroBalanceCardsAutomatically)
        model.updateSettings { $0.archiveZeroBalanceCardsAutomatically = false }
        XCTAssertFalse(settings.load().archiveZeroBalanceCardsAutomatically)
    }

    func testSuccessfulExactZeroRefreshArchivesOnceAndKeepUndoSurvivesDuplicateCallback() throws {
        let (model, _) = try makeModel()
        let cardID = try model.addCard(input(nickname: "Zero Test"))
        model.beginForegroundRefresh(id: cardID)
        let result = zeroResult

        model.applyForegroundRefresh(id: cardID, result: result)
        let firstPrompt = try XCTUnwrap(model.zeroBalancePrompt)
        XCTAssertEqual(firstPrompt.kind, .autoArchived)
        XCTAssertEqual(firstPrompt.cardName, "Zero Test")
        XCTAssertTrue(try XCTUnwrap(model.cards.first { $0.id == cardID }).isArchived)

        model.applyForegroundRefresh(id: cardID, result: result)
        XCTAssertEqual(model.zeroBalancePrompt, firstPrompt)
        model.resolveZeroBalancePrompt(.keepThisCard)
        model.applyForegroundRefresh(id: cardID, result: result)
        XCTAssertFalse(try XCTUnwrap(model.cards.first { $0.id == cardID }).isArchived)
        XCTAssertNil(model.zeroBalancePrompt)
    }

    func testRememberedKeepAndArchiveChoicesApplyToLaterCardsAndPersist() throws {
        for alwaysArchive in [false, true] {
            var initial = AppSettings()
            initial.archiveZeroBalanceCardsAutomatically = false
            let (model, settings) = try makeModel(initialSettings: initial)
            let cardID = try model.addCard(input())
            model.beginForegroundRefresh(id: cardID)
            model.applyForegroundRefresh(id: cardID, result: zeroResult)
            XCTAssertEqual(model.zeroBalancePrompt?.kind, .offerArchive)

            model.resolveZeroBalancePrompt(alwaysArchive ? .alwaysArchive : .alwaysKeep)
            XCTAssertEqual(try XCTUnwrap(model.cards.first { $0.id == cardID }).isArchived, alwaysArchive)
            let persisted = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings.load()))
            XCTAssertEqual(persisted.archiveZeroBalanceCardsAutomatically, alwaysArchive)
            if !alwaysArchive { XCTAssertFalse(persisted.askAboutZeroBalanceCards) }

            let nextID = try model.addCard(input(number: "5555555555554444"))
            model.beginForegroundRefresh(id: nextID)
            model.applyForegroundRefresh(id: nextID, result: zeroResult)
            XCTAssertEqual(try XCTUnwrap(model.cards.first { $0.id == nextID }).isArchived, alwaysArchive)
            XCTAssertEqual(model.zeroBalancePrompt?.kind, alwaysArchive ? .autoArchived : nil)
        }
    }

    func testArchiveOnceLeavesFutureAutomaticArchivingDisabled() throws {
        var initial = AppSettings()
        initial.archiveZeroBalanceCardsAutomatically = false
        let (model, settings) = try makeModel(initialSettings: initial)
        let first = try model.addCard(input())
        model.beginForegroundRefresh(id: first)
        model.applyForegroundRefresh(id: first, result: zeroResult)
        model.resolveZeroBalancePrompt(.archiveThisCard)
        XCTAssertTrue(try XCTUnwrap(model.cards.first { $0.id == first }).isArchived)
        XCTAssertFalse(settings.load().archiveZeroBalanceCardsAutomatically)
        let second = try model.addCard(input(number: "5555555555554444"))
        model.beginForegroundRefresh(id: second)
        model.applyForegroundRefresh(id: second, result: zeroResult)
        model.resolveZeroBalancePrompt(.notNow)
        model.applyForegroundRefresh(id: second, result: zeroResult)
        XCTAssertFalse(try XCTUnwrap(model.cards.first { $0.id == second }).isArchived)
        XCTAssertNil(model.zeroBalancePrompt)
    }

    func testNewPositiveBalanceClearsStalePromptAndRestoresAutoArchivedCard() throws {
        let (model, _) = try makeModel()
        let cardID = try model.addCard(input())
        model.beginForegroundRefresh(id: cardID)
        model.applyForegroundRefresh(id: cardID, result: zeroResult)
        XCTAssertNotNil(model.zeroBalancePrompt)

        model.applyForegroundRefresh(
            id: cardID,
            result: BalanceResult(balance: 7, transactions: [], fetchedAt: Date())
        )

        XCTAssertNil(model.zeroBalancePrompt)
        XCTAssertFalse(try XCTUnwrap(model.cards.first { $0.id == cardID }).isArchived)
        XCTAssertEqual(model.cards.first { $0.id == cardID }?.balance, 7)

        model.applyForegroundRefresh(id: cardID, result: zeroResult, isAuthoritativeBalance: false)
        XCTAssertNil(model.zeroBalancePrompt)
        XCTAssertFalse(try XCTUnwrap(model.cards.first { $0.id == cardID }).isArchived)
        XCTAssertEqual(model.cards.first { $0.id == cardID }?.balance, 7)
    }

    func testAuthoritativeZeroCanReplaceEarlierPositiveBalance() throws {
        let (model, _) = try makeModel()
        let cardID = try model.addCard(input())
        model.beginForegroundRefresh(id: cardID)
        model.applyForegroundRefresh(id: cardID, result: BalanceResult(balance: 7, transactions: [], fetchedAt: Date()))
        model.applyForegroundRefresh(id: cardID, result: zeroResult)
        XCTAssertEqual(model.cards.first { $0.id == cardID }?.balance, 0)
        XCTAssertTrue(try XCTUnwrap(model.cards.first { $0.id == cardID }).isArchived)
        XCTAssertEqual(model.zeroBalancePrompt?.kind, .autoArchived)
    }

    func testBulkArchiveIncludesOnlyActiveFiniteExactZeroBalances() throws {
        var initial = AppSettings()
        initial.archiveZeroBalanceCardsAutomatically = false
        let (model, _) = try makeModel(initialSettings: initial)
        let zeroID = try model.addCard(input(nickname: "Zero"))
        let positiveID = try model.addCard(input(number: "5555555555554444", nickname: "Positive"))
        let unknownID = try model.addCard(input(number: "4012888888881881", nickname: "Unknown"))
        model.beginForegroundRefresh(id: zeroID)
        model.applyForegroundRefresh(id: zeroID, result: zeroResult)
        model.resolveZeroBalancePrompt(.notNow)
        model.beginForegroundRefresh(id: positiveID)
        model.applyForegroundRefresh(
            id: positiveID,
            result: BalanceResult(balance: 0.01, transactions: [], fetchedAt: Date())
        )

        XCTAssertFalse(model.knownZeroBalanceActiveCardIDs.contains(unknownID))
        XCTAssertEqual(model.knownZeroBalanceActiveCardIDs, [zeroID])

        try model.archiveKnownZeroBalanceCards()
        XCTAssertTrue(try XCTUnwrap(model.cards.first { $0.id == zeroID }).isArchived)
        XCTAssertFalse(try XCTUnwrap(model.cards.first { $0.id == positiveID }).isArchived)
        XCTAssertFalse(try XCTUnwrap(model.cards.first { $0.id == unknownID }).isArchived)
    }

    func testEnablingAutomaticArchivingDoesNotRetroactivelyArchiveKnownZeroCard() throws {
        var initial = AppSettings()
        initial.archiveZeroBalanceCardsAutomatically = false
        let (model, _) = try makeModel(initialSettings: initial)
        let cardID = try model.addCard(input())
        model.beginForegroundRefresh(id: cardID)
        model.applyForegroundRefresh(id: cardID, result: zeroResult)
        model.resolveZeroBalancePrompt(.notNow)
        XCTAssertFalse(try XCTUnwrap(model.cards.first { $0.id == cardID }).isArchived)

        model.updateSettings { $0.archiveZeroBalanceCardsAutomatically = true }

        XCTAssertFalse(try XCTUnwrap(model.cards.first { $0.id == cardID }).isArchived)
    }

    private var zeroResult: BalanceResult {
        BalanceResult(balance: 0, transactions: [], fetchedAt: Date())
    }

    private func input(
        number: String = "4111111111111111",
        nickname: String? = nil
    ) -> CardInput {
        CardInput(cardNumber: number, expiry: "09/29", cvv: "123", nickname: nickname)
    }

    private func makeModel(
        initialSettings: AppSettings = AppSettings()
    ) throws -> (AppModel, InMemorySettingsRepository) {
        let container = try ModelContainerFactory.makeInMemory()
        let settings = InMemorySettingsRepository()
        settings.save(initialSettings)
        let environment = AppEnvironment(
            cardRepository: SwiftDataCardRepository(
                context: ModelContext(container),
                credentialStore: InMemoryCredentialStore()
            ),
            settingsRepository: settings,
            biometricService: AlwaysAllowAuthenticationService(),
            notificationService: NoopNotificationService(),
            scanner: StaticCardScanner()
        )
        return (AppModel(environment: environment), settings)
    }
}
