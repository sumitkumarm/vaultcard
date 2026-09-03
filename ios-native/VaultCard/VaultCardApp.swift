import AVFoundation
import CoreImage
import Foundation
import LocalAuthentication
import Observation
import Security
import SwiftData
import SwiftUI
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

    static let balanceFreshnessInterval: TimeInterval = 24 * 60 * 60

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

    func balanceFreshness(at date: Date = Date()) -> BalanceFreshness {
        guard fetchFailureCount == 0, let lastFetchedAt else { return .needsRefresh }
        return date.timeIntervalSince(lastFetchedAt) <= Self.balanceFreshnessInterval
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
    var lowBalance = true
    var balanceUpdated = false
    var refreshFailed = true
    var privacyPreservingContent = true
}

struct AppSettings: Codable, Equatable {
    var onboardingCompleted = false
    var appLockEnabled = false
    var analyticsEnabled = false
    var sortOption = CardSortOption.dateAddedNewest
    var notificationPreferences = NotificationPreferences()
    var addCardPreference = AddCardPreference.scan
    var hasSeenSwipeArchiveConfirmation = false

    private enum CodingKeys: String, CodingKey {
        case onboardingCompleted
        case appLockEnabled
        case analyticsEnabled
        case sortOption
        case notificationPreferences
        case addCardPreference
        case hasSeenSwipeArchiveConfirmation
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        onboardingCompleted = try values.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        appLockEnabled = try values.decodeIfPresent(Bool.self, forKey: .appLockEnabled) ?? false
        analyticsEnabled = try values.decodeIfPresent(Bool.self, forKey: .analyticsEnabled) ?? false
        sortOption = try values.decodeIfPresent(CardSortOption.self, forKey: .sortOption) ?? .dateAddedNewest
        notificationPreferences = try values.decodeIfPresent(NotificationPreferences.self, forKey: .notificationPreferences) ?? NotificationPreferences()
        addCardPreference = try values.decodeIfPresent(AddCardPreference.self, forKey: .addCardPreference) ?? .scan
        hasSeenSwipeArchiveConfirmation = try values.decodeIfPresent(Bool.self, forKey: .hasSeenSwipeArchiveConfirmation) ?? false
    }
}

struct BalanceResult: Equatable {
    var balance: Double
    var transactions: [CardTransaction]
    var fetchedAt: Date
}

enum RefreshFailureReason: String, Equatable {
    case network
    case parseError
    case rateLimited
    case offline
    case botProtection
    case credentialUnavailable
    case unknown
}

struct RefreshFailure: Equatable {
    var reason: RefreshFailureReason
    var message: String
}

enum RefreshOutcome: Equatable {
    case success(BalanceResult)
    case failure(RefreshFailure)
    case cooldown(Date)
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
    func markRefreshFailure(cardID: String) throws
    func updateRefreshCooldown(cardID: String, until: Date) throws
}

protocol SettingsRepository {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

protocol BiometricAuthenticating {
    func authenticate(reason: String) async -> Bool
}

protocol BalanceRefreshing {
    func refreshCard(_ cardID: String, ignoreCooldown: Bool, preferences: NotificationPreferences) async -> RefreshOutcome
}

enum ScanRecognitionMode {
    case live
    case still
}

protocol CardScanning {
    func extractCandidates(from image: CGImage, mode: ScanRecognitionMode) async throws -> ScanCandidate
    func extractCandidates(from text: String) -> ScanCandidate
}

protocol NotificationScheduling {
    func requestAuthorization() async
    func syncForCard(_ card: VaultCard, preferences: NotificationPreferences) async
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

    func markRefreshFailure(cardID: String) throws {
        guard let record = try findRecord(id: cardID) else { throw VaultError.cardNotFound }
        record.fetchFailureCount += 1
        try context.save()
    }

    func updateRefreshCooldown(cardID: String, until: Date) throws {
        guard let record = try findRecord(id: cardID) else { throw VaultError.cardNotFound }
        record.refreshBlockedUntil = until
        try context.save()
    }

    private func findRecord(id: String) throws -> SchemaV2.CardMetadataRecord? {
        let descriptor = FetchDescriptor<SchemaV2.CardMetadataRecord>(
            predicate: #Predicate { $0.id == id }
        )
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

struct NoopNotificationService: NotificationScheduling {
    func requestAuthorization() async {}
    func syncForCard(_ card: VaultCard, preferences: NotificationPreferences) async {}
}

final class NotificationService: NSObject, NotificationScheduling, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func syncForCard(_ card: VaultCard, preferences: NotificationPreferences) async {
        if preferences.lowBalance, let balance = card.balance, balance < 10, card.fetchFailureCount == 0 {
            await addNotification(id: "\(card.id).low", title: "A saved card may need attention", body: "Open VaultCard to review a low balance.")
        }
        if preferences.refreshFailed, card.fetchFailureCount >= 2 {
            await addNotification(id: "\(card.id).refreshFailed", title: "A saved card may need attention", body: "Open VaultCard to retry a failed refresh.")
        }
        if preferences.expiryWarning {
            await scheduleExpiry(card)
        }
    }

    private func scheduleExpiry(_ card: VaultCard) async {
        guard let expiryDate = resolveExpiryDate(card.expiry) else { return }
        for days in [30, 7] {
            let date = expiryDate.addingTimeInterval(TimeInterval(-days * 24 * 60 * 60))
            guard date > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = "A saved card may need attention"
            content.body = "Open VaultCard to review an upcoming expiry."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour], from: date), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "\(card.id).expiry.\(days)", content: content, trigger: trigger))
        }
    }

    private func addNotification(id: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    private func resolveExpiryDate(_ expiry: String) -> Date? {
        let parts = expiry.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(from: DateComponents(year: 2000 + parts[1], month: parts[0] + 1, day: 0, hour: 12))
    }
}

struct ParserConfig: Codable {
    struct FormFields: Codable {
        var cardNumber: String
        var expiryMonth: String
        var expiryYear: String
        var cvv: String
        var pin: String
    }

    struct TransactionFields: Codable {
        var date: String
        var description: String
        var amount: String
    }

    var version: Int
    var endpointUrl: URL
    var formFields: FormFields
    var balanceSelector: String
    var transactionSelector: String
    var transactionFields: TransactionFields

    static func bundled() -> ParserConfig {
        if let url = Bundle.main.url(forResource: "ParserConfig", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(ParserConfig.self, from: data) {
            return config
        }
        return ParserConfig(
            version: 1,
            endpointUrl: URL(string: "https://mygift.giftcardmall.com")!,
            formFields: FormFields(cardNumber: "cardNumber", expiryMonth: "expMonth", expiryYear: "expYear", cvv: "cvv", pin: "pin"),
            balanceSelector: ".balance-amount",
            transactionSelector: "table.transactions tbody tr",
            transactionFields: TransactionFields(date: ".date", description: ".description", amount: ".amount")
        )
    }
}

enum HtmlBalanceParser {
    static func parse(_ body: String, config: ParserConfig, fetchedAt: Date = Date()) throws -> BalanceResult {
        let balance = try parseBalance(body, selector: config.balanceSelector)
        return BalanceResult(balance: balance, transactions: parseTransactions(body), fetchedAt: fetchedAt)
    }

    private static func parseBalance(_ body: String, selector: String) throws -> Double {
        let candidates = [
            #"<[^>]*class=["'][^"']*balance-amount[^"']*["'][^>]*>([^<]+)</[^>]+>"#,
            #""closingBalance"\s*:\s*([0-9]+(?:\.[0-9]+)?)"#,
            #"\$\s*([0-9]+(?:\.[0-9]{2})?)"#
        ]
        for pattern in candidates {
            if let raw = body.firstMatch(pattern, group: 1) {
                let normalized = raw.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if let value = Double(normalized), value >= 0 {
                    return value
                }
            }
        }
        throw VaultError.refresh("Unable to parse balance response.")
    }

    private static func parseTransactions(_ body: String) -> [CardTransaction] {
        let rowPattern = #"<tr[^>]*>(.*?)</tr>"#
        return body.allMatches(rowPattern).compactMap { row in
            let cells = row.allMatches(#"<t[dh][^>]*>(.*?)</t[dh]>"#).map { $0.strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard cells.count >= 3 else { return nil }
            let date = DateFormatter.yyyyMMdd.date(from: cells[0]) ?? Date()
            let amount = Double(cells[2].replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")) ?? 0
            return CardTransaction(date: date, description: cells[1], amount: amount)
        }
    }
}

final class GiftCardMallDirectClient {
    func fetchBalance(config: ParserConfig, credentials: CardCredentials) async throws -> String {
        var request = URLRequest(url: config.endpointUrl)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.httpBody = [
            config.formFields.cardNumber: credentials.cardNumber,
            config.formFields.expiryMonth: credentials.expiryMonth,
            config.formFields.expiryYear: credentials.expiryYear,
            config.formFields.cvv: credentials.cvv,
            config.formFields.pin: credentials.pin
        ].formURLEncoded().data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let body = String(data: data, encoding: .utf8) ?? ""
        if Self.looksLikeBotProtection(response: response, body: body) {
            throw VaultError.refresh("GiftCardMall is blocking automated balance checks right now.")
        }
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw VaultError.refresh("Unexpected response from GiftCardMall.")
        }
        return body
    }

    static func looksLikeBotProtection(response: URLResponse, body: String) -> Bool {
        let normalized = body.lowercased()
        let status = (response as? HTTPURLResponse)?.statusCode
        return normalized.contains("captcha-delivery.com")
            || normalized.contains("please enable js and disable any ad blocker")
            || (status == 405 && normalized.contains("datadome"))
    }
}

final class BalanceService: BalanceRefreshing {
    private let repository: CardRepository
    private let notifications: NotificationScheduling
    private let directClient: GiftCardMallDirectClient

    init(repository: CardRepository, notifications: NotificationScheduling, directClient: GiftCardMallDirectClient = GiftCardMallDirectClient()) {
        self.repository = repository
        self.notifications = notifications
        self.directClient = directClient
    }

    func refreshCard(_ cardID: String, ignoreCooldown: Bool, preferences: NotificationPreferences) async -> RefreshOutcome {
        do {
            guard let card = try repository.getCard(id: cardID) else {
                return .failure(RefreshFailure(reason: .unknown, message: "Card not found."))
            }
            if !ignoreCooldown, let until = card.refreshBlockedUntil, until > Date() {
                return .cooldown(until)
            }
            let credentials = try repository.getCredentials(cardID: cardID)
            let config = ParserConfig.bundled()
            let body = try await directClient.fetchBalance(config: config, credentials: credentials)
            let result = try HtmlBalanceParser.parse(body, config: config)
            try repository.applyBalanceResult(cardID: cardID, result: result)
            if let updated = try repository.getCard(id: cardID) {
                await notifications.syncForCard(updated, preferences: preferences)
            }
            return .success(result)
        } catch VaultError.credentialUnavailable {
            return .failure(RefreshFailure(reason: .credentialUnavailable, message: VaultError.credentialUnavailable.localizedDescription))
        } catch {
            try? repository.markRefreshFailure(cardID: cardID)
            return .failure(RefreshFailure(reason: .network, message: error.localizedDescription))
        }
    }
}

extension Dictionary where Key == String, Value == String {
    func formURLEncoded() -> String {
        map { key, value in
            "\(key.urlEncoded)=\(value.urlEncoded)"
        }.joined(separator: "&")
    }
}

extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
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
    static let allowedHosts: Set<String> = ["mygift.giftcardmall.com", "www.mygift.giftcardmall.com"]
    static let siteURL = URL(string: "https://mygift.giftcardmall.com/")!

    static func isAllowed(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return allowedHosts.contains(host)
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
                pageHost: window.location.host
              }, payload));
            } catch (_) {}
          };

          const cardSelectors = [
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
            const selectors = [
              '.balance-amount',
              '[data-testid*="balance"]',
              '[class*="balanceAmount"]',
              '[class*="balance-amount"]'
            ];
            for (const selector of selectors) {
              for (const element of document.querySelectorAll(selector)) {
                const match = (element.textContent || '').replace(/,/g, '').match(/\\$\\s*([0-9]+(?:\\.[0-9]{1,2})?)/);
                if (!match) { continue; }
                const balance = Number(match[1]);
                if (!Number.isFinite(balance) || balance < 0 || balance === lastDOMBalance) { continue; }
                lastDOMBalance = balance;
                post({ kind: 'domBalance', balance });
                return;
              }
            }
          };

          const originalFetch = window.fetch;
          window.fetch = async (...args) => {
            const response = await originalFetch(...args);
            try {
              const clone = response.clone();
              const text = await clone.text();
              const request = args[1] || {};
              post({
                kind: 'networkCapture',
                url: typeof args[0] === 'string' ? args[0] : ((args[0] && args[0].url) || ''),
                method: request.method || 'GET',
                requestBody: request.body || null,
                responseBody: text,
                status: response.status
              });
            } catch (_) {}
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

          const observer = new MutationObserver(() => {
            if (autoScrollEnabled) { window.__vaultCardScrollToForm(); }
            inspectBalance();
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
          const setValue = (selectors, value) => {
            for (const selector of selectors) {
              const field = document.querySelector(selector);
              if (!field) { continue; }
              field.focus();
              const prototype = field.tagName === 'SELECT' ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
              const setter = Object.getOwnPropertyDescriptor(prototype, 'value') && Object.getOwnPropertyDescriptor(prototype, 'value').set;
              if (setter) { setter.call(field, value); } else { field.value = value; }
              field.dispatchEvent(new Event('input', { bubbles: true }));
              field.dispatchEvent(new Event('change', { bubbles: true }));
              return true;
            }
            return false;
          };
          const fill = () => {
            setValue(['input[name="cardNumber"]','input[id*="cardNumber"]','input[autocomplete="cc-number"]','input[inputmode="numeric"]'], \(number));
            setValue(['input[name="expirationMonth"]','input[id*="expirationMonth"]','select[name="expirationMonth"]','input[name="expMonth"]'], \(month));
            setValue(['input[name="expirationYear"]','input[id*="expirationYear"]','select[name="expirationYear"]','input[name="expYear"]'], \(year));
            setValue(['input[name="securityCode"]','input[id*="securityCode"]','input[name="cvv"]','input[id*="cvv"]','input[autocomplete="cc-csc"]'], \(cvv));
            if (window.__vaultCardScrollToForm) { window.__vaultCardScrollToForm(true); }
          };
          fill();
          [250, 800, 1600].forEach(delay => setTimeout(fill, delay));
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
              allowedHosts.contains(pageHost.lowercased())
        else { return nil }

        if payload["kind"] as? String == "domBalance" {
            guard let balance = (payload["balance"] as? NSNumber)?.doubleValue, balance >= 0 else {
                throw VaultError.webBridge("Invalid balance value.")
            }
            return GiftCardMallSummaryCapture(
                balance: balance,
                currencyCode: "USD",
                accessToken: "",
                rmsSessionId: ""
            )
        }

        guard payload["kind"] as? String == "networkCapture",
              let url = payload["url"] as? String,
              url.contains("/api/card/getCardBalanceSummary"),
              let responseBody = payload["responseBody"] as? String,
              let data = responseBody.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["success"] as? Bool == true,
              let result = json["result"] as? [String: Any],
              let balances = result["balances"] as? [String: Any]
        else { return nil }
        let requestBody = (payload["requestBody"] as? String)?.data(using: .utf8)
        let request = requestBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        guard let balance = (balances["closingBalance"] as? NSNumber)?.doubleValue else {
            throw VaultError.webBridge("GiftCardMall returned a balance response without a balance value.")
        }
        guard balance >= 0 else { throw VaultError.webBridge("Invalid balance value.") }
        return GiftCardMallSummaryCapture(
            balance: balance,
            currencyCode: (balances["currencyCode"] as? String).flatMap { $0.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) == nil ? nil : $0 } ?? "USD",
            accessToken: json["access_token"] as? String ?? "",
            rmsSessionId: request?["rmsSessionId"] as? String ?? ""
        )
    }

    static func parseTransactions(_ body: Any, sourceURL: URL?, summary: GiftCardMallSummaryCapture) throws -> BalanceResult? {
        guard isAllowed(sourceURL),
              let payload = body as? [String: Any],
              payload["namespace"] as? String == handlerName,
              payload["parserVersion"] as? Int == parserVersion,
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
        if let date = ISO8601DateFormatter().date(from: trimmed) { return date }
        if let date = DateFormatter.giftCardISO8601Fractional.date(from: trimmed) { return date }
        return DateFormatter.giftCardTransactionDates.lazy.compactMap { $0.date(from: trimmed) }.first
    }
}

extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

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

    var strippingHTML: String {
        replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

@MainActor
struct AppEnvironment {
    var cardRepository: CardRepository
    var settingsRepository: SettingsRepository
    var biometricService: BiometricAuthenticating
    var notificationService: NotificationScheduling
    var scanner: CardScanning

    static func live() throws -> AppEnvironment {
        live(container: try ModelContainerFactory.makePersistent())
    }

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
                _ = try cardRepository.addCard(input)
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
    var settings: AppSettings
    var cards: [VaultCard] = []
    var routePath: [Route] = []
    var isLocked = false
    var isAuthenticating = false
    var alertMessage: String?
    private var hasStarted = false

    init(environment: AppEnvironment) {
        self.environment = environment
        settings = environment.settingsRepository.load()
    }

    var sortedCards: [VaultCard] {
        sortedActiveCards
    }

    var activeCards: [VaultCard] {
        cards.filter { !$0.isArchived }
    }

    var archivedCards: [VaultCard] {
        cards.filter(\.isArchived)
    }

    var sortedActiveCards: [VaultCard] {
        CardRules.sorted(activeCards, by: settings.sortOption)
    }

    var sortedArchivedCards: [VaultCard] {
        CardRules.sorted(archivedCards, by: settings.sortOption)
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        reloadCards()
        await unlockIfNeeded()
        Task { await environment.notificationService.requestAuthorization() }
    }

    func reloadCards() {
        do {
            cards = try environment.cardRepository.getCards()
        } catch {
            alertMessage = error.localizedDescription
        }
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

    func addCard(_ input: CardInput) throws -> String {
        guard CardRules.isValidCardNumber(input.cardNumber) else { throw VaultError.validation("Enter a valid Visa or Mastercard number.") }
        guard CardRules.validateExpiry(input.expiry) else { throw VaultError.validation("Use MM/YY.") }
        guard CardRules.validateCVV(input.cvv) else { throw VaultError.validation("Enter a valid CVV.") }
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

    var isShowingVault: Bool { routePath.isEmpty }

    var isShowingArchived: Bool {
        guard let first = routePath.first else { return false }
        if case .archived = first { return true }
        return false
    }

    var isShowingAddFlow: Bool {
        guard let first = routePath.first else { return false }
        switch first {
        case .add, .manualEntry, .scan: return true
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

    func revealCardNumber(id: String) async throws -> String {
        try await revealCardCredentials(id: id).cardNumber
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

    func applyForegroundRefresh(id: String, result: BalanceResult) {
        do {
            try environment.cardRepository.applyBalanceResult(cardID: id, result: result)
            reloadCards()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func scanText(_ text: String) -> ScanCandidate {
        environment.scanner.extractCandidates(from: text)
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
            return
        }
        guard !isAuthenticating else { return }
        isLocked = true
        isAuthenticating = true
        let authenticated = await environment.biometricService.authenticate(reason: "Unlock your card vault")
        isAuthenticating = false
        isLocked = !authenticated
    }

    private func saveSettings() {
        environment.settingsRepository.save(settings)
    }

    private func popDetailIfNeeded(for cardID: String) {
        guard case .detail(let currentID) = routePath.last, currentID == cardID else { return }
        routePath.removeLast()
    }

    private func isDetailPresentedFromArchivedList(for cardID: String) -> Bool {
        guard routePath.count >= 2,
              case .archived = routePath[routePath.count - 2],
              case .detail(let currentID) = routePath.last
        else { return false }
        return currentID == cardID
    }
}

enum Route: Hashable {
    case add
    case manualEntry(prefill: ScanCandidate?)
    case scan
    case detail(String)
    case giftCardMall(String)
    case archived
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
                            case .detail(let id): CardDetailView(cardID: id)
                            case .giftCardMall(let id): GiftCardMallRefreshView(cardID: id)
                            case .archived: ArchivedCardsView()
                            case .settings: SettingsView()
                            }
                        }
                }
                .vaultFloatingBar {
                    floatingBar
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
        .alert("VaultCard", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                model.lockForBackground()
            } else if phase == .active {
                Task { await model.unlockIfNeeded() }
            }
        }
    }

    private var floatingBar: some View {
        VaultFloatingBar(
            vaultSelected: model.isShowingVault || model.isShowingArchived,
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
    }

    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var selectedFilter = CardFilter.all
    @State private var isStackExpanded = false
    @State private var pendingDelete: VaultCard?
    @State private var isSelectingRecentCards = false
    @State private var selectedCardIDs = Set<String>()
    @State private var isBulkDeleteConfirmationPresented = false
    @State private var pendingSwipeArchiveEducation: VaultCard?
    @State private var latestSwipeArchivedCard: VaultCard?
    @State private var swipeArchiveDismissTask: Task<Void, Never>?
    @FocusState private var searchIsFocused: Bool

    private var visibleCards: [VaultCard] {
        let filtered: [VaultCard]
        switch selectedFilter {
        case .all:
            filtered = model.sortedCards
        case .upToDate:
            filtered = model.sortedCards.filter { $0.balanceFreshness() == .upToDate }
        case .needsRefresh:
            filtered = model.sortedCards.filter { $0.balanceFreshness() == .needsRefresh }
        }
        guard !searchText.isEmpty else { return filtered }
        return filtered.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.last4.contains(searchText)
                || $0.network.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            VaultBackground()
            List {
                searchRow
                filterRow

                if visibleCards.isEmpty {
                    emptyState
                } else {
                    cardCollection
                    recentCardRows
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
                    Button {
                        model.showArchivedCards()
                    } label: {
                        Image(systemName: "archivebox")
                    }
                    .accessibilityIdentifier("cards.archived")
                    .accessibilityLabel("Archived cards")
                    .accessibilityValue("\(model.archivedCards.count) cards")
                    .accessibilityHint("Open archived cards")
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton(.all, count: model.sortedCards.count)
                filterButton(.upToDate, count: model.sortedCards.filter { $0.balanceFreshness() == .upToDate }.count)
                filterButton(.needsRefresh, count: model.sortedCards.filter { $0.balanceFreshness() == .needsRefresh }.count)
            }
        }
        .cardListRowStyle(verticalPadding: 2)
    }

    private var emptyState: some View {
        let noCards = model.cards.isEmpty
        let allCardsArchived = !noCards && model.activeCards.isEmpty
        return VaultSurface {
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

    @ViewBuilder
    private var cardCollection: some View {
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
                VaultCardArtwork(card: card)
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
                    VaultCardArtwork(card: card)
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
                VaultCardStackView(cards: visibleCards)
            }
            .accessibilityIdentifier("cards.stack.expand")
            .accessibilityLabel("Expand \(visibleCards.count) cards")
            .accessibilityHint("Shows each card separately")
            .buttonStyle(.plain)
            .cardListRowStyle(verticalPadding: 2)
        }
    }

    @ViewBuilder
    private var recentCardRows: some View {
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
    @State private var pendingDelete: VaultCard?
    @State private var isSelectingCards = false
    @State private var selectedCardIDs = Set<String>()
    @State private var isBulkDeleteConfirmationPresented = false

    var body: some View {
        ZStack {
            VaultBackground()
            List {
                if model.sortedArchivedCards.isEmpty {
                    emptyState
                } else {
                    Section {
                        if isSelectingCards {
                            bulkActionControls
                                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }

                        ForEach(model.sortedArchivedCards) { card in
                            if isSelectingCards {
                                cardSelectionRow(for: card)
                            } else {
                                cardNavigationRow(for: card)
                            }
                        }
                    } header: {
                        selectionHeader
                    }
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
        .onDisappear {
            cancelSelection()
        }
    }

    private var selectionHeader: some View {
        HStack {
            Text(
                isSelectingCards
                    ? "\(selectedCardIDs.count) Selected"
                    : "\(model.sortedArchivedCards.count) archived card\(model.sortedArchivedCards.count == 1 ? "" : "s")"
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
                Text("No Archived Cards")
                    .font(.title2.bold())
                Text("Cards you archive will live here until you restore or delete them.")
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

    var body: some View {
        let stackedCards = Array(cards.prefix(4))
        let lastIndex = CGFloat(max(0, stackedCards.count - 1))
        let lastCardHeight = 176 * (1 - lastIndex * 0.032)
        let stackHeight = lastIndex * 28 + lastCardHeight + 12
        ZStack(alignment: .top) {
            ForEach(Array(stackedCards.enumerated()).reversed(), id: \.element.id) { index, card in
                VaultCardArtwork(card: card, emphasizesEdge: index > 0)
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
        HStack(spacing: 12) {
            VaultRowIcon(symbol: "creditcard.fill")
            VStack(alignment: .leading, spacing: 3) {
                Text(card.displayName).font(.subheadline.weight(.semibold))
                Text("•••• \(card.last4)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(card.balance.map { $0.formatted(.currency(code: "USD")) } ?? "—")
                    .font(.subheadline.weight(.semibold))
                Text(card.lastFetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    @State private var confirmDelete = false

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
        .onDisappear { clearReveal() }
    }

    private func detailContent(_ card: VaultCard) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VaultCardArtwork(
                card: card,
                revealedCredentials: revealedCredentials,
                usesDetailedMask: true
            )
            topActions(card)
            Text("Overview")
                .font(.headline)
            failureBanner(card)
            balancePanel(card)
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

    private func balancePanel(_ card: VaultCard) -> some View {
        VaultSurface {
            VStack(alignment: .leading, spacing: 5) {
                Text("BALANCE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(card.balance.map { $0.formatted(.currency(code: "USD")) } ?? "Unavailable")
                    .font(.title2.bold())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    model.routePath.append(.giftCardMall(cardID))
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
            VaultRowIcon(symbol: "bag.fill", color: VaultTheme.electricBlue)
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description).font(.subheadline.weight(.medium))
                Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(transaction.amount.formatted(.currency(code: "USD")))
                .font(.subheadline.weight(.semibold))
        }
        .padding(14)
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
                revealedCredentials = nil
            }
        }
    }

    private func clearReveal() {
        hideTask?.cancel()
        revealedCredentials = nil
    }

}

struct GiftCardMallRefreshView: View {
    @Environment(AppModel.self) private var model
    let cardID: String
    @State private var summary: GiftCardMallSummaryCapture?
    @State private var credentials: CardCredentials?
    @State private var isPageLoading = true
    @State private var isPreparingAutofill = false
    @State private var isBrowserReady = false
    @State private var preparationError: String?

    var body: some View {
        ZStack {
            VaultBackground()
            if isBrowserReady {
                GiftCardMallWebView(
                    credentials: credentials,
                    onLoadingChange: { isPageLoading = $0 }
                ) { body, url in
                    do {
                        if let captured = try GiftCardMallBridge.parseSummary(body, sourceURL: url) {
                            summary = captured
                            let existingTransactions = model.cards.first { $0.id == cardID }?.transactions ?? []
                            model.applyForegroundRefresh(
                                id: cardID,
                                result: BalanceResult(balance: captured.balance, transactions: existingTransactions, fetchedAt: Date())
                            )
                            return
                        }
                        if let summary, let result = try GiftCardMallBridge.parseTransactions(body, sourceURL: url, summary: summary) {
                            guard !result.transactions.isEmpty else { return }
                            model.applyForegroundRefresh(id: cardID, result: result)
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
                ProgressView("Loading GiftCardMall…")
                    .padding(16)
                    .vaultGlass(cornerRadius: 18)
            }
        }
        .navigationTitle("Check Balance")
        .task { await prepareBrowserAfterTransition() }
        .onDisappear { credentials = nil }
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
                    NotificationCenter.default.post(name: .giftCardMallReload, object: nil)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Reload Page")
                .disabled(!isBrowserReady)
            }
        }
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
    var onLoadingChange: (Bool) -> Void
    var onMessage: (Any, URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoadingChange: onLoadingChange, onMessage: onMessage)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.add(context.coordinator, name: GiftCardMallBridge.handlerName)
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
        webView.load(URLRequest(url: GiftCardMallBridge.siteURL))
        context.coordinator.installObservers()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onLoadingChange = onLoadingChange
        context.coordinator.onMessage = onMessage
        context.coordinator.updateCredentials(credentials)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: GiftCardMallBridge.handlerName)
        coordinator.removeObservers()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onLoadingChange: (Bool) -> Void
        var onMessage: (Any, URL?) -> Void
        weak var webView: WKWebView?
        private var tokens: [NSObjectProtocol] = []
        private var credentials: CardCredentials?
        private var lastAppliedCredentials: CardCredentials?
        private var pageReady = false

        init(onLoadingChange: @escaping (Bool) -> Void, onMessage: @escaping (Any, URL?) -> Void) {
            self.onLoadingChange = onLoadingChange
            self.onMessage = onMessage
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            pageReady = false
            lastAppliedCredentials = nil
            onLoadingChange(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard GiftCardMallBridge.isAllowed(webView.url) else { return }
            webView.evaluateJavaScript(GiftCardMallBridge.installScript()) { [weak self] _, _ in
                guard let self else { return }
                self.pageReady = true
                self.onLoadingChange(false)
                self.applyAutofillIfReady()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onLoadingChange(false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onLoadingChange(false)
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
                return
            }
            decisionHandler(.allow)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == GiftCardMallBridge.handlerName else { return }
            onMessage(message.body, webView?.url)
        }

        func installObservers() {
            tokens.append(NotificationCenter.default.addObserver(forName: .giftCardMallAutofill, object: nil, queue: .main) { [weak self] notification in
                guard let credentials = notification.object as? CardCredentials else { return }
                self?.lastAppliedCredentials = nil
                self?.updateCredentials(credentials)
            })
            tokens.append(NotificationCenter.default.addObserver(forName: .giftCardMallReload, object: nil, queue: .main) { [weak self] _ in
                self?.webView?.reload()
            })
        }

        func removeObservers() {
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
        )
    ]
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
                    Text("Choose the icon VaultCard uses on your Home Screen. Additional installed designs will appear here as they’re added to the app.")
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

                    if VaultAppIcons.choices.count == 1 {
                        Label("More icon choices can be added without changing this screen.", systemImage: "square.grid.2x2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

    var body: some View {
        @Bindable var model = model
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
                Section("Security") {
                    Label("Face ID", systemImage: "faceid")
                    Toggle(isOn: Binding(get: { model.settings.appLockEnabled }, set: { value in model.updateSettings { $0.appLockEnabled = value } })) {
                        Label("App Lock", systemImage: "lock.fill")
                    }
                    Toggle(isOn: Binding(get: { model.settings.analyticsEnabled }, set: { value in model.updateSettings { $0.analyticsEnabled = value } })) {
                        Label("Private Analytics", systemImage: "chart.bar.fill")
                    }
                }
                Section("Alerts") {
                    Toggle(isOn: Binding(get: { model.settings.notificationPreferences.expiryWarning }, set: { value in model.updateSettings { $0.notificationPreferences.expiryWarning = value } })) {
                        Label("Expiry warnings", systemImage: "calendar.badge.exclamationmark")
                    }
                    Toggle(isOn: Binding(get: { model.settings.notificationPreferences.lowBalance }, set: { value in model.updateSettings { $0.notificationPreferences.lowBalance = value } })) {
                        Label("Low balance alerts", systemImage: "exclamationmark.circle.fill")
                    }
                    Toggle(isOn: Binding(get: { model.settings.notificationPreferences.balanceUpdated }, set: { value in model.updateSettings { $0.notificationPreferences.balanceUpdated = value } })) {
                        Label("Balance updated", systemImage: "arrow.clockwise.circle.fill")
                    }
                    Toggle(isOn: Binding(get: { model.settings.notificationPreferences.refreshFailed }, set: { value in model.updateSettings { $0.notificationPreferences.refreshFailed = value } })) {
                        Label("Refresh failed", systemImage: "wifi.exclamationmark")
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
                            Image("VaultCardIconPreview")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 42, height: 42)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("App Icon")
                                Text("Card Stack")
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
            .scrollContentBackground(.hidden)
            .vaultFloatingBarScrollClearance()
        }
        .navigationTitle("Settings")
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
