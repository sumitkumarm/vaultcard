import AVFoundation
import CoreImage
import Foundation
import LocalAuthentication
import Observation
import Security
import SwiftData
import SwiftUI
import UIKit
import UserNotifications
import Vision
import WebKit

enum CardNetwork: String, Codable, CaseIterable {
    case visa
    case mastercard
    case unknown

    var displayName: String { rawValue.uppercased() }
}

enum CardSortOption: String, Codable, CaseIterable, Identifiable {
    case dateAddedNewest
    case balanceLowToHigh
    case balanceHighToLow
    case expirySoonest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dateAddedNewest:
            return "Newest"
        case .balanceLowToHigh:
            return "Balance Low-High"
        case .balanceHighToLow:
            return "Balance High-Low"
        case .expirySoonest:
            return "Expiry Soonest"
        }
    }

    var listHeading: String {
        switch self {
        case .dateAddedNewest:
            return "Newest First"
        case .balanceLowToHigh:
            return "Lowest Balance First"
        case .balanceHighToLow:
            return "Highest Balance First"
        case .expirySoonest:
            return "Expiring Soonest"
        }
    }
}

enum AddCardPreference: String, Codable, CaseIterable, Identifiable {
    case scan
    case manual

    var id: String { rawValue }
    var label: String { self == .scan ? "Scan Card" : "Enter Manually" }
}

struct VaultCard: Identifiable, Equatable {
    enum BalanceFreshness: Equatable {
        case upToDate
        case needsRefresh
    }

    static let balanceFreshnessInterval: TimeInterval = 7 * 24 * 60 * 60

    var id: String
    var nickname: String?
    var network: CardNetwork
    var last4: String
    var expiry: String
    var balance: Double?
    var transactions: [CardTransaction]
    var lastFetchedAt: Date?
    var fetchFailureCount: Int
    var addedAt: Date
    var refreshBlockedUntil: Date?
    var credentialVersion: Int
    var archivedAt: Date?

    init(
        id: String,
        nickname: String?,
        network: CardNetwork,
        last4: String,
        expiry: String,
        balance: Double?,
        transactions: [CardTransaction],
        lastFetchedAt: Date?,
        fetchFailureCount: Int,
        addedAt: Date,
        refreshBlockedUntil: Date?,
        credentialVersion: Int,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.nickname = nickname
        self.network = network
        self.last4 = last4
        self.expiry = expiry
        self.balance = balance
        self.transactions = transactions
        self.lastFetchedAt = lastFetchedAt
        self.fetchFailureCount = fetchFailureCount
        self.addedAt = addedAt
        self.refreshBlockedUntil = refreshBlockedUntil
        self.credentialVersion = credentialVersion
        self.archivedAt = archivedAt
    }

    var displayName: String {
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed! : "**** \(last4)"
    }

    var isArchived: Bool { archivedAt != nil }

    func balanceFreshness(at date: Date = Date(), refreshAfterDays: Int = 7) -> BalanceFreshness {
        guard fetchFailureCount == 0, let lastFetchedAt else { return .needsRefresh }
        let boundedDays = min(max(refreshAfterDays, 1), 365)
        let freshnessInterval = TimeInterval(boundedDays) * 24 * 60 * 60
        return date.timeIntervalSince(lastFetchedAt) < freshnessInterval
            ? .upToDate
            : .needsRefresh
    }
}

struct CardTransaction: Identifiable, Equatable, Codable, Hashable {
    var id: String = UUID().uuidString
    var date: Date
    var description: String
    var amount: Double
}

struct CardCredentials: Codable, Equatable {
    var cardNumber: String
    var expiry: String
    var cvv: String
    var pin: String

    var last4: String { String(cardNumber.suffix(4)) }
    var expiryMonth: String { expiry.split(separator: "/").first.map { String($0).leftPadded(to: 2) } ?? "00" }
    var expiryYear: String { expiry.split(separator: "/").last.map { String($0).leftPadded(to: 2) } ?? "00" }
}

struct CardInput: Equatable {
    var cardNumber: String
    var expiry: String
    var cvv: String
    var pin: String = ""
    var nickname: String?

    var credentials: CardCredentials {
        CardCredentials(cardNumber: cardNumber, expiry: expiry, cvv: cvv, pin: pin)
    }

    var network: CardNetwork { CardRules.inferNetwork(cardNumber) }
}

struct NotificationPreferences: Codable, Equatable {
    var expiryWarning = true
    var expiryWarningDays = 30 {
        didSet { expiryWarningDays = min(max(expiryWarningDays, 1), 365) }
    }
    var privacyPreservingContent = true

    init(expiryWarning: Bool = true, expiryWarningDays: Int = 30, privacyPreservingContent: Bool = true) {
        self.expiryWarning = expiryWarning
        self.expiryWarningDays = min(max(expiryWarningDays, 1), 365)
        self.privacyPreservingContent = privacyPreservingContent
    }
    private enum CodingKeys: String, CodingKey { case expiryWarning, expiryWarningDays, privacyPreservingContent }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        expiryWarning = try values.decodeIfPresent(Bool.self, forKey: .expiryWarning) ?? true
        expiryWarningDays = min(max(try values.decodeIfPresent(Int.self, forKey: .expiryWarningDays) ?? 30, 1), 365)
        privacyPreservingContent = try values.decodeIfPresent(Bool.self, forKey: .privacyPreservingContent) ?? true
    }
}

struct AppSettings: Codable, Equatable {
    var onboardingCompleted = false
    var appLockEnabled = false
    var sortOption = CardSortOption.dateAddedNewest
    var notificationPreferences = NotificationPreferences()
    var refreshAfterDays = 7 {
        didSet { refreshAfterDays = min(max(refreshAfterDays, 1), 365) }
    }
    var addCardPreference = AddCardPreference.scan
    var hasSeenSwipeArchiveConfirmation = false
    var archiveZeroBalanceCardsAutomatically = true
    var askAboutZeroBalanceCards = true
    var hasCleanedUncheckedDuplicates = false
    var transactionInitialLoadOverrides: [String: Bool] = [:]

    private enum CodingKeys: String, CodingKey {
        case onboardingCompleted
        case appLockEnabled
        case sortOption
        case notificationPreferences
        case refreshAfterDays
        case addCardPreference
        case hasSeenSwipeArchiveConfirmation
        case archiveZeroBalanceCardsAutomatically
        case askAboutZeroBalanceCards
        case hasCleanedUncheckedDuplicates
        case transactionInitialLoadOverrides
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        onboardingCompleted = try values.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        appLockEnabled = try values.decodeIfPresent(Bool.self, forKey: .appLockEnabled) ?? false
        sortOption = try values.decodeIfPresent(CardSortOption.self, forKey: .sortOption) ?? .dateAddedNewest
        notificationPreferences = try values.decodeIfPresent(NotificationPreferences.self, forKey: .notificationPreferences) ?? NotificationPreferences()
        refreshAfterDays = min(max(try values.decodeIfPresent(Int.self, forKey: .refreshAfterDays) ?? 7, 1), 365)
        addCardPreference = try values.decodeIfPresent(AddCardPreference.self, forKey: .addCardPreference) ?? .scan
        hasSeenSwipeArchiveConfirmation = try values.decodeIfPresent(Bool.self, forKey: .hasSeenSwipeArchiveConfirmation) ?? false
        archiveZeroBalanceCardsAutomatically = try values.decodeIfPresent(Bool.self, forKey: .archiveZeroBalanceCardsAutomatically) ?? true
        askAboutZeroBalanceCards = try values.decodeIfPresent(Bool.self, forKey: .askAboutZeroBalanceCards) ?? true
        hasCleanedUncheckedDuplicates = try values.decodeIfPresent(Bool.self, forKey: .hasCleanedUncheckedDuplicates) ?? false
        transactionInitialLoadOverrides = try values.decodeIfPresent([String: Bool].self, forKey: .transactionInitialLoadOverrides) ?? [:]
    }
}

struct ZeroBalancePrompt: Identifiable, Equatable {
    enum Kind: Equatable { case autoArchived, offerArchive }

    let id: UUID
    let cardID: String
    let cardName: String
    let last4: String
    let kind: Kind
}

enum ZeroBalancePromptAction {
    case done
    case keepThisCard
    case notNow
    case alwaysKeep
    case archiveThisCard
    case alwaysArchive
}

struct BalanceResult: Equatable {
    var balance: Double
    var transactions: [CardTransaction]
    var fetchedAt: Date
}

struct ScanCandidate: Codable, Hashable {
    var cardNumber: String?
    var expiry: String?
    var cvv: String?
    var recognizedText: String
    var network: CardNetwork
    var confidence: Double

    var hasCandidateData: Bool {
        cardNumber != nil || expiry != nil || cvv != nil
    }
}

enum CardRules {
    private static let nicknameAdjectives = [
        "Brave", "Clever", "Cosmic", "Golden", "Noble", "Swift", "Velvet", "Wandering",
        "Bright", "Daring", "Electric", "Lucky", "Mighty", "Radiant", "Silver", "Stellar"
    ]
    private static let nicknameCharacters = [
        "Athena", "Merlin", "Mulan", "Odysseus", "Orion", "Phoenix", "Robin", "Sherlock",
        "Artemis", "Gandalf", "Leia", "Loki", "Ripley", "Spock", "Storm", "Zorro"
    ]

    static func inferNetwork(_ cardNumber: String) -> CardNetwork {
        let sanitized = digitsOnly(cardNumber)
        if sanitized.hasPrefix("4") { return .visa }
        if sanitized.count >= 2, let firstTwo = Int(sanitized.prefix(2)), (51...55).contains(firstTwo) {
            return .mastercard
        }
        if sanitized.count >= 4, let firstFour = Int(sanitized.prefix(4)), (2221...2720).contains(firstFour) {
            return .mastercard
        }
        return .unknown
    }

    static func isValidCardNumber(_ cardNumber: String) -> Bool {
        let sanitized = digitsOnly(cardNumber)
        guard sanitized.count == 16, sanitized.allSatisfy(\.isNumber), inferNetwork(sanitized) != .unknown else {
            return false
        }
        var sum = 0
        var doubleDigit = false
        for scalar in sanitized.reversed() {
            var digit = Int(String(scalar)) ?? 0
            if doubleDigit {
                digit *= 2
                if digit > 9 { digit -= 9 }
            }
            sum += digit
            doubleDigit.toggle()
        }
        return sum % 10 == 0
    }

    static func validateExpiry(_ value: String) -> Bool {
        value.range(of: #"^(0[1-9]|1[0-2])\/([0-9]{2})$"#, options: .regularExpression) != nil
    }

    static func validateCVV(_ value: String) -> Bool {
        value.range(of: #"^\d{3,4}$"#, options: .regularExpression) != nil
    }

    static func formatExpiryInput(_ value: String) -> String {
        let digits = String(digitsOnly(value).prefix(4))
        guard digits.count > 2 else { return digits }
        return "\(digits.prefix(2))/\(digits.dropFirst(2))"
    }

    static func formatCardNumber(_ value: String) -> String {
        let digits = String(digitsOnly(value).prefix(16))
        return stride(from: 0, to: digits.count, by: 4).map { start in
            let lower = digits.index(digits.startIndex, offsetBy: start)
            let upper = digits.index(lower, offsetBy: min(4, digits.count - start))
            return String(digits[lower..<upper])
        }.joined(separator: " ")
    }

    static func mask(last4: String) -> String { "**** **** **** \(last4)" }
    static func digitsOnly(_ value: String) -> String { value.filter(\.isNumber) }

    static func suggestedNickname(for cardNumber: String) -> String {
        suggestedNickname(for: cardNumber, avoiding: [])
    }

    static func suggestedNickname(for cardNumber: String, avoiding existingNames: Set<String>) -> String {
        let digits = digitsOnly(cardNumber)
        let seed = digits.reduce(0) { ($0 &* 31 &+ ($1.wholeNumberValue ?? 0)) % 10_000 }
        let normalizedExisting = Set(existingNames.map { $0.lowercased() })
        let combinations = nicknameAdjectives.count * nicknameCharacters.count
        for offset in 0..<combinations {
            let adjective = nicknameAdjectives[(seed + offset) % nicknameAdjectives.count]
            let characterIndex = (seed / nicknameAdjectives.count + offset * 7) % nicknameCharacters.count
            let suggestion = "\(adjective) \(nicknameCharacters[characterIndex])"
            if !normalizedExisting.contains(suggestion.lowercased()) { return suggestion }
        }
        return "Vault Card \(existingNames.count + 1)"
    }

    static func sorted(_ cards: [VaultCard], by option: CardSortOption) -> [VaultCard] {
        switch option {
        case .dateAddedNewest:
            return cards.sorted {
                if $0.addedAt != $1.addedAt { return $0.addedAt > $1.addedAt }
                return $0.id < $1.id
            }
        case .balanceLowToHigh:
            return cards.sorted {
                if ($0.balance ?? 0) != ($1.balance ?? 0) { return ($0.balance ?? 0) < ($1.balance ?? 0) }
                return $0.id < $1.id
            }
        case .balanceHighToLow:
            return cards.sorted {
                if ($0.balance ?? 0) != ($1.balance ?? 0) { return ($0.balance ?? 0) > ($1.balance ?? 0) }
                return $0.id < $1.id
            }
        case .expirySoonest:
            return cards.sorted {
                if $0.expiry != $1.expiry { return $0.expiry < $1.expiry }
                return $0.id < $1.id
            }
        }
    }
}

extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: "0", count: length - count) + self
    }
}

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [CardMetadataRecord.self, TransactionRecord.self]
    }

    @Model
    final class CardMetadataRecord {
        @Attribute(.unique) var id: String
        var nickname: String?
        var networkRaw: String
        var last4: String
        var expiry: String
        var balance: Double?
        var lastFetchedAt: Date?
        var fetchFailureCount: Int
        var addedAt: Date
        var refreshBlockedUntil: Date?
        var credentialVersion: Int

        init(card: VaultCard) {
            id = card.id
            nickname = card.nickname
            networkRaw = card.network.rawValue
            last4 = card.last4
            expiry = card.expiry
            balance = card.balance
            lastFetchedAt = card.lastFetchedAt
            fetchFailureCount = card.fetchFailureCount
            addedAt = card.addedAt
            refreshBlockedUntil = card.refreshBlockedUntil
            credentialVersion = card.credentialVersion
        }
    }

    @Model
    final class TransactionRecord {
        @Attribute(.unique) var id: String
        var cardId: String
        var date: Date
        var transactionDescription: String
        var amount: Double

        init(cardId: String, transaction: CardTransaction) {
            id = transaction.id
            self.cardId = cardId
            date = transaction.date
            transactionDescription = transaction.description
            amount = transaction.amount
        }
    }
}

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [CardMetadataRecord.self, TransactionRecord.self]
    }

    @Model
    final class CardMetadataRecord {
        @Attribute(.unique) var id: String
        var nickname: String?
        var networkRaw: String
        var last4: String
        var expiry: String
        var balance: Double?
        var lastFetchedAt: Date?
        var fetchFailureCount: Int
        var addedAt: Date
        var refreshBlockedUntil: Date?
        var credentialVersion: Int
        var archivedAt: Date?

        init(card: VaultCard) {
            id = card.id
            nickname = card.nickname
            networkRaw = card.network.rawValue
            last4 = card.last4
            expiry = card.expiry
            balance = card.balance
            lastFetchedAt = card.lastFetchedAt
            fetchFailureCount = card.fetchFailureCount
            addedAt = card.addedAt
            refreshBlockedUntil = card.refreshBlockedUntil
            credentialVersion = card.credentialVersion
            archivedAt = card.archivedAt
        }
    }

    @Model
    final class TransactionRecord {
        @Attribute(.unique) var id: String
        var cardId: String
        var date: Date
        var transactionDescription: String
        var amount: Double

        init(cardId: String, transaction: CardTransaction) {
            id = transaction.id
            self.cardId = cardId
            date = transaction.date
            transactionDescription = transaction.description
            amount = transaction.amount
        }
    }
}

enum VaultCardSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] {
        [MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}

enum ModelContainerFactory {
    static func makePersistent() throws -> ModelContainer {
        try ModelContainer(
            for: Schema([SchemaV2.CardMetadataRecord.self, SchemaV2.TransactionRecord.self]),
            migrationPlan: VaultCardSchemaMigrationPlan.self
        )
    }

    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Schema([SchemaV2.CardMetadataRecord.self, SchemaV2.TransactionRecord.self]),
            migrationPlan: VaultCardSchemaMigrationPlan.self,
            configurations: [configuration]
        )
    }
}

enum VaultError: Error, LocalizedError, Equatable {
    case cardNotFound
    case credentialUnavailable
    case duplicateCredential
    case keychainFailure(String)
    case validation(String)
    case refresh(String)
    case webBridge(String)

    var errorDescription: String? {
        switch self {
        case .cardNotFound:
            return "Card not found."
        case .credentialUnavailable:
            return "Credential unavailable. Re-enter this card to restore secure details."
        case .duplicateCredential:
            return "A credential already exists for this card."
        case .keychainFailure(let message):
            return message
        case .validation(let message):
            return message
        case .refresh(let message):
            return message
        case .webBridge(let message):
            return message
        }
    }
}

protocol CredentialStore {
    func writeNew(_ credentials: CardCredentials, cardID: String) throws
    func update(_ credentials: CardCredentials, cardID: String) throws
    func read(cardID: String, expiry: String) throws -> CardCredentials
    func delete(cardID: String) throws
}

@MainActor
protocol CardRepository {
    func getCards() throws -> [VaultCard]
    func getCard(id: String) throws -> VaultCard?
    func addCard(_ input: CardInput) throws -> String
    func deleteCard(id: String) throws
    func deleteCards(ids: Set<String>) throws
    func archiveCard(id: String) throws
    func archiveCards(ids: Set<String>) throws
    func unarchiveCard(id: String) throws
    func unarchiveCards(ids: Set<String>) throws
    func updateCredentials(cardID: String, credentials: CardCredentials) throws
    func getCredentials(cardID: String) throws -> CardCredentials
    func applyBalanceResult(cardID: String, result: BalanceResult) throws
}

protocol SettingsRepository {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

protocol BiometricAuthenticating {
    func authenticate(reason: String) async -> Bool
}

enum ScanRecognitionMode {
    case live
    case still
}

protocol CardScanning {
    func extractCandidates(from image: CGImage, mode: ScanRecognitionMode) async throws -> ScanCandidate
    func extractCandidates(from text: String) -> ScanCandidate
}

@MainActor
protocol NotificationScheduling {
    func requestAuthorization() async
    func syncForCard(_ card: VaultCard, preferences: NotificationPreferences) async
    func synchronize(cards: [VaultCard], preferences: NotificationPreferences) async
    func scheduleUseReminder(for card: VaultCard, at date: Date) async throws
    func cancelUseReminder(cardID: String) async
    func useReminders() -> [String: CardUseReminder]
    func notificationsEnabled() async -> Bool
    func consumePendingReminderCardID() -> String?
}

extension NotificationScheduling {
    func synchronize(cards: [VaultCard], preferences: NotificationPreferences) async {
        for card in cards { await syncForCard(card, preferences: preferences) }
    }
    func scheduleUseReminder(for card: VaultCard, at date: Date) async throws {
        throw VaultError.validation("Reminders are unavailable.")
    }
    func cancelUseReminder(cardID: String) async {}
    func useReminders() -> [String: CardUseReminder] { [:] }
    func notificationsEnabled() async -> Bool { false }
    func consumePendingReminderCardID() -> String? { nil }
}

final class KeychainCredentialStore: CredentialStore {
    private let service = "com.vaultcard.ios.credentials"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func writeNew(_ credentials: CardCredentials, cardID: String) throws {
        if try exists(cardID: cardID) {
            throw VaultError.duplicateCredential
        }
        try add(credentials, cardID: cardID)
    }

    func update(_ credentials: CardCredentials, cardID: String) throws {
        let data = try encoder.encode(credentials)
        let query = baseQuery(cardID: cardID)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            try add(credentials, cardID: cardID)
            return
        }
        guard status == errSecSuccess else { throw VaultError.keychainFailure("Unable to update credentials.") }
    }

    func read(cardID: String, expiry: String) throws -> CardCredentials {
        var query = baseQuery(cardID: cardID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw VaultError.credentialUnavailable }
        guard status == errSecSuccess, let data = item as? Data else {
            throw VaultError.keychainFailure("Unable to read credentials.")
        }
        var credentials = try decoder.decode(CardCredentials.self, from: data)
        credentials.expiry = expiry
        return credentials
    }

    func delete(cardID: String) throws {
        let status = SecItemDelete(baseQuery(cardID: cardID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.keychainFailure("Unable to delete credentials.")
        }
    }

    private func exists(cardID: String) throws -> Bool {
        var query = baseQuery(cardID: cardID)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound { return false }
        throw VaultError.keychainFailure("Unable to check credentials.")
    }

    private func add(_ credentials: CardCredentials, cardID: String) throws {
        let data = try encoder.encode(credentials)
        var query = baseQuery(cardID: cardID)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychainFailure("Unable to save credentials.") }
    }

    private func baseQuery(cardID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "card:\(cardID):credentials"
        ]
    }
}

final class InMemoryCredentialStore: CredentialStore {
    private var records: [String: CardCredentials] = [:]

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
        records.removeValue(forKey: cardID)
    }
}

@MainActor
final class SwiftDataCardRepository: CardRepository {
    private let context: ModelContext
    private let credentialStore: CredentialStore
    private let now: () -> Date
    private let uuid: () -> String
    private let beforeMetadataSave: (() throws -> Void)?

    init(
        context: ModelContext,
        credentialStore: CredentialStore,
        now: @escaping () -> Date = Date.init,
        uuid: @escaping () -> String = { UUID().uuidString },
        beforeMetadataSave: (() throws -> Void)? = nil
    ) {
        self.context = context
        self.credentialStore = credentialStore
        self.now = now
        self.uuid = uuid
        self.beforeMetadataSave = beforeMetadataSave
    }

    func getCards() throws -> [VaultCard] {
        let records = try context.fetch(FetchDescriptor<SchemaV2.CardMetadataRecord>())
        let transactionRecords = try context.fetch(FetchDescriptor<SchemaV2.TransactionRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))
        let transactionsByCard = Dictionary(grouping: transactionRecords, by: \.cardId).mapValues { records in
            records.map {
                CardTransaction(id: $0.id, date: $0.date, description: $0.transactionDescription, amount: $0.amount)
            }
        }
        return try records.map {
            try makeCard(from: $0, loadedTransactions: transactionsByCard[$0.id] ?? [])
        }
    }

    func getCard(id: String) throws -> VaultCard? {
        guard let record = try findRecord(id: id) else { return nil }
        return try makeCard(from: record)
    }

    func addCard(_ input: CardInput) throws -> String {
        let cardID = uuid()
        let sanitized = CardRules.digitsOnly(input.cardNumber)
        let credentials = CardCredentials(cardNumber: sanitized, expiry: input.expiry, cvv: input.cvv, pin: input.pin)
        try credentialStore.writeNew(credentials, cardID: cardID)
        do {
            let card = VaultCard(
                id: cardID,
                nickname: input.nickname?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                network: input.network,
                last4: credentials.last4,
                expiry: input.expiry,
                balance: nil,
                transactions: [],
                lastFetchedAt: nil,
                fetchFailureCount: 0,
                addedAt: now(),
                refreshBlockedUntil: nil,
                credentialVersion: 1
            )
            context.insert(SchemaV2.CardMetadataRecord(card: card))
            try beforeMetadataSave?()
            try context.save()
            return cardID
        } catch {
            context.rollback()
            try? credentialStore.delete(cardID: cardID)
            throw error
        }
    }

    func deleteCard(id: String) throws {
        try deleteCards(ids: [id])
    }

    func deleteCards(ids: Set<String>) throws {
        guard !ids.isEmpty else { return }
        let sortedIDs = ids.sorted()
        let records = try sortedIDs.compactMap { try findRecord(id: $0) }

        // Remove secure credentials first. Keychain deletion is idempotent, and no
        // metadata is touched until every credential deletion succeeds.
        for id in sortedIDs {
            try credentialStore.delete(cardID: id)
        }
        for record in records {
            context.delete(record)
        }
        for id in sortedIDs {
            try deleteTransactions(cardID: id)
        }
        try context.save()
    }

    func archiveCard(id: String) throws {
        try archiveCards(ids: [id])
    }

    func archiveCards(ids: Set<String>) throws {
        try setArchived(true, ids: ids)
    }

    func unarchiveCard(id: String) throws {
        try unarchiveCards(ids: [id])
    }

    func unarchiveCards(ids: Set<String>) throws {
        try setArchived(false, ids: ids)
    }

    func updateCredentials(cardID: String, credentials: CardCredentials) throws {
        guard let record = try findRecord(id: cardID) else { throw VaultError.cardNotFound }
        let previous = try? credentialStore.read(cardID: cardID, expiry: record.expiry)
        try credentialStore.update(credentials, cardID: cardID)
        do {
            record.expiry = credentials.expiry
            record.last4 = credentials.last4
            record.networkRaw = CardRules.inferNetwork(credentials.cardNumber).rawValue
            record.credentialVersion += 1
            try context.save()
        } catch {
            if let previous {
                try? credentialStore.update(previous, cardID: cardID)
            } else {
                try? credentialStore.delete(cardID: cardID)
            }
            throw error
        }
    }

    func getCredentials(cardID: String) throws -> CardCredentials {
        guard let record = try findRecord(id: cardID) else { throw VaultError.cardNotFound }
        return try credentialStore.read(cardID: cardID, expiry: record.expiry)
    }

    func applyBalanceResult(cardID: String, result: BalanceResult) throws {
        guard let record = try findRecord(id: cardID) else { throw VaultError.cardNotFound }
        record.balance = result.balance
        record.lastFetchedAt = result.fetchedAt
        record.fetchFailureCount = 0
        record.refreshBlockedUntil = result.fetchedAt.addingTimeInterval(15 * 60)
        try deleteTransactions(cardID: cardID)
        for transaction in result.transactions {
            context.insert(SchemaV2.TransactionRecord(cardId: cardID, transaction: transaction))
        }
        try context.save()
    }

    private func findRecord(id: String) throws -> SchemaV2.CardMetadataRecord? {
        var descriptor = FetchDescriptor<SchemaV2.CardMetadataRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func transactions(cardID: String) throws -> [CardTransaction] {
        let descriptor = FetchDescriptor<SchemaV2.TransactionRecord>(
            predicate: #Predicate { $0.cardId == cardID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor).map {
            CardTransaction(id: $0.id, date: $0.date, description: $0.transactionDescription, amount: $0.amount)
        }
    }

    private func deleteTransactions(cardID: String) throws {
        let descriptor = FetchDescriptor<SchemaV2.TransactionRecord>(
            predicate: #Predicate { $0.cardId == cardID }
        )
        for record in try context.fetch(descriptor) {
            context.delete(record)
        }
    }

    private func setArchived(_ archived: Bool, ids: Set<String>) throws {
        guard !ids.isEmpty else { return }
        let sortedIDs = ids.sorted()
        let records = try sortedIDs.map { id -> SchemaV2.CardMetadataRecord in
            guard let record = try findRecord(id: id) else { throw VaultError.cardNotFound }
            return record
        }
        let archiveDate = archived ? now() : nil
        for record in records {
            record.archivedAt = archiveDate
        }
        try context.save()
    }

    private func makeCard(from record: SchemaV2.CardMetadataRecord, loadedTransactions: [CardTransaction]? = nil) throws -> VaultCard {
        VaultCard(
            id: record.id,
            nickname: record.nickname,
            network: CardNetwork(rawValue: record.networkRaw) ?? .unknown,
            last4: record.last4,
            expiry: record.expiry,
            balance: record.balance,
            transactions: try loadedTransactions ?? transactions(cardID: record.id),
            lastFetchedAt: record.lastFetchedAt,
            fetchFailureCount: record.fetchFailureCount,
            addedAt: record.addedAt,
            refreshBlockedUntil: record.refreshBlockedUntil,
            credentialVersion: record.credentialVersion,
            archivedAt: record.archivedAt
        )
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

final class UserDefaultsSettingsRepository: SettingsRepository {
    private let defaults: UserDefaults
    private let key = "app_settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key) else { return AppSettings() }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    func save(_ settings: AppSettings) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: key)
    }
}

final class LocalAuthenticationService: BiometricAuthenticating {
    func authenticate(reason: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let context = LAContext()
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

struct AlwaysAllowAuthenticationService: BiometricAuthenticating {
    func authenticate(reason: String) async -> Bool { true }
}

struct GiftCardMallSummaryCapture: Equatable {
    var balance: Double
    var currencyCode: String
    var accessToken: String
    var rmsSessionId: String
}

enum GiftCardMallBridge {
    static let handlerName = "vaultcardGiftCardMallBridge"
    static let parserVersion = 1
    static let allowedHosts: Set<String> = [
        "mygift.giftcardmall.com",
        "www.mygift.giftcardmall.com",
        "mcgift.giftcardmall.com",
        "www.mycardwallet.com"
    ]
    private static let legacyHosts: Set<String> = ["mygift.giftcardmall.com", "www.mygift.giftcardmall.com", "mcgift.giftcardmall.com"]
    static let siteURL = URL(string: "https://www.mycardwallet.com/chs/mygift/")!

    static func balanceURL(for network: CardNetwork) -> URL {
        network == .mastercard ? URL(string: "https://www.mycardwallet.com/chs/mcgift/")! : siteURL
    }

    static func isAllowed(_ url: URL?) -> Bool {
        guard let url,
              url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased(),
              allowedHosts.contains(host)
        else { return false }

        if legacyHosts.contains(host) { return true }
        let path = url.path
        return ["/chs/mygift", "/chs/mcgift"].contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    static func isTrustedMainFrame(isMainFrame: Bool, scheme: String?, host: String?, port: Int, pageURL: URL?) -> Bool {
        guard isMainFrame,
              isAllowed(pageURL),
              scheme?.lowercased() == "https",
              host?.lowercased() == pageURL?.host?.lowercased()
        else { return false }
        return (port == 0 ? 443 : port) == (pageURL?.port ?? 443)
    }

    static func installScript() -> String {
        """
        (() => {
          if (window.__vaultCardGiftCardMallBridgeInstalled) { return; }
          window.__vaultCardGiftCardMallBridgeInstalled = true;
          const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(handlerName);
          if (!handler) { return; }
          const post = (payload) => {
            try {
              handler.postMessage(Object.assign({
                namespace: '\(handlerName)',
                parserVersion: \(parserVersion),
                pageHost: window.location.hostname
              }, payload));
            } catch (_) {}
          };

          const cardSelectors = [
            '#credit-card-number',
            'input[name="cardNumber"]',
            'input[id*="cardNumber"]',
            'input[autocomplete="cc-number"]',
            'input[inputmode="numeric"]'
          ];
          let autoScrollEnabled = true;
          window.__vaultCardScrollToForm = (force = false) => {
            if (!force && !autoScrollEnabled) { return false; }
            const field = cardSelectors.map(selector => document.querySelector(selector)).find(Boolean);
            if (!field) { return false; }
            const target = field.closest('form') || field;
            target.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'smooth' });
            return true;
          };

          const stopAutoScroll = () => { autoScrollEnabled = false; };
          document.addEventListener('pointerdown', stopAutoScroll, true);
          document.addEventListener('touchstart', stopAutoScroll, true);

          document.addEventListener('submit', stopAutoScroll, true);
          document.addEventListener('click', event => {
            const control = event.target && event.target.closest && event.target.closest('button, input[type="submit"]');
            if (!control) { return; }
            const type = (control.getAttribute('type') || '').toLowerCase();
            if (control.tagName === 'BUTTON' || type === 'submit') { stopAutoScroll(); }
          }, true);

          let lastDOMBalance = null;
          const inspectBalance = () => {
            // Read the labeled summary even when it is scrolled offscreen.
            // Historical transaction balances and initial balances are never current funds.
            const normalize = element => (element.textContent || '').replace(/\\s+/g, ' ').trim();
            for (const label of document.querySelectorAll('body *')) {
              if (!/^available\\s+balance(?:\\s|:|\\$|$)/i.test(normalize(label))) { continue; }
              if (!label.getClientRects().length || label.closest('table, [role="grid"], [role="row"]')) { continue; }
              let element = label;
              for (let depth = 0; element && depth < 4; depth++, element = element.parentElement) {
                const match = normalize(element).replace(/,/g, '').match(/^available\\s+balance\\s*:?\\s*\\$\\s*([0-9]+(?:\\.[0-9]{1,2})?)$/i);
                if (!match) { continue; }
                const balance = Number(match[1]);
                if (!Number.isFinite(balance) || balance < 0) { return; }
                if (balance === lastDOMBalance) { return; }
                lastDOMBalance = balance;
                post({ kind: 'domBalance', source: 'availableBalanceSummary', balance });
                return;
              }
            }
          };

          const isCardResponse = url => typeof url === 'string' && (
            url.includes('/api/card/getCardBalanceSummary') || url.includes('/api/card/getCardTransactions')
          );
          const originalFetch = window.fetch;
          window.fetch = async (...args) => {
            const response = await originalFetch(...args);
            const url = typeof args[0] === 'string' ? args[0] : ((args[0] && args[0].url) || String(args[0] || ''));
            if (isCardResponse(url)) {
              try {
                const request = args[1] || {};
                // Observe only card responses, without delaying the site's own fetch.
                response.clone().text().then(text => post({
                  kind: 'networkCapture',
                  url,
                  method: request.method || (args[0] && args[0].method) || 'GET',
                  requestBody: typeof request.body === 'string' ? request.body : null,
                  responseBody: text,
                  status: response.status
                })).catch(() => {});
              } catch (_) {}
            }
            return response;
          };

          const originalOpen = XMLHttpRequest.prototype.open;
          const originalSend = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function(method, url) {
            this.__vaultCardMethod = method || 'GET';
            this.__vaultCardURL = url || '';
            return originalOpen.apply(this, arguments);
          };
          XMLHttpRequest.prototype.send = function(body) {
            this.__vaultCardBody = body || null;
            this.addEventListener('load', () => {
              if (!isCardResponse(this.__vaultCardURL)) { return; }
              try {
                post({
                  kind: 'networkCapture',
                  url: this.__vaultCardURL || '',
                  method: this.__vaultCardMethod || 'GET',
                  requestBody: typeof this.__vaultCardBody === 'string' ? this.__vaultCardBody : null,
                  responseBody: typeof this.responseText === 'string' ? this.responseText : '',
                  status: this.status
                });
              } catch (_) {}
            });
            return originalSend.apply(this, arguments);
          };

          let inspectionPending = false;
          const observer = new MutationObserver(() => {
            if (inspectionPending) { return; }
            inspectionPending = true;
            requestAnimationFrame(() => {
              inspectionPending = false;
              if (autoScrollEnabled) { window.__vaultCardScrollToForm(); }
              inspectBalance();
            });
          });
          observer.observe(document.documentElement, { childList: true, subtree: true, characterData: true });
          [100, 450, 1200, 2500].forEach(delay => setTimeout(() => {
            if (autoScrollEnabled) { window.__vaultCardScrollToForm(); }
            inspectBalance();
          }, delay));
        })();
        """
    }

    static func autofillScript(credentials: CardCredentials) -> String {
        let number = jsString(credentials.cardNumber)
        let month = jsString(credentials.expiryMonth)
        let year = jsString(credentials.expiryYear)
        let cvv = jsString(credentials.cvv)
        return """
        (() => {
          let state = window.__vaultCardAutofillState;
          if (!state) {
            state = window.__vaultCardAutofillState = {
              attempt: 0,
              submitted: false,
              userEdited: new WeakSet(),
              listenerInstalled: false,
              observer: null,
              timeout: null
            };
          }
          if (state.submitted) { return; }
          if (state.cancel) { state.cancel(); }
          if (state.observer) { state.observer.disconnect(); }
          if (state.timeout) { clearTimeout(state.timeout); }
          const attempt = ++state.attempt;
          if (!state.listenerInstalled) {
            const rememberUserEdit = event => {
              if (event.isTrusted) {
                if (event.target instanceof Element) { state.userEdited.add(event.target); }
                if (state.retry) { state.retry(); }
              }
            };
            document.addEventListener('input', rememberUserEdit, true);
            document.addEventListener('change', rememberUserEdit, true);
            document.addEventListener('submit', event => {
              if (!event.isTrusted || !(event.target instanceof HTMLFormElement)
                  || !event.target.querySelector('#credit-card-number, input[name="cardNumber"], input[autocomplete="cc-number"]')) { return; }
              state.submitted = true;
              if (state.cancel) { state.cancel(); }
              if (state.observer) { state.observer.disconnect(); state.observer = null; }
              if (state.timeout) { clearTimeout(state.timeout); state.timeout = null; }
            }, true);
            state.listenerInstalled = true;
          }

          const selectors = {
            number: ['#credit-card-number','input[name="cardNumber"]','input[id*="cardNumber"]','input[autocomplete="cc-number"]','input[inputmode="numeric"]'],
            month: ['#expiration_month','input[name="expirationMonth"]','input[id*="expirationMonth"]','select[name="expirationMonth"]','input[name="expMonth"]'],
            year: ['#expiration_year','input[name="expirationYear"]','input[id*="expirationYear"]','select[name="expirationYear"]','input[name="expYear"]'],
            cvv: ['#credit-card-code','input[name="cvv"]','input[placeholder="EnterCode"]','input[name="securityCode"]','input[id*="securityCode"]','input[id*="cvv"]','input[autocomplete="cc-csc"]']
          };
          const expected = { number: \(number), month: \(month), year: \(year), cvv: \(cvv) };
          const isVisible = element => {
            if (!element.isConnected) { return false; }
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
          };
          const isSafeField = (field, kind) => {
            const metadata = [field.name, field.id, field.getAttribute('autocomplete'), field.getAttribute('placeholder')]
              .filter(Boolean).join(' ').toLowerCase();
            if (kind === 'number' && field.matches('input[inputmode="numeric"]') &&
                !/(card|pan|cc.?number)/.test(metadata) && (field.maxLength < 12 || field.maxLength > 19)) { return false; }
            if (/\\b(pin|otp|one.?time|security.?code|cvv|cvc|phone|telephone)\\b/.test(metadata)) {
              return kind === 'cvv' && /\\b(security.?code|cvv|cvc)\\b/.test(metadata);
            }
            return true;
          };
          const findField = (form, kind) => {
            for (const selector of selectors[kind]) {
              for (const field of form.querySelectorAll(selector)) {
                if (isVisible(field) && isSafeField(field, kind)) { return field; }
              }
            }
            return null;
          };
          const findCardForm = () => {
            for (const form of document.forms) {
              const fields = {
                number: findField(form, 'number'),
                month: findField(form, 'month'),
                year: findField(form, 'year'),
                cvv: findField(form, 'cvv')
              };
              if (Object.values(fields).every(Boolean)) { return { form, fields }; }
            }
            return null;
          };
          const digits = value => String(value || '').replace(/\\D/g, '');
          if (!['number', 'month', 'year', 'cvv'].every(kind => digits(expected[kind]).length > 0)) { return; }
          const canonical = (value, kind) => {
            const normalized = digits(value);
            if (kind === 'month') { return normalized.replace(/^0+/, '') || '0'; }
            return normalized;
          };
          const matches = (field, value, kind) => {
            const actual = canonical(field.value, kind);
            const wanted = canonical(value, kind);
            if (actual === wanted) { return true; }
            return kind === 'year' && wanted.length === 4 && actual.length === 2 && actual === wanted.slice(-2);
          };
          const writeValue = (field, value) => {
            field.focus();
            const prototype = field instanceof HTMLSelectElement ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
            const setter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;
            if (setter) { setter.call(field, value); } else { field.value = value; }
            field.dispatchEvent(new Event('input', { bubbles: true }));
            field.dispatchEvent(new Event('change', { bubbles: true }));
          };
          const findSubmitControl = form => {
            const controls = Array.from(form.querySelectorAll('button[type="submit"], button:not([type]), input[type="submit"]'))
              .filter(control => {
                if (control.disabled || control.getAttribute('aria-disabled') === 'true' || !isVisible(control)) { return false; }
                const label = (control.getAttribute('aria-label') || control.value || control.textContent || '')
                  .trim().replace(/\\s+/g, ' ').toLowerCase();
                return /^(submit|check balance|view balance)$/.test(label);
              });
            return controls.length === 1 ? controls[0] : null;
          };
          const finish = () => {
            window.removeEventListener('vaultcardIssuerReady', fillAndSubmit);
            if (state.observer) { state.observer.disconnect(); state.observer = null; }
            if (state.timeout) { clearTimeout(state.timeout); state.timeout = null; }
          };
          const issuerIsReady = () => {
            const readiness = window.__vaultCardIssuerReadiness;
            const hasWidget = Array.from(document.scripts).some(script => {
              if (!script.src) { return false; }
              const url = new URL(script.src, document.baseURI);
              return url.hostname === 'content.blackhawknetwork.com' && url.pathname.startsWith('/riskwidget/');
            });
            return !(hasWidget || readiness?.started) || readiness?.ready === true;
          };
          let submitCheckScheduled = false;
          const fillAndSubmit = () => {
            if (state.attempt !== attempt || state.submitted || Date.now() >= state.deadline) { return; }
            const match = findCardForm();
            if (!match) { return; }
            for (const kind of ['number', 'month', 'year', 'cvv']) {
              const field = match.fields[kind];
              if (!state.userEdited.has(field) && !matches(field, expected[kind], kind)) {
                writeValue(field, expected[kind]);
              }
            }
            const populated = ['number', 'month', 'year', 'cvv'].every(kind =>
              matches(match.fields[kind], expected[kind], kind)
            );
            if (!populated) { return; }
            if (window.__vaultCardScrollToForm) { window.__vaultCardScrollToForm(true); }
            if (submitCheckScheduled) { return; }
            submitCheckScheduled = true;
            requestAnimationFrame(() => {
              submitCheckScheduled = false;
              requestAnimationFrame(() => {
                if (state.attempt !== attempt || state.submitted || Date.now() >= state.deadline) { return; }
                const current = findCardForm();
                if (!current || !['number', 'month', 'year', 'cvv'].every(kind =>
                  matches(current.fields[kind], expected[kind], kind)
                )) { return; }
                if (!current.form.checkValidity() || !issuerIsReady()) { return; }
                const submit = findSubmitControl(current.form);
                if (!submit || !submit.isConnected || !current.form.contains(submit)) { return; }
                state.submitted = true;
                finish();
                submit.click();
              });
            });
          };
          state.cancel = finish;
          window.addEventListener('vaultcardIssuerReady', fillAndSubmit);
          state.deadline = Date.now() + 120000;
          state.observer = new MutationObserver(fillAndSubmit);
          state.observer.observe(document.documentElement, {
            attributes: true,
            childList: true,
            subtree: true,
            attributeFilter: ['aria-disabled', 'disabled', 'class', 'style', 'value']
          });
          state.timeout = setTimeout(finish, 120000);
          state.retry = fillAndSubmit;
          [0, 250, 800, 1600].forEach(delay => setTimeout(fillAndSubmit, delay));
        })();
        """
    }

    private static func jsString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return encoded
    }

    static func parseSummary(_ body: Any, sourceURL: URL?) throws -> GiftCardMallSummaryCapture? {
        guard isAllowed(sourceURL),
              let payload = body as? [String: Any],
              payload["namespace"] as? String == handlerName,
              payload["parserVersion"] as? Int == parserVersion,
              let pageHost = payload["pageHost"] as? String,
              allowedHosts.contains(pageHost.lowercased()),
              pageHost.caseInsensitiveCompare(sourceURL?.host ?? "") == .orderedSame
        else { return nil }

        if payload["kind"] as? String == "domBalance",
           payload["source"] as? String == "availableBalanceSummary" {
            guard let balance = (payload["balance"] as? NSNumber)?.doubleValue, balance.isFinite, balance >= 0 else {
                throw VaultError.webBridge("Invalid balance value.")
            }
            return GiftCardMallSummaryCapture(
                balance: balance,
                currencyCode: "USD",
                accessToken: "",
                rmsSessionId: ""
            )
        }

        // The rendered Available Balance is the source of truth, not closingBalance.
        return nil
    }

    static func parseTransactions(_ body: Any, sourceURL: URL?, summary: GiftCardMallSummaryCapture) throws -> BalanceResult? {
        guard isAllowed(sourceURL),
              let payload = body as? [String: Any],
              payload["namespace"] as? String == handlerName,
              payload["parserVersion"] as? Int == parserVersion,
              let pageHost = payload["pageHost"] as? String,
              allowedHosts.contains(pageHost.lowercased()),
              pageHost.caseInsensitiveCompare(sourceURL?.host ?? "") == .orderedSame,
              payload["kind"] as? String == "networkCapture",
              let url = payload["url"] as? String,
              url.contains("/api/card/getCardTransactions"),
              let responseBody = payload["responseBody"] as? String,
              let data = responseBody.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["success"] as? Bool == true,
              let result = json["result"] as? [String: Any]
        else { return nil }
        guard let items = transactionItems(in: result) else {
            throw VaultError.webBridge("GiftCardMall returned an unrecognized transaction response.")
        }
        let transactions = items.compactMap(parseTransaction)
        if !items.isEmpty, transactions.isEmpty {
            throw VaultError.webBridge("GiftCardMall returned transaction rows in an unsupported format.")
        }
        return BalanceResult(balance: summary.balance, transactions: transactions, fetchedAt: Date())
    }

    private static func transactionItems(in value: Any, depth: Int = 0) -> [[String: Any]]? {
        guard depth <= 4, let dictionary = value as? [String: Any] else { return nil }
        let preferredKeys = [
            "transactions", "transactionHistory", "transactionDetails", "cardTransactions",
            "items", "records", "content", "data", "results"
        ]

        for preferredKey in preferredKeys {
            guard let key = dictionary.keys.first(where: { $0.caseInsensitiveCompare(preferredKey) == .orderedSame }) else { continue }
            if let items = dictionary[key] as? [[String: Any]] { return items }
            if let nested = transactionItems(in: dictionary[key] as Any, depth: depth + 1) { return nested }
        }

        for nestedValue in dictionary.values {
            if let items = nestedValue as? [[String: Any]], items.contains(where: looksLikeTransaction) {
                return items
            }
            if let nested = transactionItems(in: nestedValue, depth: depth + 1) { return nested }
        }
        return nil
    }

    private static func looksLikeTransaction(_ item: [String: Any]) -> Bool {
        value(in: item, aliases: ["amount", "transactionAmount", "transactionValue", "value", "debitAmount"]) != nil
            && value(in: item, aliases: ["transactionDate", "transactionDateTime", "date", "postedDate", "postingDate", "timestamp"]) != nil
    }

    private static func parseTransaction(_ item: [String: Any]) -> CardTransaction? {
        guard let amount = transactionAmount(value(in: item, aliases: [
            "amount", "transactionAmount", "transactionValue", "value", "debitAmount", "loadAmount"
        ])), let date = firstTransactionDate(in: item) else { return nil }

        let description = (value(in: item, aliases: [
            "merchantDescription", "transactionDescription", "description", "merchantName", "merchant", "memo", "type"
        ]) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "GiftCardMall transaction"
        return CardTransaction(date: date, description: description, amount: amount)
    }

    private static func firstTransactionDate(in item: [String: Any]) -> Date? {
        let aliases = [
            "transactionDate", "transactionDateTime", "date", "postedDate", "postingDate",
            "timestamp", "createdAt", "transDate", "settlementDate"
        ]
        for alias in aliases {
            if let rawValue = value(in: item, aliases: [alias]), let date = transactionDate(rawValue) {
                return date
            }
        }
        return nil
    }

    private static func value(in item: [String: Any], aliases: [String]) -> Any? {
        for alias in aliases {
            if let key = item.keys.first(where: { $0.caseInsensitiveCompare(alias) == .orderedSame }) {
                return item[key]
            }
        }
        return nil
    }

    private static func transactionAmount(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        guard let text = value as? String else { return nil }
        let negativeParentheses = text.contains("(") && text.contains(")")
        let normalized = text.filter { $0.isNumber || $0 == "." || $0 == "-" }
        guard var amount = Double(normalized) else { return nil }
        if negativeParentheses, amount > 0 { amount *= -1 }
        return amount
    }

    private static func transactionDate(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
        }
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let epochRange = trimmed.range(of: #"/Date\((-?\d{10,13})"#, options: .regularExpression) {
            let epochText = trimmed[epochRange].filter { $0.isNumber || $0 == "-" }
            if let raw = Double(epochText) {
                return Date(timeIntervalSince1970: abs(raw) > 10_000_000_000 ? raw / 1_000 : raw)
            }
        }
        if let raw = Double(trimmed), trimmed.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) {
            return Date(timeIntervalSince1970: abs(raw) > 10_000_000_000 ? raw / 1_000 : raw)
        }
        if let date = DateFormatter.giftCardISO8601.date(from: trimmed) { return date }
        if let date = DateFormatter.giftCardISO8601Fractional.date(from: trimmed) { return date }
        return DateFormatter.giftCardTransactionDates.lazy.compactMap { $0.date(from: trimmed) }.first
    }
}

extension DateFormatter {
    static let giftCardISO8601 = ISO8601DateFormatter()

    static let giftCardISO8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let giftCardTransactionDates: [DateFormatter] = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS",
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "MM/dd/yyyy HH:mm:ss",
        "MM/dd/yyyy hh:mm:ss a",
        "yyyy-MM-dd",
        "MM/dd/yyyy",
        "MM/dd/yy",
        "MMM d, yyyy"
    ].map { format in
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }
}

final class VisionCardScanner: CardScanning {
    private struct RecognizedLine {
        var text: String
        var boundingBox: CGRect
        var confidence: Float
    }

    private struct RecognizedFields {
        var cardNumber: String?
        var expiry: String?
        var labeledCVV: String?
    }

    func extractCandidates(from image: CGImage, mode: ScanRecognitionMode) async throws -> ScanCandidate {
        let lines: [RecognizedLine] = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let lines = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap { observation in
                        observation.topCandidates(1).first.map {
                            RecognizedLine(text: $0.string, boundingBox: observation.boundingBox, confidence: $0.confidence)
                        }
                    }
                    continuation.resume(returning: lines)
                }
                // Live and shutter capture intentionally share the same recognition
                // algorithm. Live frames are throttled by CameraViewController instead.
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["en-US"]
                request.usesLanguageCorrection = false
                request.minimumTextHeight = 0.012
                let handler = VNImageRequestHandler(cgImage: image)
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        try Task.checkCancellation()
        return extractCandidates(from: lines)
    }

    func extractCandidates(from text: String) -> ScanCandidate {
        let fields = recognizedFields(from: text)
        let cvv = fields.labeledCVV ?? inferContextualCVV(
            from: text,
            excludingCard: fields.cardNumber,
            expiry: fields.expiry
        )
        return makeCandidate(text: text, fields: fields, cvv: cvv)
    }

    private func extractCandidates(from lines: [RecognizedLine]) -> ScanCandidate {
        let text = lines.map(\.text).joined(separator: "\n")
        let fields = recognizedFields(from: text)
        let cvv = fields.labeledCVV
            ?? inferSpatialCVV(from: lines, excludingCard: fields.cardNumber, expiry: fields.expiry)
            ?? inferContextualCVV(from: text, excludingCard: fields.cardNumber, expiry: fields.expiry)
        return makeCandidate(text: text, fields: fields, cvv: cvv)
    }

    private func recognizedFields(from text: String) -> RecognizedFields {
        let labeledCard = text
            .firstMatch(#"(?i)(?:card(?:[ \t]*(?:number|no\.?))?|pan)[ \t]*[:#-]?[ \t]*((?:\d[ \t-]?){13,19})"#, group: 1)
            .map(CardRules.digitsOnly)
            .flatMap { CardRules.isValidCardNumber($0) ? $0 : nil }
        let validCards = text.allMatches(#"(?<!\d)(?:\d[ \t-]?){13,19}(?!\d)"#)
            .map(CardRules.digitsOnly)
            .filter(CardRules.isValidCardNumber)
        let card = labeledCard ?? validCards.first

        let labeledExpiry = text.firstMatch(#"(?i)(?:exp|expiry|expires)\s*[:#-]?\s*((0[1-9]|1[0-2])\s*[/\-]\s*([0-9]{2}))"#, group: 1)
        let rawExpiry = labeledExpiry ?? text.firstMatch(#"\b(0[1-9]|1[0-2])\s*[/\-]\s*([0-9]{2})\b"#)
        let expiry = rawExpiry.map(CardRules.formatExpiryInput)
        let rawCVV = text.firstMatch(
            #"(?i)(?:c\s*v\s*v(?:\s*2)?|c\s*v\s*c(?:\s*2)?|c\s*s\s*c|c\s*i\s*d|c\s*v\s*n|sec(?:urity)?\s*(?:code|number|no\.?|id)|card\s*(?:(?:security|verification)\s*)?code|card\s*(?:security|verification)\s*(?:number|no\.?)|verification\s*(?:code|number)|signature\s*code|3\s*digit\s*code)\s*[:#-]?\s*((?:[0-9][\s-]*){3,4})\b"#,
            group: 1
        )
        let labeledCVV = rawCVV
            .map(CardRules.digitsOnly)
            .flatMap { CardRules.validateCVV($0) ? $0 : nil }

        return RecognizedFields(cardNumber: card, expiry: expiry, labeledCVV: labeledCVV)
    }

    private func makeCandidate(text: String, fields: RecognizedFields, cvv: String?) -> ScanCandidate {
        let confidence: Double
        if fields.cardNumber != nil, fields.expiry != nil, cvv != nil {
            confidence = 0.95
        } else if fields.cardNumber != nil, fields.expiry != nil {
            confidence = 0.78
        } else if fields.cardNumber != nil {
            confidence = 0.62
        } else {
            confidence = 0.45
        }
        return ScanCandidate(
            cardNumber: fields.cardNumber,
            expiry: fields.expiry,
            cvv: cvv,
            recognizedText: text,
            network: CardRules.inferNetwork(fields.cardNumber ?? ""),
            confidence: confidence
        )
    }

    private func inferContextualCVV(from text: String, excludingCard card: String?, expiry: String?) -> String? {
        let expiryDigits = expiry.map(CardRules.digitsOnly)
        let candidates = text
            .components(separatedBy: .newlines)
            .enumerated()
            .compactMap { index, rawLine -> (value: String, score: Int)? in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                let digits = CardRules.digitsOnly(line)
                guard (3...4).contains(digits.count), digits != expiryDigits, digits != card else { return nil }

                let isNumericOnly = line.range(of: #"^[\s\d#:\-]*$"#, options: .regularExpression) != nil
                let hasSecurityContext = line.range(
                    of: #"(?i)(security|secure|verification|verify|signature|code|cvv|cvc|csc|cid|cvn|sec\b|3\s*digit)"#,
                    options: .regularExpression
                ) != nil
                guard isNumericOnly || hasSecurityContext else { return nil }

                var score = digits.count == 3 ? 8 : 3
                if isNumericOnly { score += 4 }
                if hasSecurityContext { score += 6 }
                if index > 0 { score += 1 }
                return (digits, score)
            }
        return candidates.max { $0.score < $1.score }?.value
    }

    private func inferSpatialCVV(from lines: [RecognizedLine], excludingCard card: String?, expiry: String?) -> String? {
        let expiryDigits = expiry.map(CardRules.digitsOnly)
        let candidates = lines.compactMap { line -> (value: String, score: Double)? in
            let digits = CardRules.digitsOnly(line.text)
            guard (3...4).contains(digits.count), digits != expiryDigits, digits != card else { return nil }

            let isNumericOnly = line.text.range(of: #"^[\s\d#:\-]*$"#, options: .regularExpression) != nil
            let hasSecurityContext = line.text.range(
                of: #"(?i)(security|secure|verification|verify|signature|code|cvv|cvc|csc|cid|cvn|sec\b|3\s*digit)"#,
                options: .regularExpression
            ) != nil
            let compactLength = line.text.filter { !$0.isWhitespace }.count
            guard isNumericOnly || hasSecurityContext || (line.boundingBox.midX > 0.62 && compactLength <= 12) else {
                return nil
            }

            var score = digits.count == 3 ? 10.0 : 3.0
            if isNumericOnly { score += 5 }
            if hasSecurityContext { score += 7 }
            if line.boundingBox.midX > 0.62 { score += 3 }
            if (0.2...0.85).contains(line.boundingBox.midY) { score += 1 }
            score += Double(line.confidence) * 2
            return (digits, score)
        }
        return candidates.max { $0.score < $1.score }?.value
    }
}

struct StaticCardScanner: CardScanning {
    func extractCandidates(from image: CGImage, mode: ScanRecognitionMode) async throws -> ScanCandidate {
        extractCandidates(from: "4111 1111 1111 1111 exp: 09/29 cvv: 123")
    }

    func extractCandidates(from text: String) -> ScanCandidate {
        VisionCardScanner().extractCandidates(from: text)
    }
}

extension String {
    func firstMatch(_ pattern: String, group: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range), let matchRange = Range(match.range(at: group), in: self) else {
            return nil
        }
        return String(self[matchRange])
    }

    func allMatches(_ pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).compactMap { match in
            Range(match.range, in: self).map { String(self[$0]) }
        }
    }


}

@MainActor
struct AppEnvironment {
    var cardRepository: CardRepository
    var settingsRepository: SettingsRepository
    var biometricService: BiometricAuthenticating
    var notificationService: NotificationScheduling
    var scanner: CardScanning

    static func live(container: ModelContainer) -> AppEnvironment {
        let context = ModelContext(container)
        let notificationService = NotificationService()
        let cardRepository = SwiftDataCardRepository(context: context, credentialStore: KeychainCredentialStore())
        return AppEnvironment(
            cardRepository: cardRepository,
            settingsRepository: UserDefaultsSettingsRepository(),
            biometricService: LocalAuthenticationService(),
            notificationService: notificationService,
            scanner: VisionCardScanner()
        )
    }

    static func uiTesting() throws -> AppEnvironment {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let notificationService = NoopNotificationService()
        let cardRepository = SwiftDataCardRepository(context: context, credentialStore: InMemoryCredentialStore())
        let settingsRepository = InMemorySettingsRepository()
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-seed-cards") {
            var settings = settingsRepository.load()
            settings.onboardingCompleted = true
            settingsRepository.save(settings)
            for input in [
                CardInput(cardNumber: "4111111111111111", expiry: "09/29", cvv: "123", nickname: "Test Aurora"),
                CardInput(cardNumber: "4012888888881881", expiry: "09/29", cvv: "123", nickname: "Test Atlas"),
                CardInput(cardNumber: "5555555555554444", expiry: "09/29", cvv: "123", nickname: "Test Nova")
            ] {
                var seededInput = input
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-seed-long-card-names") {
                    let names = ["1111": "Stellar Artemis", "1881": "Clever Odysseus", "4444": "Daring Leia"]
                    seededInput.nickname = names[String(input.cardNumber.suffix(4))]
                }
                let cardID = try cardRepository.addCard(seededInput)
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-seed-activity") {
                    let index = input.nickname == "Test Aurora" ? 0 : (input.nickname == "Test Atlas" ? 1 : 2)
                    let descriptions = ["Corner Coffee", "Market Groceries", "Book Shop"]
                    let transaction = CardTransaction(
                        date: Calendar.current.date(byAdding: .day, value: -(index + 1), to: Date())!,
                        description: descriptions[index],
                        amount: Double((index + 1) * 10)
                    )
                    try cardRepository.applyBalanceResult(
                        cardID: cardID,
                        result: BalanceResult(balance: 100, transactions:
                            ProcessInfo.processInfo.arguments.contains("--ui-testing-seed-signed-activity")
                                ? [CardTransaction(date: transaction.date, description: descriptions[index], amount: -abs(transaction.amount)),
                                   CardTransaction(date: transaction.date.addingTimeInterval(-3600), description: "Initial load", amount: 200)]
                                : [transaction], fetchedAt: Date())
                    )
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-seed-zero-card"),
               let zeroCard = try cardRepository.getCards().first(where: { $0.last4 == "1111" }) {
                try cardRepository.applyBalanceResult(
                    cardID: zeroCard.id,
                    result: BalanceResult(balance: 0, transactions: zeroCard.transactions, fetchedAt: Date())
                )
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-seed-archived-cards") {
                let archivedCardIDs = Set(try cardRepository.getCards()
                    .filter { ["1111", "1881"].contains($0.last4) }
                    .map(\.id))
                try cardRepository.archiveCards(ids: archivedCardIDs)
            }
        }
        return AppEnvironment(
            cardRepository: cardRepository,
            settingsRepository: settingsRepository,
            biometricService: AlwaysAllowAuthenticationService(),
            notificationService: notificationService,
            scanner: StaticCardScanner()
        )
    }
}

final class InMemorySettingsRepository: SettingsRepository {
    private var settings = AppSettings()

    func load() -> AppSettings { settings }
    func save(_ settings: AppSettings) { self.settings = settings }
}

@MainActor
@Observable
final class AppModel {
    private let environment: AppEnvironment
    var settings: AppSettings {
        didSet {
            if settings.sortOption != oldValue.sortOption { updateCardLists() }
        }
    }
    var cards: [VaultCard] = [] {
        didSet { updateCardLists() }
    }
    private(set) var sortedActiveCards: [VaultCard] = []
    private(set) var sortedArchivedCards: [VaultCard] = []
    var routePath: [Route] = []
    var isLocked = false
    var isAuthenticating = false
    var alertMessage: String?
    var zeroBalancePrompt: ZeroBalancePrompt?
    var useReminders: [String: CardUseReminder] = [:]
    var notificationsAllowed: Bool?
    private var notificationSyncTask: Task<Void, Never>?
    private var foregroundRefreshIDs: [String: UUID] = [:]
    private var completedZeroBalanceRefreshIDs: [String: UUID] = [:]
    private var automaticArchiveRefreshIDs: [String: UUID] = [:]
    private var automaticArchiveDates: [String: Date] = [:]
    private var authoritativeBalanceRefreshIDs: [String: UUID] = [:]
    private var hasStarted = false

    init(environment: AppEnvironment) {
        self.environment = environment
        settings = environment.settingsRepository.load()
    }

    private func updateCardLists() {
        var active: [VaultCard] = []
        var archived: [VaultCard] = []
        for card in cards {
            if card.isArchived {
                archived.append(card)
            } else {
                active.append(card)
            }
        }
        sortedActiveCards = CardRules.sorted(active, by: settings.sortOption)
        sortedArchivedCards = CardRules.sorted(archived, by: settings.sortOption)
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        reloadCards()
        await unlockIfNeeded()
        await synchronizeNotifications()
        if let id = environment.notificationService.consumePendingReminderCardID() { openReminderCard(id: id) }
    }

    func reloadCards() {
        do {
            cards = try environment.cardRepository.getCards()
            queueNotificationSync()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func synchronizeNotifications() async {
        await environment.notificationService.synchronize(cards: cards, preferences: settings.notificationPreferences)
        useReminders = environment.notificationService.useReminders()
        notificationsAllowed = await environment.notificationService.notificationsEnabled()
    }

    private func queueNotificationSync() {
        notificationSyncTask?.cancel()
        notificationSyncTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            await self.synchronizeNotifications()
        }
    }

    func requestNotificationAuthorization() async {
        await environment.notificationService.requestAuthorization()
        await synchronizeNotifications()
    }

    func scheduleUseReminder(cardID: String, at date: Date) async throws {
        guard let card = cards.first(where: { $0.id == cardID }), !card.isArchived,
              let balance = card.balance, balance.isFinite, balance > 0, balance < 10 else {
            throw VaultError.validation("Reminders are available for active cards with a balance below $10.")
        }
        try await environment.notificationService.scheduleUseReminder(for: card, at: date)
        useReminders = environment.notificationService.useReminders()
        notificationsAllowed = await environment.notificationService.notificationsEnabled()
    }

    func cancelUseReminder(cardID: String) async {
        await environment.notificationService.cancelUseReminder(cardID: cardID)
        useReminders = environment.notificationService.useReminders()
    }

    func openReminderCard(id: String) {
        guard cards.contains(where: { $0.id == id }) else { return }
        _ = environment.notificationService.consumePendingReminderCardID()
        routePath = [.detail(id)]
    }

    func completeOnboarding() {
        settings.onboardingCompleted = true
        saveSettings()
    }

    func setSort(_ option: CardSortOption) {
        settings.sortOption = option
        saveSettings()
    }

    func updateSettings(_ update: (inout AppSettings) -> Void) {
        update(&settings)
        saveSettings()
    }

    func markSwipeArchiveConfirmationSeen() {
        guard !settings.hasSeenSwipeArchiveConfirmation else { return }
        settings.hasSeenSwipeArchiveConfirmation = true
        saveSettings()
    }

    func addCard(_ input: CardInput, allowMissingCVV: Bool = false, allowConfirmedNumber: Bool = false) throws -> String {
        guard CardRules.isValidCardNumber(input.cardNumber) || (allowConfirmedNumber && BulkCardReview.canConfirmNumber(input.cardNumber)) else { throw VaultError.validation("Enter a valid Visa or Mastercard number.") }
        guard CardRules.validateExpiry(input.expiry) else { throw VaultError.validation("Use MM/YY.") }
        guard (allowMissingCVV && input.cvv.isEmpty) || CardRules.validateCVV(input.cvv) else { throw VaultError.validation("Enter a valid CVV.") }
        var resolvedInput = input
        let defaultSuggestion = CardRules.suggestedNickname(for: input.cardNumber)
        let trimmedNickname = input.nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNickname?.isEmpty != false || trimmedNickname == defaultSuggestion {
            let existingNames = Set(cards.compactMap(\.nickname))
            resolvedInput.nickname = CardRules.suggestedNickname(for: input.cardNumber, avoiding: existingNames)
        }
        let id = try environment.cardRepository.addCard(resolvedInput)
        reloadCards()
        return id
    }

    // Compare secure full numbers, never suffixes, CVV, or expiry. Archived cards count too.
    func bulkExistingCardNumbers() throws -> Set<String> {
        try Set(environment.cardRepository.getCards().map {
            CardRules.digitsOnly(try environment.cardRepository.getCredentials(cardID: $0.id).cardNumber)
        })
    }

    func saveBulkRows(_ rows: [BulkCardRow]) throws -> BulkCardSaveResult {
        var existing = try bulkExistingCardNumbers()
        var result = BulkCardSaveResult()
        do {
            for row in rows {
                switch BulkCardReview.status(for: row, existingNumbers: existing, precedingNumbers: []) {
                case .existing, .duplicate:
                    result.duplicateRowIDs.insert(row.id)
                case .needsReview:
                    result.pendingRowIDs.insert(row.id)
                case .ready:
                    let id = try addCard(row.input, allowMissingCVV: true, allowConfirmedNumber: row.numberConfirmed)
                    result.savedCardIDs.append(id)
                    result.savedRowIDs.insert(row.id)
                    existing.insert(CardRules.digitsOnly(row.cardNumber))
                }
            }
            return result
        } catch {
            reloadCards()
            throw BulkCardSaveError(savedIDs: result.savedCardIDs, underlying: error,
                savedRowIDs: result.savedRowIDs, duplicateRowIDs: result.duplicateRowIDs)
        }
    }

    /// Remove only unchecked copies of an already checked card. Never merge or
    /// delete cards that have their own balances/history, or match only by suffix.
    @discardableResult
    func removeUncheckedDuplicateCards() throws -> Int {
        let snapshot = try environment.cardRepository.getCards()
        var credentials = try Dictionary(uniqueKeysWithValues: snapshot.map { card in
            (card.id, try environment.cardRepository.getCredentials(cardID: card.id))
        })
        let checkedCards = snapshot.filter {
            $0.lastFetchedAt != nil || $0.balance != nil || !$0.transactions.isEmpty
        }.sorted { $0.addedAt < $1.addedAt }
        var duplicateIDs = Set<String>()
        for copy in snapshot.sorted(by: { $0.addedAt < $1.addedAt }) where copy.lastFetchedAt == nil && copy.balance == nil && copy.transactions.isEmpty {
            guard let copyCredentials = credentials[copy.id] else { continue }
            let number = CardRules.digitsOnly(copyCredentials.cardNumber)
            guard !number.isEmpty else { continue }
            guard let original = checkedCards.first(where: { card in
                guard card.expiry == copy.expiry, let saved = credentials[card.id] else { return false }
                return CardRules.digitsOnly(saved.cardNumber) == number
                    && (saved.cvv.isEmpty || copyCredentials.cvv.isEmpty || saved.cvv == copyCredentials.cvv)
                    && (saved.pin.isEmpty || copyCredentials.pin.isEmpty || saved.pin == copyCredentials.pin)
            }), var saved = credentials[original.id] else { continue }
            let previous = saved
            if saved.cvv.isEmpty { saved.cvv = copyCredentials.cvv }
            if saved.pin.isEmpty { saved.pin = copyCredentials.pin }
            if saved != previous {
                try environment.cardRepository.updateCredentials(cardID: original.id, credentials: saved)
                credentials[original.id] = saved
            }
            duplicateIDs.insert(copy.id)
        }
        if !duplicateIDs.isEmpty {
            try environment.cardRepository.deleteCards(ids: duplicateIDs)
            reloadCards()
        }
        return duplicateIDs.count
    }

    private func cleanUncheckedDuplicatesIfNeeded() {
        guard !isLocked, !settings.hasCleanedUncheckedDuplicates else { return }
        do {
            let count = try removeUncheckedDuplicateCards()
            settings.hasCleanedUncheckedDuplicates = true
            saveSettings()
            if count > 0 {
                alertMessage = "Removed \(count) unchecked duplicate cards. Original cards, balances, and transaction history were kept."
            }
        } catch {
            // Leave the migration pending; inaccessible credentials must never be guessed.
            alertMessage = "Duplicate cleanup couldn’t finish: \(error.localizedDescription)"
        }
    }

    func saveCVV(_ cvv: String, cardID: String) async throws {
        guard CardRules.validateCVV(cvv) else { throw VaultError.validation("Enter a 3 or 4 digit CVV.") }
        var credentials = try await revealCardCredentials(id: cardID)
        credentials.cvv = cvv
        try environment.cardRepository.updateCredentials(cardID: cardID, credentials: credentials)
        reloadCards()
    }

    var isShowingVault: Bool { routePath.isEmpty }

    var isShowingArchived: Bool {
        guard let first = routePath.first else { return false }
        switch first {
        case .archived, .archivedZeroBalance: return true
        default: return false
        }
    }

    var isShowingActivity: Bool {
        guard let first = routePath.first else { return false }
        if case .activity = first { return true }
        return false
    }

    var isShowingAddFlow: Bool {
        guard let first = routePath.first else { return false }
        switch first {
        case .add, .manualEntry, .scan, .bulkCapture: return true
        default: return false
        }
    }

    var isShowingSettings: Bool {
        guard let first = routePath.first else { return false }
        if case .settings = first { return true }
        return false
    }

    func showVault() {
        guard !isShowingVault else { return }
        routePath.removeAll()
    }

    func showPreferredAddFlow() {
        guard !isShowingAddFlow else { return }
        routePath = [settings.addCardPreference == .scan ? .scan : .manualEntry(prefill: nil)]
    }

    func showSettings() {
        guard !isShowingSettings else { return }
        routePath = [.settings]
    }

    func deleteCard(id: String) throws {
        let shouldReturnToArchivedList = isDetailPresentedFromArchivedList(for: id)
        try environment.cardRepository.deleteCard(id: id)
        if shouldReturnToArchivedList {
            routePath.removeLast()
        } else {
            routePath.removeAll()
        }
        reloadCards()
    }

    func deleteCards(ids: Set<String>) throws {
        try environment.cardRepository.deleteCards(ids: ids)
        reloadCards()
    }

    func archiveCard(id: String) throws {
        try environment.cardRepository.archiveCard(id: id)
        reloadCards()
        popDetailIfNeeded(for: id)
    }

    func archiveCards(ids: Set<String>) throws {
        try environment.cardRepository.archiveCards(ids: ids)
        reloadCards()
    }

    func unarchiveCard(id: String) throws {
        try environment.cardRepository.unarchiveCard(id: id)
        reloadCards()
        popDetailIfNeeded(for: id)
    }

    func unarchiveCards(ids: Set<String>) throws {
        try environment.cardRepository.unarchiveCards(ids: ids)
        reloadCards()
    }

    func showArchivedCards() {
        guard routePath.last != .archived else { return }
        routePath = [.archived]
    }

    func showArchivedZeroBalanceCards() {
        guard routePath.last != .archivedZeroBalance else { return }
        routePath = [.archivedZeroBalance]
    }

    func setTransactionInitialLoad(cardID: String, transactionID: String, isInitialLoad: Bool?) {
        guard let card = cards.first(where: { $0.id == cardID }),
              let transaction = card.transactions.first(where: { $0.id == transactionID }),
              transaction.amount.isFinite, transaction.amount > 0 else { return }
        let key = TransactionInitialLoad.key(cardID: cardID, transactionID: transactionID)
        settings.transactionInitialLoadOverrides[key] = isInitialLoad
        saveSettings()
    }

    func showActivity() {
        guard routePath.last != .activity else { return }
        routePath = [.activity]
    }

    func revealCardCredentials(id: String) async throws -> CardCredentials {
        isAuthenticating = true
        defer { isAuthenticating = false }
        guard await environment.biometricService.authenticate(reason: "Reveal sensitive card details") else {
            throw VaultError.validation("Authentication was cancelled.")
        }
        return try environment.cardRepository.getCredentials(cardID: id)
    }

    func credentialsForAutofill(id: String) async throws -> CardCredentials {
        // Opening the embedded balance check is already an explicit user action from
        // inside the unlocked vault. Avoid interrupting that workflow with a second
        // authentication prompt; reveal remains separately authenticated.
        return try environment.cardRepository.getCredentials(cardID: id)
    }

    @discardableResult
    func applyForegroundRefresh(id: String, result: BalanceResult, isAuthoritativeBalance: Bool = true) -> Bool {
        if !isAuthoritativeBalance, let checkID = foregroundRefreshIDs[id],
           authoritativeBalanceRefreshIDs[id] == checkID { return false }
        do {
            try environment.cardRepository.applyBalanceResult(cardID: id, result: result)
            reloadCards()
            if isAuthoritativeBalance, let checkID = foregroundRefreshIDs[id] {
                authoritativeBalanceRefreshIDs[id] = checkID
            }
            handleZeroBalanceRefresh(id: id, balance: result.balance)
            return true
        } catch {
            alertMessage = error.localizedDescription
            return false
        }
    }

    func beginForegroundRefresh(id: String) {
        let checkID = UUID()
        foregroundRefreshIDs[id] = checkID
        completedZeroBalanceRefreshIDs[id] = nil
        automaticArchiveRefreshIDs[id] = nil
        automaticArchiveDates[id] = nil
        authoritativeBalanceRefreshIDs[id] = nil
        if zeroBalancePrompt?.cardID == id { zeroBalancePrompt = nil }
    }

    func resolveZeroBalancePrompt(_ action: ZeroBalancePromptAction) {
        guard let prompt = zeroBalancePrompt else { return }
        zeroBalancePrompt = nil
        switch action {
        case .done, .notNow:
            break
        case .keepThisCard:
            automaticArchiveRefreshIDs[prompt.cardID] = nil
            automaticArchiveDates[prompt.cardID] = nil
            do { try unarchiveCard(id: prompt.cardID) }
            catch { alertMessage = error.localizedDescription }
        case .alwaysKeep:
            settings.archiveZeroBalanceCardsAutomatically = false
            settings.askAboutZeroBalanceCards = false
            saveSettings()
        case .archiveThisCard:
            guard isKnownZeroBalanceActiveCard(prompt.cardID) else { return }
            do { try archiveCard(id: prompt.cardID) }
            catch { alertMessage = error.localizedDescription }
        case .alwaysArchive:
            guard isKnownZeroBalanceActiveCard(prompt.cardID) else { return }
            do {
                try archiveCard(id: prompt.cardID)
                settings.archiveZeroBalanceCardsAutomatically = true
                saveSettings()
            } catch { alertMessage = error.localizedDescription }
        }
    }

    var knownZeroBalanceActiveCardIDs: Set<String> {
        Set(sortedActiveCards.filter { $0.balance?.isFinite == true && $0.balance == 0 }.map(\.id))
    }

    private func isKnownZeroBalanceActiveCard(_ id: String) -> Bool {
        knownZeroBalanceActiveCardIDs.contains(id)
    }

    func archiveKnownZeroBalanceCards() throws {
        let ids = knownZeroBalanceActiveCardIDs
        guard !ids.isEmpty else { return }
        try archiveCards(ids: ids)
    }

    private func handleZeroBalanceRefresh(id: String, balance: Double) {
        guard balance.isFinite, let checkID = foregroundRefreshIDs[id] else { return }
        if balance > 0 {
            if completedZeroBalanceRefreshIDs[id] == checkID {
                if zeroBalancePrompt?.cardID == id { zeroBalancePrompt = nil }
                if automaticArchiveRefreshIDs[id] == checkID {
                    automaticArchiveRefreshIDs[id] = nil
                    let autoArchiveDate = automaticArchiveDates.removeValue(forKey: id)
                    if let card = cards.first(where: { $0.id == id }),
                       card.isArchived, card.archivedAt == autoArchiveDate {
                        do { try unarchiveCard(id: id) }
                        catch { alertMessage = error.localizedDescription }
                    }
                }
            }
            return
        }
        guard balance == 0,
              completedZeroBalanceRefreshIDs[id] != checkID,
              let card = cards.first(where: { $0.id == id }),
              !card.isArchived else { return }

        completedZeroBalanceRefreshIDs[id] = checkID
        if settings.archiveZeroBalanceCardsAutomatically {
            do {
                try archiveCard(id: id)
                automaticArchiveRefreshIDs[id] = checkID
                automaticArchiveDates[id] = cards.first(where: { $0.id == id })?.archivedAt
                zeroBalancePrompt = ZeroBalancePrompt(
                    id: UUID(), cardID: id, cardName: card.displayName, last4: card.last4, kind: .autoArchived
                )
            } catch {
                alertMessage = error.localizedDescription
            }
        } else if settings.askAboutZeroBalanceCards {
            zeroBalancePrompt = ZeroBalancePrompt(
                id: UUID(), cardID: id, cardName: card.displayName, last4: card.last4, kind: .offerArchive
            )
        }
    }

    func scanImage(_ image: CGImage, mode: ScanRecognitionMode) async throws -> ScanCandidate {
        try await environment.scanner.extractCandidates(from: image, mode: mode)
    }

    func lockForBackground() {
        if settings.appLockEnabled {
            isLocked = true
        }
    }

    func unlockIfNeeded() async {
        guard settings.appLockEnabled else {
            isLocked = false
            cleanUncheckedDuplicatesIfNeeded()
            return
        }
        guard !isAuthenticating else { return }
        isLocked = true
        isAuthenticating = true
        let authenticated = await environment.biometricService.authenticate(reason: "Unlock your card vault")
        isAuthenticating = false
        isLocked = !authenticated
        if authenticated { cleanUncheckedDuplicatesIfNeeded() }
    }

    private func saveSettings() {
        environment.settingsRepository.save(settings)
        queueNotificationSync()
    }

    private func popDetailIfNeeded(for cardID: String) {
        guard case .detail(let currentID) = routePath.last, currentID == cardID else { return }
        routePath.removeLast()
    }

    private func isDetailPresentedFromArchivedList(for cardID: String) -> Bool {
        guard routePath.count >= 2,
              let archiveRoute = routePath.dropLast().last,
              case .detail(let currentID) = routePath.last
        else { return false }
        switch archiveRoute {
        case .archived, .archivedZeroBalance: break
        default: return false
        }
        return currentID == cardID
    }
}

enum Route: Hashable {
    case add
    case manualEntry(prefill: ScanCandidate?)
    case scan
    case bulkCapture
    case detail(String)
    case giftCardMall(String)
    case archived
    case archivedZeroBalance
    case activity
    case settings
}

@main
struct VaultCardApp: App {
    var body: some Scene {
        WindowGroup {
            BootstrapView()
        }
    }
}

struct BootstrapView: View {
    @State private var model: AppModel?
    @State private var startupError: String?
    @State private var isTakingLong = false

    var body: some View {
        if let model {
            RootView()
                .environment(model)
        } else if let startupError {
            ContentUnavailableView(
                "VaultCard could not start",
                systemImage: "exclamationmark.triangle",
                description: Text(startupError)
            )
        } else {
            ZStack {
                VaultBackground()
                VStack(spacing: 16) {
                    VaultBrandMark(size: 76)
                    ProgressView(isTakingLong ? "Still opening your encrypted vault…" : "Opening your vault…")
                        .font(.callout.weight(.medium))
                    if isTakingLong {
                        Text("Your saved cards are safe. VaultCard is waiting for the on-device store to become available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                    }
                }
            }
            .task { await bootstrap() }
            .task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, model == nil, startupError == nil else { return }
                isTakingLong = true
            }
        }
    }

    @MainActor
    private func bootstrap() async {
        guard model == nil, startupError == nil else { return }
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        do {
            let environment: AppEnvironment
            if isUITesting {
                environment = try AppEnvironment.uiTesting()
            } else {
                let result = await Task.detached(priority: .userInitiated) {
                    Result { try ModelContainerFactory.makePersistent() }
                }.value
                environment = AppEnvironment.live(container: try result.get())
            }
            model = AppModel(environment: environment)
        } catch {
            startupError = error.localizedDescription
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        ZStack {
            VaultBackground()
            if model.settings.onboardingCompleted {
                NavigationStack(path: $model.routePath) {
                    CardListView()
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .add: AddCardChoiceView()
                            case .manualEntry(let prefill): ManualCardEntryView(prefill: prefill)
                            case .scan: ScanCardView()
                            case .bulkCapture: BulkCardCaptureView()
                            case .detail(let id): CardDetailView(cardID: id)
                            case .giftCardMall(let id): GiftCardMallRefreshView(cardID: id)
                            case .archived: ArchivedCardsView()
                            case .archivedZeroBalance: ArchivedCardsView(initialZeroBalanceOnly: true)
                            case .activity: ActivityView()
                            case .settings: SettingsView()
                            }
                        }
                }
                .vaultFloatingBar {
                    if shouldShowFloatingBar { floatingBar }
                }
            } else {
                OnboardingView()
            }
            if model.isLocked {
                LockOverlayView()
            }
        }
        .tint(VaultTheme.electricBlue)
        .task { await model.start() }
        .alert(
            "VaultCard",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { isPresented in if !isPresented { model.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaultcardOpenReminderCard)) { notification in
            if let id = notification.object as? String { model.openReminderCard(id: id) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                model.lockForBackground()
            } else if phase == .active {
                Task {
                    await model.unlockIfNeeded()
                    await model.synchronizeNotifications()
                }
            }
        }
    }

    private var shouldShowFloatingBar: Bool {
        switch model.routePath.last {
        case .bulkCapture?, .giftCardMall?: return false
        default: return true
        }
    }

    private var floatingBar: some View {
        VaultFloatingBar(
            vaultSelected: model.isShowingVault || model.isShowingArchived || model.isShowingActivity,
            addSelected: model.isShowingAddFlow,
            settingsSelected: model.isShowingSettings,
            showVault: { withAnimation(.snappy) { model.showVault() } },
            addCard: { withAnimation(.snappy) { model.showPreferredAddFlow() } },
            showSettings: { withAnimation(.snappy) { model.showSettings() } }
        )
    }
}

private extension View {
    @ViewBuilder
    func vaultFloatingBar<Bar: View>(@ViewBuilder bar: () -> Bar) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom, spacing: 0, content: bar)
        } else {
            safeAreaInset(edge: .bottom, spacing: 0, content: bar)
        }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var index = 0
    private let pages = [
        ("Your prepaid cards.\nOrganized. Protected.", "VaultCard securely stores your Visa and Mastercard open-loop gift cards — on this device and under your control.", "creditcard.and.123"),
        ("Balances stay\nwithin reach.", "Refresh balances and recent activity without juggling receipts, websites, or physical cards.", "arrow.triangle.2.circlepath"),
        ("Private by design.\nReady when you are.", "Sensitive details stay encrypted and require authentication before they are revealed or autofilled.", "faceid")
    ]

    var body: some View {
        ZStack {
            VaultBackground()
            VStack(spacing: 0) {
                TabView(selection: $index) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { offset, page in
                        VStack(spacing: 24) {
                            Spacer(minLength: 28)
                            ZStack {
                                Circle()
                                    .fill(VaultTheme.electricBlue.opacity(0.12))
                                    .frame(width: 210, height: 210)
                                    .blur(radius: 2)
                                if offset == 0 {
                                    VaultBrandMark(size: 124)
                                    Image(systemName: "creditcard.fill")
                                        .font(.system(size: 50))
                                        .foregroundStyle(.white, VaultTheme.electricBlue)
                                        .rotationEffect(.degrees(-9))
                                        .offset(x: 58, y: 42)
                                        .shadow(color: VaultTheme.electricBlue.opacity(0.5), radius: 12)
                                } else {
                                    VaultBrandMark(size: 116)
                                    Image(systemName: page.2)
                                        .font(.system(size: 42, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            Text(page.0)
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .multilineTextAlignment(.center)
                                .tracking(-0.6)
                            Text(page.1)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                                .frame(maxWidth: 340)
                            Spacer(minLength: 20)
                        }
                        .padding(.horizontal, 28)
                        .tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { page in
                        Capsule()
                            .fill(page == index ? VaultTheme.electricBlue : Color.secondary.opacity(0.2))
                            .frame(width: page == index ? 24 : 7, height: 7)
                            .animation(.snappy, value: index)
                    }
                }
                .padding(.bottom, 18)

                Button(index == pages.count - 1 ? "Get Started" : "Next") {
                    if index == pages.count - 1 {
                        model.completeOnboarding()
                    } else {
                        withAnimation(.snappy) { index += 1 }
                    }
                }
                .accessibilityIdentifier("onboarding.primary")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .controlSize(.large)
                .vaultPrimaryButton()
                .padding(.horizontal, 28)

                Label("Your data stays on your device.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            }
        }
    }
}

private struct VaultBulkActionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(VaultBulkActionButtonChrome(tint: tint, isPressed: configuration.isPressed))
    }
}

private struct VaultBulkActionButtonChrome: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    let tint: Color
    let isPressed: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .foregroundStyle(isEnabled ? tint : Color.secondary.opacity(0.55))
                .opacity(isEnabled && isPressed ? 0.82 : 1)
                .scaleEffect(isEnabled && isPressed ? 0.98 : 1)
                .glassEffect(
                    .regular
                        .tint(tint.opacity(isEnabled ? 0.32 : 0.06))
                        .interactive(isEnabled),
                    in: .rect(cornerRadius: 18)
                )
        } else {
            content
                .foregroundStyle(isEnabled ? tint : Color.secondary.opacity(0.55))
                .opacity(isEnabled && isPressed ? 0.82 : 1)
                .scaleEffect(isEnabled && isPressed ? 0.98 : 1)
                .background(
                    isEnabled ? tint.opacity(isPressed ? 0.2 : 0.12) : Color.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .vaultGlass(cornerRadius: 18, interactive: isEnabled)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isEnabled ? tint.opacity(0.42) : Color.secondary.opacity(0.12), lineWidth: 1)
                }
        }
    }
}

struct CardListView: View {
    private enum CardFilter: String, CaseIterable {
        case all = "All"
        case upToDate = "Up to Date"
        case needsRefresh = "Needs Refresh"
        case zeroBalance = "$0 Balance"
    }

    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var selectedFilter = CardFilter.all
    @State private var isStackExpanded = false
    @State private var pendingDelete: VaultCard?
    @State private var isSelectingRecentCards = false
    @State private var selectedCardIDs = Set<String>()
    @State private var isBulkDeleteConfirmationPresented = false
    @State private var isZeroBalanceArchiveConfirmationPresented = false
    @State private var pendingSwipeArchiveEducation: VaultCard?
    @State private var latestSwipeArchivedCard: VaultCard?
    @State private var swipeArchiveDismissTask: Task<Void, Never>?
    @FocusState private var searchIsFocused: Bool

    private var visibleCards: [VaultCard] {
        let filtered: [VaultCard]
        switch selectedFilter {
        case .all:
            filtered = model.sortedActiveCards
        case .upToDate:
            filtered = model.sortedActiveCards.filter {
                $0.balanceFreshness(refreshAfterDays: model.settings.refreshAfterDays) == .upToDate
            }
        case .needsRefresh:
            filtered = model.sortedActiveCards.filter {
                $0.balanceFreshness(refreshAfterDays: model.settings.refreshAfterDays) == .needsRefresh
            }
        case .zeroBalance:
            filtered = model.sortedActiveCards.filter { $0.balance?.isFinite == true && $0.balance == 0 }
        }
        guard !searchText.isEmpty else { return filtered }
        return filtered.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.last4.contains(searchText)
                || $0.network.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        let visibleCards = visibleCards
        ZStack {
            VaultBackground()
            List {
                VaultFundsSummaryView(cards: model.cards, refreshAfterDays: model.settings.refreshAfterDays)
                    .cardListRowStyle(verticalPadding: 8)
                searchRow
                filterRow
                if selectedFilter == .zeroBalance {
                    zeroBalanceArchiveInfo
                }

                if visibleCards.isEmpty {
                    emptyState
                } else {
                    cardCollection(visibleCards)
                    recentCardRows(visibleCards)
                }

                Label("Card data and sensitive details stay on this device.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .cardListRowStyle(verticalPadding: 14)
                    .accessibilityIdentifier("cards.privacy.footer")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
            .vaultFloatingBarScrollClearance()
            .navigationTitle("Vault")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            model.showArchivedCards()
                        } label: {
                            Label("Archived Cards", systemImage: "archivebox")
                        }
                        Button {
                            isZeroBalanceArchiveConfirmationPresented = true
                        } label: {
                            Label("Archive $0 Cards (\(model.knownZeroBalanceActiveCardIDs.count))", systemImage: "archivebox.fill")
                        }
                        .disabled(model.knownZeroBalanceActiveCardIDs.isEmpty)
                    } label: {
                        Image(systemName: "archivebox")
                    }
                    .accessibilityIdentifier("cards.archived")
                    .accessibilityLabel("Archive options")
                    .accessibilityValue("\(model.sortedArchivedCards.count) cards")
                    .accessibilityHint("Open archived cards or archive cards with a zero balance")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.showActivity()
                    } label: {
                        Label("Activity", systemImage: "clock.arrow.circlepath")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityIdentifier("cards.activity")
                    .accessibilityLabel("Activity")
                    .accessibilityHint("Show transactions across all cards")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(CardSortOption.allCases) { option in
                            Button(option.label) { model.setSort(option) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
        }
        .alert("Remove card?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                guard let card = pendingDelete else { return }
                pendingDelete = nil
                do {
                    try model.deleteCard(id: card.id)
                } catch {
                    model.alertMessage = error.localizedDescription
                }
            }
        } message: {
            Text("This removes the card and its secure credentials from this device.")
        }
        .alert(
            "Delete \(selectedCardIDs.count) card\(selectedCardIDs.count == 1 ? "" : "s")?",
            isPresented: $isBulkDeleteConfirmationPresented
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete \(selectedCardIDs.count)", role: .destructive) {
                deleteSelectedCards()
            }
            .accessibilityIdentifier("cards.bulk.delete.confirm")
        } message: {
            Text("This permanently removes the selected card metadata and secure credentials from this device.")
        }
        .alert(
            "Archive \(model.knownZeroBalanceActiveCardIDs.count) $0 card\(model.knownZeroBalanceActiveCardIDs.count == 1 ? "" : "s")?",
            isPresented: $isZeroBalanceArchiveConfirmationPresented
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Archive \(model.knownZeroBalanceActiveCardIDs.count)") {
                do { try model.archiveKnownZeroBalanceCards() }
                catch { model.alertMessage = error.localizedDescription }
            }
            .disabled(model.knownZeroBalanceActiveCardIDs.isEmpty)
            .accessibilityIdentifier("cards.archiveZero.confirm")
        } message: {
            Text("Only active cards with a known $0 balance will be archived. Cards with no balance yet will stay in your Vault.")
        }
        .alert("Archive this card?", isPresented: Binding(
            get: { pendingSwipeArchiveEducation != nil },
            set: { if !$0 { pendingSwipeArchiveEducation = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                pendingSwipeArchiveEducation = nil
            }
            Button("Archive") {
                guard let card = pendingSwipeArchiveEducation else { return }
                pendingSwipeArchiveEducation = nil
                archiveFromSwipe(card, markEducationSeen: true)
            }
            .accessibilityIdentifier("cards.swipe.archive.confirmation")
        } message: {
            Text("Archived cards leave the Vault but remain safely on this device. Future right swipes will archive immediately, and you can use Undo after each one.")
        }
        .overlay(alignment: .bottom) {
            if let card = latestSwipeArchivedCard {
                swipeArchiveToast(for: card)
                    .padding(.horizontal, 20)
                    .padding(.bottom, VaultFloatingBar.overlayClearance)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .onChange(of: searchText) { _, _ in
            guard isSelectingRecentCards else { return }
            cancelSelection()
        }
        .onChange(of: selectedFilter) { _, _ in
            guard isSelectingRecentCards else { return }
            cancelSelection()
        }
        .onDisappear {
            swipeArchiveDismissTask?.cancel()
            swipeArchiveDismissTask = nil
            latestSwipeArchivedCard = nil
            pendingSwipeArchiveEducation = nil
        }
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search cards", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchIsFocused)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .contentShape(Rectangle())
        .onTapGesture { searchIsFocused = true }
        .vaultGlass(cornerRadius: 16)
        .cardListRowStyle(verticalPadding: 6)
    }

    private var filterRow: some View {
        let cards = model.sortedActiveCards
        let now = Date()
        let upToDateCount = cards.reduce(0) {
            $0 + ($1.balanceFreshness(at: now, refreshAfterDays: model.settings.refreshAfterDays) == .upToDate ? 1 : 0)
        }
        let zeroBalanceCount = model.knownZeroBalanceActiveCardIDs.count
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton(.all, count: cards.count)
                filterButton(.upToDate, count: upToDateCount)
                filterButton(.needsRefresh, count: cards.count - upToDateCount)
                filterButton(.zeroBalance, count: zeroBalanceCount)
            }
        }
        .cardListRowStyle(verticalPadding: 2)
    }

    @ViewBuilder
    private var emptyState: some View {
        let noCards = model.cards.isEmpty
        let allCardsArchived = !noCards && model.sortedActiveCards.isEmpty
        let zeroBalanceActiveCards = model.sortedActiveCards.filter {
            $0.balance?.isFinite == true && $0.balance == 0
        }
        if selectedFilter == .zeroBalance {
            let description: String = {
                if !searchText.isEmpty && !zeroBalanceActiveCards.isEmpty {
                    return "No $0 cards match your search. Try another card name, network, or last four digits."
                } else if model.settings.archiveZeroBalanceCardsAutomatically {
                    return "$0 cards you choose to keep will appear here."
                } else {
                    return "$0 cards will appear here when a balance check reports no remaining funds."
                }
            }()
            VaultSurface {
                VStack(spacing: 16) {
                    VaultBrandMark(size: 82)
                    Text("No $0 cards here")
                        .font(.title2.bold())
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            .cardListRowStyle()
        } else {
            VaultSurface {
                VStack(spacing: 16) {
                    VaultBrandMark(size: 82)
                    Text(noCards ? "No cards yet" : allCardsArchived ? "Your vault is archived" : "No matching cards")
                        .font(.title2.bold())
                    Text(
                        noCards
                            ? "Add your first Visa or Mastercard prepaid card to start tracking balances and expiry dates."
                            : allCardsArchived
                                ? "Your archived cards are safe and can be restored whenever you need them."
                                : "Try another filter, card name, network, or last four digits."
                    )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if noCards {
                        Button("Add Your First Card") { model.showPreferredAddFlow() }
                            .accessibilityIdentifier("cards.empty.add")
                            .vaultPrimaryButton()
                    } else if allCardsArchived {
                        Button {
                            model.showArchivedCards()
                        } label: {
                            Label("View Archived Cards", systemImage: "archivebox")
                        }
                        .accessibilityIdentifier("cards.empty.archived")
                        .vaultPrimaryButton()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            .cardListRowStyle()
        }
    }

    private var zeroBalanceArchiveInfo: some View {
        VaultSurface(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    model.settings.archiveZeroBalanceCardsAutomatically
                        ? "$0 cards move to Archived Cards after a balance check. Cards you choose to keep remain here."
                        : "$0 cards stay in your vault until you archive them."
                )
                .font(.callout)
                .foregroundStyle(.secondary)

                Button {
                    model.showArchivedZeroBalanceCards()
                } label: {
                    Label("View Archived $0 Cards", systemImage: "archivebox")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(VaultTheme.electricBlue)
                .accessibilityIdentifier("cards.zero.archived")
                .accessibilityHint("Show archived cards with a $0 balance")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cards.zero.archiveInfo")
        .cardListRowStyle(verticalPadding: 4)
    }

    @ViewBuilder
    private func cardCollection(_ visibleCards: [VaultCard]) -> some View {
        if visibleCards.count > 1 {
            HStack {
                Text("Cards")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                        isStackExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(isStackExpanded ? "Collapse" : "Expand")
                        Image(systemName: isStackExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .accessibilityIdentifier("cards.stack.toggle")
                .accessibilityLabel(isStackExpanded ? "Collapse cards" : "Expand cards")
            }
            .padding(.top, 12)
            .cardListRowStyle(verticalPadding: 3)
        }

        if visibleCards.count == 1, let card = visibleCards.first {
            Button { model.routePath.append(.detail(card.id)) } label: {
                VaultCardArtwork(card: card, refreshAfterDays: model.settings.refreshAfterDays)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("card.row.\(card.last4)")
            .accessibilityLabel("Open \(card.displayName)")
            .cardListRowStyle()
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                archiveAction(for: card)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                deleteAction(for: card)
            }
        } else if isStackExpanded {
            ForEach(visibleCards) { card in
                Button { model.routePath.append(.detail(card.id)) } label: {
                    VaultCardArtwork(card: card, refreshAfterDays: model.settings.refreshAfterDays)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("card.row.\(card.last4)")
                .cardListRowStyle()
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    archiveAction(for: card)
                }
                // A full trailing swipe reaches the same confirmation surface as the
                // visible action, so it never removes credentials without consent.
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    deleteAction(for: card)
                }
            }
        } else {
            Button {
                withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) {
                    isStackExpanded = true
                }
            } label: {
                VaultCardStackView(cards: visibleCards, refreshAfterDays: model.settings.refreshAfterDays)
            }
            .accessibilityIdentifier("cards.stack.expand")
            .accessibilityLabel("Expand \(visibleCards.count) cards")
            .accessibilityHint("Shows each card separately")
            .buttonStyle(.plain)
            .cardListRowStyle(verticalPadding: 2)
        }
    }

    @ViewBuilder
    private func recentCardRows(_ visibleCards: [VaultCard]) -> some View {
        HStack {
            Text(isSelectingRecentCards ? "\(selectedCardIDs.count) Selected" : model.settings.sortOption.listHeading)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if isSelectingRecentCards {
                Button(action: cancelSelection) {
                    Text("Cancel")
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("cards.bulk.cancel")
                    .accessibilityLabel("Cancel card selection")
            } else {
                Button("Select") { beginSelection() }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("cards.bulk.select")
                    .accessibilityLabel("Select cards")
            }
        }
        .padding(.top, 10)
        .cardListRowStyle(verticalPadding: 4)

        if isSelectingRecentCards {
            bulkActionControls
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }

        ForEach(visibleCards) { card in
            if isSelectingRecentCards {
                cardSelectionRow(for: card)
            } else {
                cardNavigationRow(for: card)
            }
        }
    }

    @ViewBuilder
    private var bulkActionControls: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                bulkActionButtons
            }
        } else {
            bulkActionButtons
        }
    }

    private var bulkActionButtons: some View {
        HStack(spacing: 12) {
            Button {
                archiveSelectedCards()
            } label: {
                Label("Archive", systemImage: "archivebox")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
            }
            .disabled(selectedCardIDs.isEmpty)
            .accessibilityIdentifier("cards.bulk.archive")
            .accessibilityLabel("Archive selected cards")
            .accessibilityValue("\(selectedCardIDs.count) cards selected")
            .buttonStyle(VaultBulkActionButtonStyle(tint: VaultTheme.electricBlue))

            Button(role: .destructive) {
                isBulkDeleteConfirmationPresented = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
            }
            .disabled(selectedCardIDs.isEmpty)
            .accessibilityIdentifier("cards.bulk.delete")
            .accessibilityLabel("Delete selected cards")
            .accessibilityValue("\(selectedCardIDs.count) cards selected")
            .buttonStyle(VaultBulkActionButtonStyle(tint: VaultTheme.danger))
        }
    }

    private func cardNavigationRow(for card: VaultCard) -> some View {
        Button { model.routePath.append(.detail(card.id)) } label: {
            VaultSurface(padding: 8) {
                CardRow(card: card)
            }
        }
        .buttonStyle(.plain)
        .cardListRowStyle(verticalPadding: 4)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            archiveAction(for: card)
        }
        // Keep the full-swipe behavior consistent with the larger card artwork.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            deleteAction(for: card)
            refreshAction(for: card)
        }
    }

    private func cardSelectionRow(for card: VaultCard) -> some View {
        let isSelected = selectedCardIDs.contains(card.id)
        return Button {
            withAnimation(.snappy) { toggleSelection(for: card.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? VaultTheme.electricBlue : .secondary)
                    .accessibilityHidden(true)
                VaultSurface(padding: 8) {
                    CardRow(card: card)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cards.bulk.select.\(card.id)")
        .accessibilityLabel("Select \(card.displayName)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .cardListRowStyle(verticalPadding: 4)
    }

    private func beginSelection() {
        selectedCardIDs.removeAll()
        isSelectingRecentCards = true
    }

    private func cancelSelection() {
        selectedCardIDs.removeAll()
        isSelectingRecentCards = false
    }

    private func toggleSelection(for cardID: String) {
        if selectedCardIDs.contains(cardID) {
            selectedCardIDs.remove(cardID)
        } else {
            selectedCardIDs.insert(cardID)
        }
    }

    private func archiveSelectedCards() {
        guard !selectedCardIDs.isEmpty else { return }
        do {
            try model.archiveCards(ids: selectedCardIDs)
            cancelSelection()
        } catch {
            model.alertMessage = error.localizedDescription
        }
    }

    private func deleteSelectedCards() {
        guard !selectedCardIDs.isEmpty else { return }
        do {
            try model.deleteCards(ids: selectedCardIDs)
            cancelSelection()
        } catch {
            model.alertMessage = error.localizedDescription
        }
    }

    private func filterButton(_ filter: CardFilter, count: Int) -> some View {
        Button {
            withAnimation(.snappy) { selectedFilter = filter }
        } label: {
            VaultStatusPill(title: "\(filter.rawValue) \(count)", active: selectedFilter == filter)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cards.filter.\(filter.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))")
        .accessibilityValue(selectedFilter == filter ? "Selected" : "Not selected")
        .disabled(selectedFilter == filter)
    }

    private func archiveAction(for card: VaultCard) -> some View {
        Button {
            requestSwipeArchive(for: card)
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        .tint(VaultTheme.electricBlue)
        .accessibilityIdentifier("cards.swipe.archive.\(card.id)")
        .accessibilityLabel("Archive \(card.displayName)")
        .accessibilityHint("Moves this card out of the Vault")
    }

    @ViewBuilder
    private func swipeArchiveToast(for card: VaultCard) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox.fill")
                .foregroundStyle(VaultTheme.electricBlue)
                .accessibilityHidden(true)
            Text("Card archived")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 12)
            Button("Undo") {
                undoSwipeArchive(card)
            }
            .font(.subheadline.weight(.bold))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityIdentifier("cards.swipe.archive.undo")
            .accessibilityLabel("Undo archive")
            .accessibilityHint("Restores \(card.displayName) to the Vault")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(maxWidth: 420, minHeight: 56)
        .vaultGlass(cornerRadius: 20, interactive: true)
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cards.swipe.archive.toast")
        .accessibilityLabel("Card archived")
        .accessibilityValue("\(card.displayName) moved to Archived Cards")
    }

    private func requestSwipeArchive(for card: VaultCard) {
        if model.settings.hasSeenSwipeArchiveConfirmation {
            archiveFromSwipe(card, markEducationSeen: false)
        } else {
            pendingSwipeArchiveEducation = card
        }
    }

    private func archiveFromSwipe(_ card: VaultCard, markEducationSeen: Bool) {
        do {
            try model.archiveCard(id: card.id)
            if markEducationSeen {
                model.markSwipeArchiveConfirmationSeen()
            }
            showSwipeArchiveToast(for: card)
        } catch {
            model.alertMessage = error.localizedDescription
        }
    }

    private func showSwipeArchiveToast(for card: VaultCard) {
        swipeArchiveDismissTask?.cancel()
        withAnimation(.snappy) {
            latestSwipeArchivedCard = card
        }
        swipeArchiveDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, latestSwipeArchivedCard?.id == card.id else { return }
            withAnimation(.snappy) {
                latestSwipeArchivedCard = nil
            }
            swipeArchiveDismissTask = nil
        }
    }

    private func undoSwipeArchive(_ card: VaultCard) {
        swipeArchiveDismissTask?.cancel()
        swipeArchiveDismissTask = nil
        do {
            try model.unarchiveCard(id: card.id)
            withAnimation(.snappy) {
                latestSwipeArchivedCard = nil
            }
        } catch {
            withAnimation(.snappy) {
                latestSwipeArchivedCard = nil
            }
            model.alertMessage = error.localizedDescription
        }
    }

    private func deleteAction(for card: VaultCard) -> some View {
        Button(role: .destructive) {
            pendingDelete = card
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .tint(.red)
    }

    private func refreshAction(for card: VaultCard) -> some View {
        Button {
            model.routePath.append(.giftCardMall(card.id))
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .tint(VaultTheme.electricBlue)
        .accessibilityIdentifier("cards.swipe.refresh.\(card.id)")
        .accessibilityLabel("Refresh \(card.displayName)")
        .accessibilityHint("Open the balance check for this card")
    }
}

struct ArchivedCardsView: View {
    @Environment(AppModel.self) private var model
    @State private var zeroBalanceOnly: Bool
    @State private var pendingDelete: VaultCard?
    @State private var isSelectingCards = false
    @State private var selectedCardIDs = Set<String>()
    @State private var isBulkDeleteConfirmationPresented = false

    init(initialZeroBalanceOnly: Bool = false) {
        _zeroBalanceOnly = State(initialValue: initialZeroBalanceOnly)
    }

    private var zeroBalanceArchivedCards: [VaultCard] {
        model.sortedArchivedCards.filter { $0.balance?.isFinite == true && $0.balance == 0 }
    }

    private var displayedCards: [VaultCard] {
        zeroBalanceOnly ? zeroBalanceArchivedCards : model.sortedArchivedCards
    }

    var body: some View {
        ZStack {
            VaultBackground()
            List {
                archiveFilterRow
                Section {
                    if isSelectingCards && !displayedCards.isEmpty {
                        bulkActionControls
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    if displayedCards.isEmpty {
                        emptyState
                    } else {
                        ForEach(displayedCards) { card in
                            if isSelectingCards {
                                cardSelectionRow(for: card)
                            } else {
                                cardNavigationRow(for: card)
                            }
                        }
                    }
                } header: {
                    selectionHeader
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
            .vaultFloatingBarScrollClearance()
        }
        .navigationTitle("Archived Cards")
        .alert("Remove archived card?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                guard let card = pendingDelete else { return }
                pendingDelete = nil
                do {
                    try model.deleteCard(id: card.id)
                } catch {
                    model.alertMessage = error.localizedDescription
                }
            }
            .accessibilityIdentifier("archived.delete.confirm")
        } message: {
            Text("This permanently removes the archived card metadata and secure credentials from this device.")
        }
        .alert(
            "Delete \(selectedCardIDs.count) archived card\(selectedCardIDs.count == 1 ? "" : "s")?",
            isPresented: $isBulkDeleteConfirmationPresented
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete \(selectedCardIDs.count)", role: .destructive) {
                deleteSelectedCards()
            }
            .accessibilityIdentifier("archived.bulk.delete.confirm")
        } message: {
            Text("This permanently removes the selected card metadata and secure credentials from this device.")
        }
        .onChange(of: zeroBalanceOnly) { _, _ in
            cancelSelection()
        }
        .onDisappear {
            cancelSelection()
        }
    }

    private var archiveFilterRow: some View {
        HStack(spacing: 8) {
            archiveFilterButton(title: "All", isZeroBalanceOnly: false)
            archiveFilterButton(title: "$0 Balance", isZeroBalanceOnly: true)
        }
        .cardListRowStyle(verticalPadding: 4)
    }

    private func archiveFilterButton(title: String, isZeroBalanceOnly: Bool) -> some View {
        Button {
            withAnimation(.snappy) {
                zeroBalanceOnly = isZeroBalanceOnly
            }
        } label: {
            VaultStatusPill(title: title, active: zeroBalanceOnly == isZeroBalanceOnly)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(isZeroBalanceOnly ? "archived.filter.zero" : "archived.filter.all")
        .accessibilityLabel(title)
        .accessibilityValue(zeroBalanceOnly == isZeroBalanceOnly ? "Selected" : "Not selected")
    }

    private var selectionHeader: some View {
        HStack {
            Text(
                isSelectingCards
                    ? "\(selectedCardIDs.count) Selected"
                    : "\(displayedCards.count) \(zeroBalanceOnly ? "archived $0 balance card" : "archived card")\(displayedCards.count == 1 ? "" : "s")"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            Spacer()
            if isSelectingCards {
                Button(action: cancelSelection) {
                    Text("Cancel")
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .accessibilityIdentifier("archived.bulk.cancel")
                .accessibilityLabel("Cancel archived card selection")
            } else {
                Button("Select") {
                    beginSelection()
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("archived.bulk.select")
                .accessibilityLabel("Select archived cards")
                .disabled(displayedCards.isEmpty)
            }
        }
        .textCase(nil)
    }

    @ViewBuilder
    private var bulkActionControls: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                bulkActionButtons
            }
        } else {
            bulkActionButtons
        }
    }

    private var bulkActionButtons: some View {
        HStack(spacing: 12) {
            Button {
                restoreSelectedCards()
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
            }
            .disabled(selectedCardIDs.isEmpty)
            .accessibilityIdentifier("archived.bulk.restore")
            .accessibilityLabel("Restore selected cards")
            .accessibilityValue("\(selectedCardIDs.count) cards selected")
            .buttonStyle(VaultBulkActionButtonStyle(tint: VaultTheme.electricBlue))

            Button(role: .destructive) {
                isBulkDeleteConfirmationPresented = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
            }
            .disabled(selectedCardIDs.isEmpty)
            .accessibilityIdentifier("archived.bulk.delete")
            .accessibilityLabel("Delete selected archived cards")
            .accessibilityValue("\(selectedCardIDs.count) cards selected")
            .buttonStyle(VaultBulkActionButtonStyle(tint: VaultTheme.danger))
        }
    }

    private func cardNavigationRow(for card: VaultCard) -> some View {
        Button { model.routePath.append(.detail(card.id)) } label: {
            VaultSurface(padding: 8) {
                CardRow(card: card)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("archived.card.row.\(card.id)")
        .accessibilityLabel("Open archived \(card.displayName)")
        .cardListRowStyle(verticalPadding: 4)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                restore(cardID: card.id)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(VaultTheme.electricBlue)
            .accessibilityIdentifier("archived.restore.\(card.id)")
            .accessibilityLabel("Restore \(card.displayName)")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            deleteAction(for: card)
        }
    }

    private func cardSelectionRow(for card: VaultCard) -> some View {
        let isSelected = selectedCardIDs.contains(card.id)
        return Button {
            withAnimation(.snappy) {
                toggleSelection(for: card.id)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? VaultTheme.electricBlue : .secondary)
                    .accessibilityHidden(true)
                VaultSurface(padding: 8) {
                    CardRow(card: card)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("archived.bulk.select.\(card.id)")
        .accessibilityLabel("Select \(card.displayName)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .cardListRowStyle(verticalPadding: 4)
    }

    private var emptyState: some View {
        VaultSurface {
            VStack(spacing: 14) {
                Image(systemName: "archivebox")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(VaultTheme.electricBlue)
                Text(zeroBalanceOnly ? "No archived $0 cards" : "No Archived Cards")
                    .font(.title2.bold())
                Text(
                    zeroBalanceOnly
                        ? "Archived cards with a $0 balance will appear here."
                        : "Cards you archive will live here until you restore or delete them."
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
        .cardListRowStyle(verticalPadding: 12)
    }

    private func restore(cardID: String) {
        do {
            try model.unarchiveCard(id: cardID)
        } catch {
            model.alertMessage = error.localizedDescription
        }
    }

    private func beginSelection() {
        selectedCardIDs.removeAll()
        isSelectingCards = true
    }

    private func cancelSelection() {
        selectedCardIDs.removeAll()
        isSelectingCards = false
    }

    private func toggleSelection(for cardID: String) {
        if selectedCardIDs.contains(cardID) {
            selectedCardIDs.remove(cardID)
        } else {
            selectedCardIDs.insert(cardID)
        }
    }

    private func restoreSelectedCards() {
        guard !selectedCardIDs.isEmpty else { return }
        do {
            try model.unarchiveCards(ids: selectedCardIDs)
            cancelSelection()
        } catch {
            model.alertMessage = error.localizedDescription
        }
    }

    private func deleteSelectedCards() {
        guard !selectedCardIDs.isEmpty else { return }
        do {
            try model.deleteCards(ids: selectedCardIDs)
            cancelSelection()
        } catch {
            model.alertMessage = error.localizedDescription
        }
    }

    private func deleteAction(for card: VaultCard) -> some View {
        Button(role: .destructive) {
            pendingDelete = card
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .tint(.red)
        .accessibilityIdentifier("archived.delete.\(card.id)")
    }
}

struct VaultCardStackView: View {
    let cards: [VaultCard]
    var refreshAfterDays = 7

    var body: some View {
        let stackedCards = Array(cards.prefix(4))
        let lastIndex = CGFloat(max(0, stackedCards.count - 1))
        let lastCardHeight = 176 * (1 - lastIndex * 0.032)
        let stackHeight = lastIndex * 28 + lastCardHeight + 12
        ZStack(alignment: .top) {
            ForEach(Array(stackedCards.enumerated()).reversed(), id: \.element.id) { index, card in
                VaultCardArtwork(card: card, refreshAfterDays: refreshAfterDays, emphasizesEdge: index > 0)
                    .scaleEffect(1 - CGFloat(index) * 0.032, anchor: .top)
                    .offset(y: CGFloat(index) * 28)
                    .zIndex(Double(stackedCards.count - index))
                    .accessibilityHidden(index != 0)
            }
        }
        .frame(height: stackHeight, alignment: .top)
    }
}

private extension View {
    func cardListRowStyle(verticalPadding: CGFloat = 6) -> some View {
        listRowInsets(EdgeInsets(top: verticalPadding, leading: 20, bottom: verticalPadding, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

struct CardRow: View {
    var card: VaultCard

    var body: some View {
        let isKnownZeroBalance = !card.isArchived && card.balance?.isFinite == true && card.balance == 0
        let isLowBalance = !card.isArchived && card.balance?.isFinite == true && (card.balance ?? 0) > 0 && (card.balance ?? 10) < 10
        HStack(spacing: 12) {
            VaultNetworkRowIcon(network: card.network)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(card.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    HStack(spacing: 6) {
                        Text(card.balance.map { $0.formatted(.currency(code: "USD")) } ?? "—")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isKnownZeroBalance ? .secondary : .primary)
                            .fixedSize()
                        if isKnownZeroBalance || isLowBalance {
                            Text(isKnownZeroBalance ? "No funds" : "Low balance")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                                .accessibilityLabel(isKnownZeroBalance ? "No funds" : "Low balance")
                        }
                    }
                    .fixedSize()
                }

                HStack(spacing: 8) {
                    Text("•••• \(card.last4)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(card.lastFetchedAt.map {
                        CardRowTimestamp.string(date: $0)
                    } ?? "Never")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel(card.lastFetchedAt.map {
                            "Last refreshed \($0.formatted(date: .complete, time: .shortened))"
                        } ?? "Never refreshed")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct AddCardChoiceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            VaultBackground()
            ScrollView {
                VStack(spacing: 20) {
                    VaultBrandMark(size: 78)
                    VStack(spacing: 8) {
                        Text("Add Card")
                            .font(.system(.title, design: .rounded, weight: .bold))
                        Text("Add a Visa or Mastercard prepaid or debit gift card.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VaultSurface(padding: 8) {
                        VStack(spacing: 0) {
                            Button { model.routePath.append(.scan) } label: {
                                HStack(spacing: 14) {
                                    VaultRowIcon(symbol: "viewfinder", color: VaultTheme.electricBlue)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Scan Card").font(.headline)
                                        Text("Use the camera to scan card details")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .padding(10)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("add.scan")
                            Divider().padding(.leading, 58)
                            Button { model.routePath.append(.manualEntry(prefill: nil)) } label: {
                                HStack(spacing: 14) {
                                    VaultRowIcon(symbol: "keyboard", color: VaultTheme.electricBlue)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Enter Manually").font(.headline)
                                        Text("Type card details and save")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .padding(10)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("add.manual")
                        }
                    }

                    BulkCardEntryButton()

                    Label("Your card data stays on your device.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 32)
            }
            .vaultFloatingBarScrollClearance()
        }
        .navigationTitle("Add Card")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ManualCardEntryView: View {
    @Environment(AppModel.self) private var model
    private let scanCapture: ScanCandidate?
    @State private var cardNumber: String
    @State private var expiry: String
    @State private var cvv: String
    @State private var nickname: String
    @State private var errorMessage: String?

    init(prefill: ScanCandidate?) {
        scanCapture = prefill
        _cardNumber = State(initialValue: prefill?.cardNumber ?? "")
        _expiry = State(initialValue: CardRules.formatExpiryInput(prefill?.expiry ?? ""))
        _cvv = State(initialValue: prefill?.cvv ?? "")
        _nickname = State(initialValue: prefill?.cardNumber.map(CardRules.suggestedNickname) ?? "")
    }

    private var previewCard: VaultCard {
        let digits = CardRules.digitsOnly(cardNumber)
        return VaultCard(
            id: "preview",
            nickname: nickname.isEmpty ? "Your Card" : nickname,
            network: CardRules.inferNetwork(cardNumber),
            last4: digits.count >= 4 ? String(digits.suffix(4)) : "••••",
            expiry: expiry.isEmpty ? "MM/YY" : expiry,
            balance: nil,
            transactions: [],
            lastFetchedAt: nil,
            fetchFailureCount: 0,
            addedAt: Date(),
            refreshBlockedUntil: nil,
            credentialVersion: 1
        )
    }

    var body: some View {
        ZStack {
            VaultBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(scanCapture == nil ? "Enter your card details." : "Confirm the captured details against your physical card.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    VaultCardArtwork(card: previewCard)

                    if scanCapture != nil {
                        Label("Captured from scan. Review or edit every value before saving.", systemImage: "checkmark.seal.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(VaultTheme.success)
                            .accessibilityIdentifier("scan.confirmation.summary")
                    }
                    BulkCardEntryButton()
                    manualFields

                    if let errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(errorMessage)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(VaultTheme.danger)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(VaultTheme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityIdentifier("manual.validationError")
                    }

                    Button(scanCapture == nil ? "Save Card" : "Confirm & Save") {
                        do {
                            let id = try model.addCard(CardInput(cardNumber: cardNumber, expiry: expiry, cvv: cvv, nickname: nickname))
                            model.routePath = [.detail(id)]
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .accessibilityIdentifier("manual.save")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .controlSize(.large)
                    .vaultPrimaryButton()

                    if scanCapture != nil {
                        Button {
                            if !model.routePath.isEmpty { model.routePath.removeLast() }
                        } label: {
                            Label("Re-scan Card", systemImage: "viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("scan.confirmation.rescan")
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    Label("Your card stays on this device and remains under your control.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .vaultFloatingBarScrollClearance()
        }
        .navigationTitle("Review & Save")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }

    private var manualFields: some View {
        VaultSurface(padding: 4) {
            VStack(spacing: 0) {
                fieldLabel("Card number")
                TextField("4000 1234 5678 9010", text: Binding(
                    get: { CardRules.formatCardNumber(cardNumber) },
                    set: { cardNumber = String(CardRules.digitsOnly($0).prefix(16)) }
                ))
                    .keyboardType(.numberPad)
                    .textContentType(.creditCardNumber)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .accessibilityIdentifier("manual.cardNumber")
                Divider().padding(.leading, 14)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Expiration")
                        TextField("MM/YY", text: Binding(get: { expiry }, set: { expiry = CardRules.formatExpiryInput($0) }))
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityIdentifier("manual.expiry")
                    }
                    Divider().frame(height: 54)
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("CVV")
                        cvvInput
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                Divider().padding(.leading, 14)
                fieldLabel("Card nickname")
                TextField("Blue Prisma", text: $nickname)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .accessibilityIdentifier("manual.nickname")
            }
        }
    }

    @ViewBuilder
    private var cvvInput: some View {
        if scanCapture == nil {
            SecureField("123", text: $cvv)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("manual.cvv")
        } else {
            TextField("123", text: Binding(
                get: { cvv },
                set: { cvv = String(CardRules.digitsOnly($0).prefix(4)) }
            ))
            .keyboardType(.numberPad)
            .accessibilityIdentifier("manual.cvv")
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 12)
    }

}

struct ScanCardView: View {
    private enum FocusField: Hashable {
        case cardNumber
        case expiry
        case cvv
    }

    @Environment(AppModel.self) private var model
    @State private var cardNumber = ""
    @State private var expiry = ""
    @State private var cvv = ""
    @State private var hasCandidate = false
    @State private var isProcessingFrame = false
    @State private var didAdvance = false
    @State private var editorRevision = 0
    @State private var recognitionTask: Task<Void, Never>?
    @State private var isScannerVisible = false
    @FocusState private var focusedField: FocusField?

    var body: some View {
        ZStack {
            VaultBackground()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 18) {
                        VStack(spacing: 5) {
                            Text("Position your card inside the frame.")
                                .font(.headline)
                            Text("VaultCard scans automatically. Use the camera button only if you want to capture a still image.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        if !didAdvance {
                            CameraCaptureView(
                                liveDetectionEnabled: isScannerVisible && !isProcessingFrame,
                                onImage: { image in processImage(image, manualCapture: true) },
                                onLiveFrame: { image in processImage(image, manualCapture: false) }
                            )
                            .frame(height: 330)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .stroke(VaultTheme.electricBlue.opacity(0.75), lineWidth: 2)
                            }
                            .shadow(color: VaultTheme.electricBlue.opacity(0.2), radius: 20)
                            .overlay(alignment: .top) {
                                if isProcessingFrame {
                                    Label("Reading card…", systemImage: "text.viewfinder")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .padding(12)
                                }
                            }
                        }

                        Button {
                            model.routePath.append(.manualEntry(prefill: nil))
                        } label: {
                            Label("Enter card manually", systemImage: "keyboard")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("scan.enterManually")

                        BulkCardEntryButton()

                        if hasCandidate {
                            detectedDetailsEditor
                                .id("scan.detectedDetails")
                        }
                    }
                    .padding(20)
                }
                .vaultFloatingBarScrollClearance()
                .onChange(of: editorRevision) { _, _ in
                    withAnimation(.snappy) {
                        proxy.scrollTo("scan.detectedDetails", anchor: .center)
                    }
                }
            }
        }
        .navigationTitle("Scan Card")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            isScannerVisible = true
            if didAdvance { resetForRescan() }
        }
        .onDisappear {
            isScannerVisible = false
            recognitionTask?.cancel()
            recognitionTask = nil
            isProcessingFrame = false
        }
    }

    private var detectedDetailsEditor: some View {
        let complete = candidateIsComplete(currentCandidate)
        return VaultSurface(padding: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Label(
                    complete ? "Ready to confirm" : "Review and complete the details",
                    systemImage: complete ? "checkmark.seal.fill" : "pencil.and.list.clipboard"
                )
                .font(.headline)
                .foregroundStyle(complete ? VaultTheme.success : VaultTheme.warning)
                .padding(14)

                Divider().padding(.leading, 14)
                fieldLabel("Full card number")
                TextField("4000 1234 5678 9010", text: Binding(
                    get: { CardRules.formatCardNumber(cardNumber) },
                    set: { cardNumber = String(CardRules.digitsOnly($0).prefix(16)) }
                ))
                .keyboardType(.numberPad)
                .textContentType(.creditCardNumber)
                .font(.body.monospaced())
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .focused($focusedField, equals: .cardNumber)
                .accessibilityIdentifier("scan.cardNumber")

                Divider().padding(.leading, 14)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Expiration")
                        TextField("MM/YY", text: Binding(
                            get: { expiry },
                            set: { expiry = CardRules.formatExpiryInput($0) }
                        ))
                        .keyboardType(.numbersAndPunctuation)
                        .focused($focusedField, equals: .expiry)
                        .accessibilityIdentifier("scan.expiry")
                    }
                    Divider().frame(height: 54)
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("CVV")
                        TextField("123", text: Binding(
                            get: { cvv },
                            set: { cvv = String(CardRules.digitsOnly($0).prefix(4)) }
                        ))
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .cvv)
                        .accessibilityIdentifier("scan.cvv")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

                if !complete {
                    Text("Correct any missing or incorrect value above, then confirm. All values remain visible until you save.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                }

                Divider().padding(.leading, 14)
                HStack(spacing: 10) {
                    Button {
                        advance(to: currentCandidate)
                    } label: {
                        Label("Confirm", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("scan.confirm")
                    .vaultPrimaryButton()
                    .disabled(!complete)

                    Button {
                        resetForRescan()
                    } label: {
                        Label("Re-scan", systemImage: "viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("scan.rescan")
                    .buttonStyle(.bordered)
                }
                .padding(14)
            }
        }
    }

    private var currentCandidate: ScanCandidate {
        let normalizedCard = CardRules.digitsOnly(cardNumber)
        let normalizedExpiry = CardRules.formatExpiryInput(expiry)
        let normalizedCVV = CardRules.digitsOnly(cvv)
        return ScanCandidate(
            cardNumber: normalizedCard.isEmpty ? nil : normalizedCard,
            expiry: normalizedExpiry.isEmpty ? nil : normalizedExpiry,
            cvv: normalizedCVV.isEmpty ? nil : normalizedCVV,
            recognizedText: "",
            network: CardRules.inferNetwork(normalizedCard),
            confidence: candidateIsCompleteValues(card: normalizedCard, expiry: normalizedExpiry, cvv: normalizedCVV) ? 0.95 : 0.65
        )
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 12)
    }

    private func processImage(_ image: CGImage, manualCapture: Bool) {
        guard isScannerVisible, !isProcessingFrame, !didAdvance else { return }
        isProcessingFrame = true
        recognitionTask?.cancel()
        recognitionTask = Task {
            defer {
                isProcessingFrame = false
                recognitionTask = nil
            }
            do {
                let candidate = try await model.scanImage(image, mode: manualCapture ? .still : .live)
                guard !Task.isCancelled else { return }
                if candidate.hasCandidateData {
                    if manualCapture || candidateIsComplete(candidate) {
                        apply(candidate, autoAdvance: true, forceEditor: manualCapture)
                    }
                } else if manualCapture {
                    hasCandidate = true
                    editorRevision += 1
                }
            } catch is CancellationError {
                return
            } catch {
                if manualCapture {
                    hasCandidate = true
                    model.alertMessage = "Scan could not read every field. Edit the card details below or capture another photo."
                    editorRevision += 1
                }
            }
        }
    }

    private func apply(_ candidate: ScanCandidate, autoAdvance: Bool, forceEditor: Bool) {
        let mergedCard = candidate.cardNumber ?? (cardNumber.isEmpty ? nil : CardRules.digitsOnly(cardNumber))
        let mergedExpiry = candidate.expiry ?? (expiry.isEmpty ? nil : CardRules.formatExpiryInput(expiry))
        let mergedCVV = candidate.cvv ?? (cvv.isEmpty ? nil : CardRules.digitsOnly(cvv))
        let merged = ScanCandidate(
            cardNumber: mergedCard,
            expiry: mergedExpiry,
            cvv: mergedCVV,
            recognizedText: candidate.recognizedText,
            network: CardRules.inferNetwork(mergedCard ?? ""),
            confidence: candidate.confidence
        )

        cardNumber = merged.cardNumber ?? ""
        expiry = merged.expiry ?? ""
        cvv = merged.cvv ?? ""
        hasCandidate = forceEditor || merged.hasCandidateData

        if autoAdvance, candidateIsComplete(merged) {
            advance(to: merged)
        } else if hasCandidate {
            editorRevision += 1
        }
    }

    private func advance(to candidate: ScanCandidate) {
        guard !didAdvance, candidateIsComplete(candidate) else { return }
        didAdvance = true
        focusedField = nil
        model.routePath.append(.manualEntry(prefill: candidate))
    }

    private func resetForRescan() {
        recognitionTask?.cancel()
        recognitionTask = nil
        cardNumber = ""
        expiry = ""
        cvv = ""
        hasCandidate = false
        isProcessingFrame = false
        didAdvance = false
        focusedField = nil
    }

    private func candidateIsComplete(_ candidate: ScanCandidate) -> Bool {
        guard let cardNumber = candidate.cardNumber,
              let expiry = candidate.expiry,
              let cvv = candidate.cvv
        else { return false }
        return candidateIsCompleteValues(card: cardNumber, expiry: expiry, cvv: cvv)
    }

    private func candidateIsCompleteValues(card: String, expiry: String, cvv: String) -> Bool {
        CardRules.isValidCardNumber(card)
            && CardRules.validateExpiry(expiry)
            && CardRules.validateCVV(cvv)
    }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    var liveDetectionEnabled: Bool
    var onImage: (CGImage) -> Void
    var onLiveFrame: (CGImage) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.onImage = onImage
        controller.onLiveFrame = onLiveFrame
        controller.setLiveDetectionEnabled(liveDetectionEnabled)
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.onImage = onImage
        uiViewController.onLiveFrame = onLiveFrame
        uiViewController.setLiveDetectionEnabled(liveDetectionEnabled)
    }

    static func dismantleUIViewController(_ uiViewController: CameraViewController, coordinator: Void) {
        uiViewController.tearDown()
    }
}

final class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onImage: ((CGImage) -> Void)?
    var onLiveFrame: ((CGImage) -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.vaultcard.camera.session", qos: .userInitiated)
    private let videoOutputQueue = DispatchQueue(label: "com.vaultcard.camera.frames", qos: .userInitiated)
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var isConfigured = false
    private var isPhotoCaptureInFlight = false
    private var liveDetectionEnabled = false
    private var lastFrameDeliveryTime: CFTimeInterval = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        prepareCamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startCaptureSession()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopCaptureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    func setLiveDetectionEnabled(_ enabled: Bool) {
        videoOutputQueue.async { [weak self] in
            self?.liveDetectionEnabled = enabled
        }
    }

    func tearDown() {
        onImage = nil
        onLiveFrame = nil
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        stopCaptureSession()
    }

    private func prepareCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.showFallbackMessage()
                    }
                }
            }
        default:
            showFallbackMessage()
        }
    }

    private func configureSession() {
        guard !isConfigured,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(photoOutput),
              session.canAddOutput(videoOutput)
        else {
            showFallbackMessage()
            return
        }

        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        session.addOutput(videoOutput)
        if let connection = videoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        session.commitConfiguration()
        isConfigured = true

        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)

        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "camera.fill"), for: .normal)
        button.tintColor = .label
        button.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.92)
        button.layer.cornerRadius = 34
        button.layer.borderWidth = 4
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        button.imageView?.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        button.accessibilityLabel = "Capture card"
        button.accessibilityIdentifier = "scan.capture"
        button.addTarget(self, action: #selector(capture), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),
            button.widthAnchor.constraint(equalToConstant: 68),
            button.heightAnchor.constraint(equalTo: button.widthAnchor)
        ])
        startCaptureSession()
    }

    private func startCaptureSession() {
        guard isConfigured else { return }
        sessionQueue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    private func stopCaptureSession() {
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    @objc private func capture() {
        guard !isPhotoCaptureInFlight, session.isRunning else { return }
        isPhotoCaptureInFlight = true
        setLiveDetectionEnabled(false)
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { isPhotoCaptureInFlight = false }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data)?.normalizedCGImage
        else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onImage?(image)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard liveDetectionEnabled else { return }
        let now = CACurrentMediaTime()
        guard now - lastFrameDeliveryTime >= 1.2,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        liveDetectionEnabled = false
        lastFrameDeliveryTime = now
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(image, from: image.extent) else {
            liveDetectionEnabled = true
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onLiveFrame?(cgImage)
        }
    }

    private func showFallbackMessage() {
        let label = UILabel()
        label.text = "Camera unavailable. Enter the card manually instead."
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}

private extension UIImage {
    var normalizedCGImage: CGImage? {
        if imageOrientation == .up { return cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return normalized.cgImage
    }
}

struct CardDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    let cardID: String
    @State private var revealedCredentials: CardCredentials?
    @State private var hideTask: Task<Void, Never>?
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var isCardNumberCopied = false
    @State private var confirmDelete = false
    @State private var showCVVEditor = false
    @State private var needsCVV = false
    @State private var showUseReminder = false

    var card: VaultCard? { model.cards.first { $0.id == cardID } }

    var body: some View {
        ZStack {
            VaultBackground()
            ScrollView {
                if let card {
                    detailContent(card)
                    .padding(20)
                } else {
                    ContentUnavailableView("Card unavailable", systemImage: "creditcard.trianglebadge.exclamationmark", description: Text("This card may have been deleted."))
                }
            }
            .vaultFloatingBarScrollClearance()
        }
        .navigationTitle(card?.displayName ?? "Card")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let card {
                    Button {
                        toggleArchive(for: card)
                    } label: {
                        Image(systemName: card.isArchived ? "arrow.uturn.backward" : "archivebox")
                    }
                    .accessibilityIdentifier(card.isArchived ? "detail.restore" : "detail.archive")
                    .accessibilityLabel(card.isArchived ? "Restore card" : "Archive card")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: { Image(systemName: "trash") }
                .accessibilityIdentifier("detail.delete")
            }
        }
        .alert("Remove card?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                do { try model.deleteCard(id: cardID) } catch { model.alertMessage = error.localizedDescription }
            }
            .accessibilityIdentifier("detail.confirmDelete")
        } message: {
            Text("This removes the saved metadata and secure credentials from this device.")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                clearReveal()
            }
        }
        .task { needsCVV = (try? await model.credentialsForAutofill(id: cardID).cvv.isEmpty) ?? false }
        .sheet(isPresented: $showCVVEditor) {
            AddMissingCVVView(cardID: cardID) { needsCVV = false }
        }
        .sheet(isPresented: $showUseReminder) {
            if let card {
                CardUseReminderView(card: card, reminder: model.useReminders[cardID]) { date in
                    try await model.scheduleUseReminder(cardID: cardID, at: date)
                }
            }
        }
        .onDisappear { clearReveal() }
    }

    private func detailContent(_ card: VaultCard) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VaultCardArtwork(
                card: card,
                refreshAfterDays: model.settings.refreshAfterDays,
                revealedCredentials: revealedCredentials,
                onCopyCardNumber: revealedCredentials == nil ? nil : { copyCardNumber() },
                isCardNumberCopied: isCardNumberCopied,
                usesDetailedMask: true
            )
            if needsCVV {
                Button { showCVVEditor = true } label: {
                    Label("Add CVV to manage this card", systemImage: "creditcard.trianglebadge.exclamationmark")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("detail.addCVV")
            }
            topActions(card)
            LowBalanceCardPanel(card: card, reminder: model.useReminders[cardID], onRemind: {
                showUseReminder = true
            }, onCancel: {
                Task { await model.cancelUseReminder(cardID: cardID) }
            })
            failureBanner(card)
            transactionPanel(card)
            Label("Secure details never leave your device.", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private func toggleArchive(for card: VaultCard) {
        do {
            if card.isArchived {
                try model.unarchiveCard(id: card.id)
            } else {
                try model.archiveCard(id: card.id)
            }
        } catch {
            model.alertMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func failureBanner(_ card: VaultCard) -> some View {
        if card.fetchFailureCount > 0 {
            let message = card.lastFetchedAt == nil
                ? "Balance refresh has failed \(card.fetchFailureCount) time(s)."
                : "Balance may be stale after \(card.fetchFailureCount) failed refresh attempt(s)."
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(VaultTheme.warning)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VaultTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func topActions(_ card: VaultCard) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                cardActionButton(
                    title: revealedCredentials == nil ? (model.isAuthenticating ? "Checking…" : "Reveal") : "Hide",
                    systemImage: revealedCredentials == nil ? "eye.fill" : "eye.slash.fill",
                    identifier: "detail.reveal",
                    action: toggleReveal
                )
                cardActionButton(
                    title: "Check Balance",
                    systemImage: "arrow.clockwise",
                    identifier: "detail.refresh"
                ) {
                    if needsCVV { showCVVEditor = true }
                    else { model.routePath.append(.giftCardMall(cardID)) }
                }
            }
            Label(
                card.lastFetchedAt.map { "Last refreshed \($0.formatted(date: .abbreviated, time: .shortened))" }
                    ?? "Never refreshed",
                systemImage: "clock"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("detail.last-refresh")
        }
    }

    private func cardActionButton(title: String, systemImage: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
        }
        .accessibilityIdentifier(identifier)
        .vaultGlass(cornerRadius: 20, interactive: true)
    }

    private func transactionPanel(_ card: VaultCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transactions").font(.headline)
            VaultSurface(padding: 0) {
                if card.transactions.isEmpty {
                    Label("No transaction history available", systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(card.transactions.enumerated()), id: \.element.id) { index, tx in
                            transactionRow(tx)
                            if index < card.transactions.count - 1 { Divider().padding(.leading, 56) }
                        }
                    }
                }
            }
        }
    }

    private func transactionRow(_ transaction: CardTransaction) -> some View {
        HStack {
            TransactionIcon(amount: transaction.amount)
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description).font(.subheadline.weight(.medium))
                Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            TransactionAmountLabel(amount: transaction.amount)
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    private func toggleReveal() {
        if revealedCredentials != nil {
            clearReveal()
        } else {
            Task {
                do {
                    revealedCredentials = try await model.revealCardCredentials(id: cardID)
                    scheduleHide()
                } catch {
                    model.alertMessage = error.localizedDescription
                }
            }
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(30))
            if !Task.isCancelled {
                clearReveal()
            }
        }
    }

    private func copyCardNumber() {
        guard let revealedCredentials else { return }
        UIPasteboard.general.setItems(
            [["public.utf8-plain-text": CardRules.digitsOnly(revealedCredentials.cardNumber)]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(120)
            ]
        )
        copyFeedbackTask?.cancel()
        isCardNumberCopied = true
        copyFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            isCardNumberCopied = false
            copyFeedbackTask = nil
        }
    }

    private func clearReveal() {
        hideTask?.cancel()
        hideTask = nil
        copyFeedbackTask?.cancel()
        copyFeedbackTask = nil
        isCardNumberCopied = false
        revealedCredentials = nil
    }

}

struct GiftCardMallRefreshView: View {
    @Environment(AppModel.self) private var model
    let cardID: String
    @State private var summary: GiftCardMallSummaryCapture?
    @State private var transactionFromDate = Date()
    @State private var credentials: CardCredentials?
    @State private var isPageLoading = true
    @State private var isPreparingAutofill = false
    @State private var isBrowserReady = false
    @State private var preparationError: String?
    @State private var pageLoadFailed = false
    @State private var showUseReminder = false
    @State private var showBalanceSaved = false

    var body: some View {
        ZStack {
            VaultBackground()
            if isBrowserReady {
                GiftCardMallWebView(
                    credentials: credentials,
                    transactionFromDate: transactionFromDate,
                    onLoadingChange: { isLoading in
                        isPageLoading = isLoading
                        if isLoading { pageLoadFailed = false }
                    },
                    onNavigationError: { pageLoadFailed = $0 }
                ) { body, url in
                    do {
                        if let captured = try GiftCardMallBridge.parseSummary(body, sourceURL: url) {
                            let existingTransactions = model.cards.first { $0.id == cardID }?.transactions ?? []
                            let accepted = model.applyForegroundRefresh(
                                id: cardID,
                                result: BalanceResult(balance: captured.balance, transactions: existingTransactions, fetchedAt: Date()),
                                isAuthoritativeBalance: true
                            )
                            if accepted { summary = captured }
                            return
                        }
                        if let summary, let result = try GiftCardMallBridge.parseTransactions(body, sourceURL: url, summary: summary) {
                            guard !result.transactions.isEmpty else { return }
                            let existing = model.cards.first { $0.id == cardID }?.transactions ?? []
                            let merged = BalanceResult(
                                balance: result.balance,
                                transactions: TransactionRefreshPolicy.merge(existing: existing, incoming: result.transactions),
                                fetchedAt: result.fetchedAt
                            )
                            model.applyForegroundRefresh(id: cardID, result: merged)
                        }
                    } catch {
                        model.alertMessage = error.localizedDescription
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            } else if let preparationError {
                ContentUnavailableView(
                    "Balance check unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(preparationError)
                )
                .padding(24)
            }
            if !isBrowserReady && preparationError == nil {
                ProgressView("Opening secure balance check…")
                    .padding(16)
                    .vaultGlass(cornerRadius: 18)
            } else if isBrowserReady && isPageLoading {
                ProgressView("Loading balance page…")
                    .padding(16)
                    .vaultGlass(cornerRadius: 18)
            }
            if isBrowserReady && pageLoadFailed {
                VStack {
                    VStack(spacing: 8) {
                        Label("Balance page couldn’t be loaded", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Check your connection and try again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Retry", action: reloadPage)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityIdentifier("balance.retry")
                    }
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    Spacer(minLength: 0)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let summary, !pageLoadFailed, showBalanceSaved || canOfferUseReminder || automaticArchiveNotice != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if showBalanceSaved && automaticArchiveNotice == nil {
                        Label("Balance saved: \(summary.balance.formatted(.currency(code: "USD")))", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("balance.saved")
                    }
                    if let prompt = automaticArchiveNotice {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Archived automatically", systemImage: "archivebox.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .accessibilityIdentifier("balance.archived")
                                Text("\(prompt.cardName) (•••• \(prompt.last4)) moved to Archived Cards.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button("Undo") { model.resolveZeroBalancePrompt(.keepThisCard) }
                                .font(.subheadline.weight(.semibold))
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityIdentifier("balance.archiveUndo")
                        }
                    }
                    if let card = model.cards.first(where: { $0.id == cardID }), !card.isArchived,
                       let balance = card.balance, balance > 0, balance < 10 {
                        Button(model.useReminders[cardID] == nil ? "Remind me to use this" : "Edit reminder") { showUseReminder = true }
                            .accessibilityIdentifier("reminder.open")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .confirmationDialog(
            "No balance left",
            isPresented: Binding(
                get: { archiveChoicePrompt != nil },
                set: { isPresented in
                    guard !isPresented, archiveChoicePrompt != nil else { return }
                    model.resolveZeroBalancePrompt(.notNow)
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Keep This Time", role: .cancel) { model.resolveZeroBalancePrompt(.notNow) }
            Button("Always Keep in Vault") { model.resolveZeroBalancePrompt(.alwaysKeep) }
            Button("Archive This Card") { model.resolveZeroBalancePrompt(.archiveThisCard) }
            Button("Always Archive $0 Cards") { model.resolveZeroBalancePrompt(.alwaysArchive) }
        } message: {
            if let prompt = archiveChoicePrompt {
                Text("\(prompt.cardName) (•••• \(prompt.last4)) has a $0.00 balance. The “Always” options remember your choice.")
            }
        }
        .sheet(isPresented: $showUseReminder) {
            if let card = model.cards.first(where: { $0.id == cardID }) {
                CardUseReminderView(card: card, reminder: model.useReminders[cardID]) { date in
                    try await model.scheduleUseReminder(cardID: cardID, at: date)
                }
            }
        }
        .navigationTitle("Check Balance")
        .task(id: summary?.balance) {
            guard summary != nil else { showBalanceSaved = false; return }
            showBalanceSaved = true
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            showBalanceSaved = false
        }
        .task(id: model.zeroBalancePrompt?.id) {
            guard let notice = automaticArchiveNotice else { return }
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard model.zeroBalancePrompt?.id == notice.id else { return }
            model.resolveZeroBalancePrompt(.done)
        }
        .task { await prepareBrowserAfterTransition() }
        .onDisappear {
            credentials = nil
            if automaticArchiveNotice != nil { model.resolveZeroBalancePrompt(.done) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    if let credentials {
                        NotificationCenter.default.post(name: .giftCardMallAutofill, object: credentials)
                    }
                } label: {
                    Image(systemName: "rectangle.and.pencil.and.ellipsis")
                }
                .accessibilityLabel("Autofill Again")
                .disabled(credentials == nil || isPreparingAutofill || !isBrowserReady)

                Button {
                    reloadPage()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Reload Page")
                .disabled(!isBrowserReady)
            }
        }
    }

    private var canOfferUseReminder: Bool {
        guard let card = model.cards.first(where: { $0.id == cardID }), !card.isArchived,
              let balance = card.balance else { return false }
        return balance.isFinite && balance > 0 && balance < 10
    }

    private var automaticArchiveNotice: ZeroBalancePrompt? {
        guard let prompt = model.zeroBalancePrompt,
              prompt.cardID == cardID,
              prompt.kind == .autoArchived else { return nil }
        return prompt
    }

    private var archiveChoicePrompt: ZeroBalancePrompt? {
        guard let prompt = model.zeroBalancePrompt,
              prompt.cardID == cardID,
              prompt.kind == .offerArchive else { return nil }
        return prompt
    }

    private func reloadPage() {
        model.beginForegroundRefresh(id: cardID)
        summary = nil
        pageLoadFailed = false
        isPageLoading = true
        NotificationCenter.default.post(name: .giftCardMallReload, object: nil)
    }

    private func prepareBrowserAfterTransition() async {
        guard credentials == nil, !isPreparingAutofill else { return }
        isPreparingAutofill = true
        defer { isPreparingAutofill = false }

        // Constructing WKWebView can briefly occupy the main thread. Let the native
        // navigation animation finish first so the detail-to-browser push stays fluid.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            credentials = try await model.credentialsForAutofill(id: cardID)
            model.beginForegroundRefresh(id: cardID)
            // Freeze the range before any response updates the saved history.
            transactionFromDate = TransactionRefreshPolicy.fromDate(
                transactions: model.cards.first { $0.id == cardID }?.transactions ?? [],
                now: Date(), calendar: Calendar(identifier: .gregorian)
            )
            isBrowserReady = true
        } catch {
            preparationError = error.localizedDescription
        }
    }
}

extension Notification.Name {
    static let giftCardMallAutofill = Notification.Name("giftCardMallAutofill")
    static let giftCardMallReload = Notification.Name("giftCardMallReload")
}

struct GiftCardMallWebView: UIViewRepresentable {
    var credentials: CardCredentials?
    var transactionFromDate: Date
    var onLoadingChange: (Bool) -> Void
    var onNavigationError: (Bool) -> Void
    var onMessage: (Any, URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoadingChange: onLoadingChange, onNavigationError: onNavigationError, onMessage: onMessage)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(WKUserScript(
            source: GiftCardMallBridge.cardSubmissionReadinessScript(), injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        configuration.userContentController.add(context.coordinator, name: GiftCardMallBridge.handlerName)
        let readyScript = GiftCardMallBridge.installScript()
            + "\n" + GiftCardMallBridge.transactionDateScript(fromDate: transactionFromDate, calendar: Calendar(identifier: .gregorian))
            + "\nwindow.webkit.messageHandlers." + GiftCardMallBridge.handlerName + ".postMessage({kind: 'vaultcardPageReady'});"
        configuration.userContentController.addUserScript(WKUserScript(
            source: readyScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = true
        webView.scrollView.alwaysBounceVertical = true
        webView.scrollView.keyboardDismissMode = .interactive
        context.coordinator.webView = webView
        context.coordinator.updateCredentials(credentials)
        let network = credentials.map { CardRules.inferNetwork($0.cardNumber) } ?? .unknown
        let loadRequest = URLRequest(url: GiftCardMallBridge.balanceURL(for: network), timeoutInterval: 30)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing") && arguments.contains("--ui-testing-web-failure") {
            let coordinator = context.coordinator
            DispatchQueue.main.async {
                coordinator.onLoadingChange(false)
                coordinator.onNavigationError(true)
            }
        } else if arguments.contains("--ui-testing") && (arguments.contains("--ui-testing-zero-refresh") || arguments.contains("--ui-testing-low-refresh")) {
            let coordinator = context.coordinator
            let trustedURL = GiftCardMallBridge.balanceURL(for: network)
            let message: [String: Any] = [
                "namespace": GiftCardMallBridge.handlerName,
                "parserVersion": GiftCardMallBridge.parserVersion,
                "pageHost": trustedURL.host ?? "",
                "kind": "domBalance",
                "source": "availableBalanceSummary",
                "balance": arguments.contains("--ui-testing-low-refresh") ? 3.99 : 0
            ]
            DispatchQueue.main.async {
                coordinator.onLoadingChange(false)
                coordinator.onNavigationError(false)
                coordinator.onMessage(message, trustedURL)
            }
        } else {
            webView.load(loadRequest)
        }
        context.coordinator.installObservers()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onLoadingChange = onLoadingChange
        context.coordinator.onNavigationError = onNavigationError
        context.coordinator.onMessage = onMessage
        context.coordinator.updateCredentials(credentials)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: GiftCardMallBridge.handlerName)
        coordinator.removeObservers()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onLoadingChange: (Bool) -> Void
        var onNavigationError: (Bool) -> Void
        var onMessage: (Any, URL?) -> Void
        weak var webView: WKWebView?
        private var tokens: [NSObjectProtocol] = []
        private var credentials: CardCredentials?
        private var lastAppliedCredentials: CardCredentials?
        private var pageReady = false
        private var navigationTimeout: DispatchWorkItem?

        init(onLoadingChange: @escaping (Bool) -> Void, onNavigationError: @escaping (Bool) -> Void, onMessage: @escaping (Any, URL?) -> Void) {
            self.onLoadingChange = onLoadingChange
            self.onNavigationError = onNavigationError
            self.onMessage = onMessage
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            cancelNavigationTimeout()
            pageReady = false
            lastAppliedCredentials = nil
            onNavigationError(false)
            onLoadingChange(true)
            let timeout = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView, webView.isLoading else { return }
                self.navigationTimeout = nil
                self.pageReady = false
                self.onLoadingChange(false)
                self.onNavigationError(true)
                webView.stopLoading()
            }
            navigationTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            cancelNavigationTimeout()
            guard GiftCardMallBridge.isAllowed(webView.url) else {
                pageReady = false
                onLoadingChange(false)
                onNavigationError(true)
                return
            }
            webView.evaluateJavaScript(GiftCardMallBridge.installScript()) { [weak self] _, _ in
                guard let self else { return }
                self.pageReady = true
                self.onLoadingChange(false)
                self.onNavigationError(false)
                self.applyAutofillIfReady()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            cancelNavigationTimeout()
            guard !isNavigationCancellation(error) else { return }
            pageReady = false
            onLoadingChange(false)
            onNavigationError(true)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            cancelNavigationTimeout()
            guard !isNavigationCancellation(error) else { return }
            pageReady = false
            onLoadingChange(false)
            onNavigationError(true)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let targetFrame = navigationAction.targetFrame, !targetFrame.isMainFrame {
                // GiftCardMall may embed a third-party anti-bot challenge. It can run in
                // its subframe, but the top-level browser remains pinned to GiftCardMall.
                decisionHandler(.allow)
                return
            }
            guard GiftCardMallBridge.isAllowed(navigationAction.request.url) else {
                decisionHandler(.cancel)
                onLoadingChange(false)
                onNavigationError(true)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            guard navigationResponse.isForMainFrame else {
                decisionHandler(.allow)
                return
            }
            guard GiftCardMallBridge.isAllowed(navigationResponse.response.url) else {
                decisionHandler(.cancel)
                onLoadingChange(false)
                onNavigationError(true)
                return
            }
            if let response = navigationResponse.response as? HTTPURLResponse,
               !GiftCardMallBridge.canDisplayBalanceResponse(url: response.url, statusCode: response.statusCode, mimeType: response.mimeType) {
                decisionHandler(.cancel)
                onLoadingChange(false)
                onNavigationError(true)
                return
            }
            decisionHandler(.allow)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == GiftCardMallBridge.handlerName,
                  message.frameInfo.isMainFrame,
                  let pageURL = webView?.url,
                  GiftCardMallBridge.isTrustedMainFrame(
                    isMainFrame: message.frameInfo.isMainFrame,
                    scheme: message.frameInfo.securityOrigin.protocol,
                    host: message.frameInfo.securityOrigin.host,
                    port: message.frameInfo.securityOrigin.port,
                    pageURL: pageURL
                  )
            else { return }
            if let payload = message.body as? [String: Any], payload["kind"] as? String == "vaultcardPageReady" {
                cancelNavigationTimeout()
                pageReady = true
                onLoadingChange(false)
                onNavigationError(false)
                applyAutofillIfReady()
                return
            }
            onMessage(message.body, pageURL)
        }

        func installObservers() {
            tokens.append(NotificationCenter.default.addObserver(forName: .giftCardMallAutofill, object: nil, queue: .main) { [weak self] notification in
                guard let credentials = notification.object as? CardCredentials else { return }
                guard let self else { return }
                // This toolbar action is an explicit retry, unlike repeated page-ready events.
                self.webView?.evaluateJavaScript("if (window.__vaultCardAutofillState) { window.__vaultCardAutofillState.submitted = false; window.__vaultCardAutofillState.userEdited = new WeakSet(); }") { [weak self] _, _ in
                    self?.lastAppliedCredentials = nil
                    self?.updateCredentials(credentials)
                }
            })
            tokens.append(NotificationCenter.default.addObserver(forName: .giftCardMallReload, object: nil, queue: .main) { [weak self] _ in
                guard let self, let webView = self.webView else { return }
                let network = self.credentials.map { CardRules.inferNetwork($0.cardNumber) } ?? .unknown
                webView.load(URLRequest(url: GiftCardMallBridge.balanceURL(for: network), timeoutInterval: 30))
            })
        }

        func removeObservers() {
            cancelNavigationTimeout()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens.removeAll()
        }

        func updateCredentials(_ credentials: CardCredentials?) {
            if self.credentials != credentials {
                lastAppliedCredentials = nil
            }
            self.credentials = credentials
            applyAutofillIfReady()
        }

        private func applyAutofillIfReady() {
            guard pageReady,
                  let credentials,
                  let webView,
                  lastAppliedCredentials != credentials,
                  GiftCardMallBridge.isAllowed(webView.url)
            else { return }
            lastAppliedCredentials = credentials
            webView.evaluateJavaScript(GiftCardMallBridge.autofillScript(credentials: credentials))
        }

        private func cancelNavigationTimeout() {
            navigationTimeout?.cancel()
            navigationTimeout = nil
        }

        private func isNavigationCancellation(_ error: Error) -> Bool {
            let error = error as NSError
            return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
        }

    }
}

struct VaultAppIconChoice: Identifiable, Hashable {
    let id: String
    let title: String
    let alternateIconName: String?
    let previewAssetName: String
}

enum VaultAppIcons {
    static let choices = [
        VaultAppIconChoice(
            id: "primary",
            title: "Card Stack",
            alternateIconName: nil,
            previewAssetName: "VaultCardIconPreview"
        ),
        VaultAppIconChoice(
            id: "blue-wallet",
            title: "Blue Wallet",
            alternateIconName: "VaultIconBlueWallet",
            previewAssetName: "VaultIconBlueWalletPreview"
        ),
        VaultAppIconChoice(
            id: "midnight-shield",
            title: "Midnight Shield",
            alternateIconName: "VaultIconMidnightShield",
            previewAssetName: "VaultIconMidnightShieldPreview"
        ),
        VaultAppIconChoice(
            id: "electric-stack",
            title: "Electric Stack",
            alternateIconName: "VaultIconElectricStack",
            previewAssetName: "VaultIconElectricStackPreview"
        ),
        VaultAppIconChoice(
            id: "sunset-stack",
            title: "Sunset Stack",
            alternateIconName: "VaultIconSunsetStack",
            previewAssetName: "VaultIconSunsetStackPreview"
        ),
        VaultAppIconChoice(
            id: "teal-stack",
            title: "Teal Stack",
            alternateIconName: "VaultIconTealStack",
            previewAssetName: "VaultIconTealStackPreview"
        ),
        VaultAppIconChoice(
            id: "frost-stack",
            title: "Frost Stack",
            alternateIconName: "VaultIconFrostStack",
            previewAssetName: "VaultIconFrostStackPreview"
        ),
        VaultAppIconChoice(
            id: "aurora-stack",
            title: "Aurora Stack",
            alternateIconName: "VaultIconAuroraStack",
            previewAssetName: "VaultIconAuroraStackPreview"
        ),
        VaultAppIconChoice(
            id: "midnight-stack",
            title: "Midnight Stack",
            alternateIconName: "VaultIconMidnightStack",
            previewAssetName: "VaultIconMidnightStackPreview"
        ),
        VaultAppIconChoice(
            id: "aurora-wallet",
            title: "Aurora Wallet",
            alternateIconName: "VaultIconAuroraWallet",
            previewAssetName: "VaultIconAuroraWalletPreview"
        ),
        VaultAppIconChoice(
            id: "teal-wallet",
            title: "Teal Wallet",
            alternateIconName: "VaultIconTealWallet",
            previewAssetName: "VaultIconTealWalletPreview"
        ),
        VaultAppIconChoice(
            id: "pearl-wallet",
            title: "Pearl Wallet",
            alternateIconName: "VaultIconPearlWallet",
            previewAssetName: "VaultIconPearlWalletPreview"
        ),
        VaultAppIconChoice(
            id: "prism-wallet",
            title: "Prism Wallet",
            alternateIconName: "VaultIconPrismWallet",
            previewAssetName: "VaultIconPrismWalletPreview"
        )
    ]

    static func choice(for alternateIconName: String?) -> VaultAppIconChoice {
        choices.first { $0.alternateIconName == alternateIconName } ?? choices[0]
    }
}

struct AppIconPickerView: View {
    @State private var selectedIconName = UIApplication.shared.alternateIconName
    @State private var isChanging = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 132), spacing: 18)]

    var body: some View {
        ZStack {
            VaultBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Choose the icon VaultCard uses on your Home Screen.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(VaultAppIcons.choices) { choice in
                            Button { select(choice) } label: {
                                VStack(spacing: 10) {
                                    Image(choice.previewAssetName)
                                        .resizable()
                                        .scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                                        .overlay(alignment: .topTrailing) {
                                            if selectedIconName == choice.alternateIconName {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.title2)
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, VaultTheme.electricBlue)
                                                    .padding(8)
                                            }
                                        }
                                    Text(choice.title)
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isChanging || selectedIconName == choice.alternateIconName)
                            .accessibilityLabel("\(choice.title) app icon")
                            .accessibilityValue(selectedIconName == choice.alternateIconName ? "Selected" : "Available")
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(VaultTheme.danger)
                    }
                }
                .padding(20)
            }
            .vaultFloatingBarScrollClearance()
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func select(_ choice: VaultAppIconChoice) {
        guard selectedIconName != choice.alternateIconName else { return }
        isChanging = true
        errorMessage = nil
        UIApplication.shared.setAlternateIconName(choice.alternateIconName) { error in
            Task { @MainActor in
                isChanging = false
                if let error {
                    errorMessage = error.localizedDescription
                } else {
                    selectedIconName = choice.alternateIconName
                }
            }
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedAppIconName = UIApplication.shared.alternateIconName

    var body: some View {
        @Bindable var model = model
        let selectedAppIcon = VaultAppIcons.choice(for: selectedAppIconName)
        ZStack {
            VaultBackground()
            Form {
                Section("Adding Cards") {
                    Picker(
                        "Default add method",
                        selection: Binding(
                            get: { model.settings.addCardPreference },
                            set: { value in model.updateSettings { $0.addCardPreference = value } }
                        )
                    ) {
                        ForEach(AddCardPreference.allCases) { preference in
                            Text(preference.label).tag(preference)
                        }
                    }
                    Text("The center plus button opens this method directly. Manual entry remains available from the scan screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Balances") {
                    HStack(spacing: 5) {
                        Text("Needs refresh after")
                        Spacer(minLength: 4)
                        TextField("7", value: refreshAfterDaysBinding, format: .number)
                            .frame(width: 42)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .accessibilityLabel("Needs refresh after days")
                            .accessibilityIdentifier("settings.refreshAfterDays")
                        Text("days")
                        Stepper("", value: refreshAfterDaysBinding, in: 1...365)
                            .labelsHidden()
                            .accessibilityLabel("Adjust refresh interval")
                            .accessibilityIdentifier("settings.refreshAfterDays.stepper")
                    }
                    Toggle(isOn: Binding(
                        get: { model.settings.archiveZeroBalanceCardsAutomatically },
                        set: { value in model.updateSettings { $0.archiveZeroBalanceCardsAutomatically = value } }
                    )) {
                        Text("Archive $0 cards automatically")
                    }
                    if model.settings.archiveZeroBalanceCardsAutomatically {
                        Text("Cards with a $0 balance move to Archived Cards after a balance check. A brief confirmation includes Undo; no tap is needed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Toggle(isOn: Binding(
                            get: { model.settings.askAboutZeroBalanceCards },
                            set: { value in model.updateSettings { $0.askAboutZeroBalanceCards = value } }
                        )) {
                            Text("Ask about $0 cards")
                        }
                        .accessibilityIdentifier("settings.askZeroBalance")
                        Text(model.settings.askAboutZeroBalanceCards
                             ? "Choose whether to archive each $0 card."
                             : "$0 cards stay in your Vault without prompts. You can archive them manually.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Security") {
                    Label("Face ID", systemImage: "faceid")
                    Toggle(isOn: Binding(get: { model.settings.appLockEnabled }, set: { value in model.updateSettings { $0.appLockEnabled = value } })) {
                        Label("App Lock", systemImage: "lock.fill")
                    }
                }
                Section("Notifications") {
                    Toggle(isOn: Binding(get: { model.settings.notificationPreferences.expiryWarning }, set: { value in
                        model.updateSettings { $0.notificationPreferences.expiryWarning = value }
                        if value { Task { await model.requestNotificationAuthorization() } }
                    })) {
                        Label("Unused balance expiry reminder", systemImage: "calendar.badge.exclamationmark")
                    }
                    .accessibilityIdentifier("settings.expiryWarnings")
                    if model.settings.notificationPreferences.expiryWarning {
                        HStack(spacing: 5) {
                            Text("Reminder lead time")
                            Spacer(minLength: 4)
                            TextField("30", value: expiryWarningDaysBinding, format: .number)
                                .frame(width: 42)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                                .accessibilityLabel("Expiry reminder days")
                                .accessibilityIdentifier("settings.expiryWarningDays")
                            Text("days")
                            Stepper("", value: expiryWarningDaysBinding, in: 1...365)
                                .labelsHidden()
                                .accessibilityLabel("Adjust expiry reminder lead time")
                                .accessibilityIdentifier("settings.expiryWarningDays.stepper")
                        }
                        Text("Reminds you when a card has a last-known positive balance before it expires at the end of its expiry month.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("For a saved balance below $10, open the card and choose ‘Remind me to use this’ to set a one-time reminder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.notificationsAllowed == false {
                        Button("Enable Notifications") {
                            Task {
                                await model.requestNotificationAuthorization()
                                if model.notificationsAllowed == false,
                                   let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                    await UIApplication.shared.open(url)
                                }
                            }
                        }
                        .accessibilityIdentifier("settings.enableNotifications")
                    }
                }
                Section("Privacy") {
                    HStack(spacing: 12) {
                        Label("On-device privacy", systemImage: "lock.fill")
                        Spacer()
                        Text("Always on")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("settings.privacy.onDevice")
                    .accessibilityLabel("On-device privacy")
                    .accessibilityValue("Always on")
                    Text("Card data and sensitive details stay on this device. Privacy protections are always enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Appearance") {
                    NavigationLink {
                        AppIconPickerView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(selectedAppIcon.previewAssetName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 42, height: 42)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("App Icon")
                                Text(selectedAppIcon.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("settings.appIcon")
                }
                Section("About") {
                    LabeledContent("Version", value: "1.0")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .vaultFloatingBarScrollClearance()
        }
        .navigationTitle("Settings")
        .onAppear {
            selectedAppIconName = UIApplication.shared.alternateIconName
        }
    }

    private var expiryWarningDaysBinding: Binding<Int> {
        Binding(
            get: { model.settings.notificationPreferences.expiryWarningDays },
            set: { value in model.updateSettings { $0.notificationPreferences.expiryWarningDays = value } }
        )
    }

    private var refreshAfterDaysBinding: Binding<Int> {
        Binding(
            get: { model.settings.refreshAfterDays },
            set: { value in model.updateSettings { $0.refreshAfterDays = value } }
        )
    }
}

struct LockOverlayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            VaultBrandMark(size: 88)
            Text("VaultCard is locked").font(.title2.bold())
            Text("Authenticate with biometrics or device passcode to continue.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(model.isAuthenticating ? "Unlocking..." : "Unlock") {
                Task { await model.unlockIfNeeded() }
            }
            .font(.headline)
            .controlSize(.large)
            .vaultPrimaryButton()
            .disabled(model.isAuthenticating)
        }
        .padding(28)
        .frame(maxWidth: 340)
        .vaultGlass(cornerRadius: 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VaultBackground())
    }
}
