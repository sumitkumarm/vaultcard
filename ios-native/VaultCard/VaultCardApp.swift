import AVFoundation
import BackgroundTasks
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
}

struct VaultCard: Identifiable, Equatable {
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

    var displayName: String {
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed! : "**** \(last4)"
    }

    var isRefreshCoolingDown: Bool {
        guard let refreshBlockedUntil else { return false }
        return refreshBlockedUntil > Date()
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
    var expiryYear: String { "20" + (expiry.split(separator: "/").last.map { String($0).leftPadded(to: 2) } ?? "00") }
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

    static func mask(last4: String) -> String { "**** **** **** \(last4)" }
    static func digitsOnly(_ value: String) -> String { value.filter(\.isNumber) }

    static func sorted(_ cards: [VaultCard], by option: CardSortOption) -> [VaultCard] {
        switch option {
        case .dateAddedNewest:
            return cards.sorted { $0.addedAt > $1.addedAt }
        case .balanceLowToHigh:
            return cards.sorted { ($0.balance ?? 0) < ($1.balance ?? 0) }
        case .balanceHighToLow:
            return cards.sorted { ($0.balance ?? 0) > ($1.balance ?? 0) }
        case .expirySoonest:
            return cards.sorted { $0.expiry < $1.expiry }
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

enum VaultCardSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum ModelContainerFactory {
    static func makePersistent() throws -> ModelContainer {
        try ModelContainer(
            for: Schema([SchemaV1.CardMetadataRecord.self, SchemaV1.TransactionRecord.self]),
            migrationPlan: VaultCardSchemaMigrationPlan.self
        )
    }

    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Schema([SchemaV1.CardMetadataRecord.self, SchemaV1.TransactionRecord.self]),
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

protocol CardScanning {
    func extractCandidates(from image: CGImage) async throws -> ScanCandidate
    func extractCandidates(from text: String) -> ScanCandidate
}

protocol NotificationScheduling {
    func requestAuthorization() async
    func syncForCard(_ card: VaultCard, preferences: NotificationPreferences) async
}

protocol BackgroundRefreshRegistering {
    func register()
    func scheduleStaleCheck()
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
        let records = try context.fetch(FetchDescriptor<SchemaV1.CardMetadataRecord>())
        return try records.map { try makeCard(from: $0) }
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
            context.insert(SchemaV1.CardMetadataRecord(card: card))
            try beforeMetadataSave?()
            try context.save()
            return cardID
        } catch {
            try? credentialStore.delete(cardID: cardID)
            throw error
        }
    }

    func deleteCard(id: String) throws {
        try credentialStore.delete(cardID: id)
        guard let record = try findRecord(id: id) else { return }
        context.delete(record)
        try deleteTransactions(cardID: id)
        try context.save()
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
            context.insert(SchemaV1.TransactionRecord(cardId: cardID, transaction: transaction))
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

    private func findRecord(id: String) throws -> SchemaV1.CardMetadataRecord? {
        let descriptor = FetchDescriptor<SchemaV1.CardMetadataRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    private func transactions(cardID: String) throws -> [CardTransaction] {
        let descriptor = FetchDescriptor<SchemaV1.TransactionRecord>(
            predicate: #Predicate { $0.cardId == cardID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor).map {
            CardTransaction(id: $0.id, date: $0.date, description: $0.transactionDescription, amount: $0.amount)
        }
    }

    private func deleteTransactions(cardID: String) throws {
        let descriptor = FetchDescriptor<SchemaV1.TransactionRecord>(
            predicate: #Predicate { $0.cardId == cardID }
        )
        for record in try context.fetch(descriptor) {
            context.delete(record)
        }
    }

    private func makeCard(from record: SchemaV1.CardMetadataRecord) throws -> VaultCard {
        VaultCard(
            id: record.id,
            nickname: record.nickname,
            network: CardNetwork(rawValue: record.networkRaw) ?? .unknown,
            last4: record.last4,
            expiry: record.expiry,
            balance: record.balance,
            transactions: try transactions(cardID: record.id),
            lastFetchedAt: record.lastFetchedAt,
            fetchFailureCount: record.fetchFailureCount,
            addedAt: record.addedAt,
            refreshBlockedUntil: record.refreshBlockedUntil,
            credentialVersion: record.credentialVersion
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
        guard preferences.privacyPreservingContent else { return }
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

final class BackgroundRefreshService: BackgroundRefreshRegistering {
    static let taskIdentifier = "com.vaultcard.ios.stale-check"
    private static var didRegister = false

    func register() {
        guard !Self.didRegister else { return }
        Self.didRegister = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            task.expirationHandler = { task.setTaskCompleted(success: false) }
            task.setTaskCompleted(success: true)
        }
    }

    func scheduleStaleCheck() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(24 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

struct NoopBackgroundRefreshService: BackgroundRefreshRegistering {
    func register() {}
    func scheduleStaleCheck() {}
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
              field.value = value;
              field.dispatchEvent(new Event('input', { bubbles: true }));
              field.dispatchEvent(new Event('change', { bubbles: true }));
              return true;
            }
            return false;
          };
          setValue(['input[name="cardNumber"]','input[id*="cardNumber"]','input[autocomplete="cc-number"]','input[inputmode="numeric"]'], \(number));
          setValue(['input[name="expirationMonth"]','input[id*="expirationMonth"]','select[name="expirationMonth"]','input[name="expMonth"]'], \(month));
          setValue(['input[name="expirationYear"]','input[id*="expirationYear"]','select[name="expirationYear"]','input[name="expYear"]'], \(year));
          setValue(['input[name="securityCode"]','input[id*="securityCode"]','input[name="cvv"]','input[id*="cvv"]','input[autocomplete="cc-csc"]'], \(cvv));
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
              payload["kind"] as? String == "networkCapture",
              let pageHost = payload["pageHost"] as? String,
              allowedHosts.contains(pageHost.lowercased()),
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
        let balance = (balances["closingBalance"] as? NSNumber)?.doubleValue ?? 0
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
        let transactions = (result["transactions"] as? [[String: Any]] ?? []).compactMap { item -> CardTransaction? in
            let description = (item["merchantDescription"] as? String) ?? (item["description"] as? String) ?? "GiftCardMall transaction"
            guard let amount = (item["amount"] as? NSNumber)?.doubleValue,
                  let dateString = item["transactionDate"] as? String,
                  let date = ISO8601DateFormatter().date(from: dateString) ?? DateFormatter.yyyyMMdd.date(from: dateString)
            else { return nil }
            return CardTransaction(date: date, description: description.trimmingCharacters(in: .whitespacesAndNewlines), amount: amount)
        }
        return BalanceResult(balance: summary.balance, transactions: transactions, fetchedAt: Date())
    }
}

extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

final class VisionCardScanner: CardScanning {
    func extractCandidates(from image: CGImage) async throws -> ScanCandidate {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let text = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: self.extractCandidates(from: text))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func extractCandidates(from text: String) -> ScanCandidate {
        let card = text.firstMatch(#"(?:\d[\s-]?){16}"#).map { CardRules.digitsOnly($0) }
        let labeledExpiry = text.firstMatch(#"(?i)(?:exp|expiry)[:\s]*((0[1-9]|1[0-2])\/([0-9]{2}))"#, group: 1)
        let expiry = labeledExpiry ?? text.firstMatch(#"\b(0[1-9]|1[0-2])\/([0-9]{2})\b"#)
        let labeledCVV = text.firstMatch(#"(?i)cvv[:\s]*([0-9]{3,4})"#, group: 1)
        let cvv = labeledCVV ?? text.allMatches(#"\b\d{3,4}\b"#).last
        return ScanCandidate(
            cardNumber: card,
            expiry: expiry,
            cvv: cvv,
            recognizedText: text,
            network: CardRules.inferNetwork(card ?? ""),
            confidence: card != nil && expiry != nil ? 0.8 : 0.45
        )
    }
}

struct StaticCardScanner: CardScanning {
    func extractCandidates(from image: CGImage) async throws -> ScanCandidate {
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
    var balanceService: BalanceRefreshing
    var scanner: CardScanning
    var backgroundRefresh: BackgroundRefreshRegistering

    static func live() throws -> AppEnvironment {
        let container = try ModelContainerFactory.makePersistent()
        let context = ModelContext(container)
        let notificationService = NotificationService()
        let cardRepository = SwiftDataCardRepository(context: context, credentialStore: KeychainCredentialStore())
        return AppEnvironment(
            cardRepository: cardRepository,
            settingsRepository: UserDefaultsSettingsRepository(),
            biometricService: LocalAuthenticationService(),
            notificationService: notificationService,
            balanceService: BalanceService(repository: cardRepository, notifications: notificationService),
            scanner: VisionCardScanner(),
            backgroundRefresh: BackgroundRefreshService()
        )
    }

    static func uiTesting() throws -> AppEnvironment {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let notificationService = NoopNotificationService()
        let cardRepository = SwiftDataCardRepository(context: context, credentialStore: InMemoryCredentialStore())
        return AppEnvironment(
            cardRepository: cardRepository,
            settingsRepository: InMemorySettingsRepository(),
            biometricService: AlwaysAllowAuthenticationService(),
            notificationService: notificationService,
            balanceService: BalanceService(repository: cardRepository, notifications: notificationService),
            scanner: StaticCardScanner(),
            backgroundRefresh: NoopBackgroundRefreshService()
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

    init(environment: AppEnvironment) {
        self.environment = environment
        settings = environment.settingsRepository.load()
    }

    var sortedCards: [VaultCard] {
        CardRules.sorted(cards, by: settings.sortOption)
    }

    func start() async {
        environment.backgroundRefresh.scheduleStaleCheck()
        await environment.notificationService.requestAuthorization()
        reloadCards()
        await unlockIfNeeded()
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

    func addCard(_ input: CardInput) throws -> String {
        guard CardRules.isValidCardNumber(input.cardNumber) else { throw VaultError.validation("Enter a valid Visa or Mastercard number.") }
        guard CardRules.validateExpiry(input.expiry) else { throw VaultError.validation("Use MM/YY.") }
        guard CardRules.validateCVV(input.cvv) else { throw VaultError.validation("Enter a valid CVV.") }
        let id = try environment.cardRepository.addCard(input)
        reloadCards()
        return id
    }

    func deleteCard(id: String) throws {
        try environment.cardRepository.deleteCard(id: id)
        routePath.removeAll()
        reloadCards()
    }

    func revealCardNumber(id: String) async throws -> String {
        isAuthenticating = true
        defer { isAuthenticating = false }
        guard await environment.biometricService.authenticate(reason: "Reveal sensitive card details") else {
            throw VaultError.validation("Authentication was cancelled.")
        }
        return try environment.cardRepository.getCredentials(cardID: id).cardNumber
    }

    func credentialsForAutofill(id: String) async throws -> CardCredentials {
        guard await environment.biometricService.authenticate(reason: "Autofill card details") else {
            throw VaultError.validation("Authentication was cancelled.")
        }
        return try environment.cardRepository.getCredentials(cardID: id)
    }

    func refreshCard(id: String) async -> RefreshOutcome {
        let outcome = await environment.balanceService.refreshCard(id, ignoreCooldown: false, preferences: settings.notificationPreferences)
        reloadCards()
        return outcome
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

    func scanImage(_ image: CGImage) async throws -> ScanCandidate {
        try await environment.scanner.extractCandidates(from: image)
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
        isLocked = true
        isAuthenticating = true
        let authenticated = await environment.biometricService.authenticate(reason: "Unlock your card vault")
        isAuthenticating = false
        isLocked = !authenticated
    }

    private func saveSettings() {
        environment.settingsRepository.save(settings)
    }
}

enum Route: Hashable {
    case add
    case manualEntry(prefill: ScanCandidate?)
    case scan
    case detail(String)
    case giftCardMall(String)
    case settings
}

@main
struct VaultCardApp: App {
    init() {
        BackgroundRefreshService().register()
    }

    var body: some Scene {
        WindowGroup {
            BootstrapView()
        }
    }
}

struct BootstrapView: View {
    @State private var model: AppModel?
    @State private var startupError: String?

    init() {
        do {
            let environment = try ProcessInfo.processInfo.arguments.contains("--ui-testing")
                ? AppEnvironment.uiTesting()
                : AppEnvironment.live()
            _model = State(initialValue: AppModel(environment: environment))
            _startupError = State(initialValue: nil)
        } catch {
            _model = State(initialValue: nil)
            _startupError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some View {
        if let model {
            RootView()
                .environment(model)
        } else {
            ContentUnavailableView(
                "VaultCard could not start",
                systemImage: "exclamationmark.triangle",
                description: Text(startupError ?? "The local secure store could not be initialized.")
            )
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        ZStack {
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
                            case .settings: SettingsView()
                            }
                        }
                }
            } else {
                OnboardingView()
            }
            if model.isLocked {
                LockOverlayView()
            }
        }
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
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var index = 0
    private let pages = [
        ("Track every gift card in one place", "VaultCard keeps prepaid Visa and Mastercard gift cards organized on-device only.", "lock.rectangle.stack"),
        ("Balances stay easy to check", "Refresh balances and recent transactions without juggling receipts.", "arrow.clockwise.circle"),
        ("Sensitive details stay protected", "Card credentials remain encrypted on-device and require authentication before reveal.", "faceid")
    ]

    var body: some View {
        VStack {
            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.offset) { offset, page in
                    VStack(spacing: 20) {
                        Image(systemName: page.2).font(.system(size: 76)).foregroundStyle(.tint)
                        Text(page.0).font(.largeTitle.bold()).multilineTextAlignment(.center)
                        Text(page.1).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            Button(index == pages.count - 1 ? "Get Started" : "Next") {
                if index == pages.count - 1 {
                    model.completeOnboarding()
                } else {
                    withAnimation { index += 1 }
                }
            }
            .accessibilityIdentifier("onboarding.primary")
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
    }
}

struct CardListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if model.sortedCards.isEmpty {
                ContentUnavailableView("No cards yet", systemImage: "creditcard", description: Text("Add your first prepaid gift card to start tracking balances and expiry dates."))
                Button("Add Your First Card") { model.routePath.append(.add) }
                    .accessibilityIdentifier("cards.empty.add")
            } else {
                Section {
                    ForEach(model.sortedCards) { card in
                        Button { model.routePath.append(.detail(card.id)) } label: {
                            CardRow(card: card)
                        }
                        .accessibilityIdentifier("card.row.\(card.last4)")
                    }
                } header: {
                    Text("Your Cards")
                }
            }
        }
        .refreshable {
            for card in model.sortedCards {
                _ = await model.refreshCard(id: card.id)
            }
        }
        .navigationTitle("VaultCard")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    ForEach(CardSortOption.allCases) { option in
                        Button(option.label) { model.setSort(option) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.routePath.append(.settings) } label: { Image(systemName: "gearshape") }
            }
            ToolbarItem(placement: .bottomBar) {
                Button { model.routePath.append(.add) } label: { Label("Add Card", systemImage: "plus") }
                    .accessibilityIdentifier("cards.add")
            }
        }
    }
}

struct CardRow: View {
    var card: VaultCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.displayName).font(.headline)
                Spacer()
                Text(card.network.displayName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(card.balance.map { $0.formatted(.currency(code: "USD")) } ?? "Balance unavailable")
                .foregroundStyle(.primary)
            Text("Expires \(card.expiry)").foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

struct AddCardChoiceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                Button { model.routePath.append(.scan) } label: {
                    Label("Scan Card", systemImage: "doc.viewfinder")
                }
                .accessibilityIdentifier("add.scan")
                Button { model.routePath.append(.manualEntry(prefill: nil)) } label: {
                    Label("Enter Manually", systemImage: "keyboard")
                }
                .accessibilityIdentifier("add.manual")
            } header: {
                Text("Choose how to add your card")
            } footer: {
                Text("Scan can prefill fields, but manual review is required before saving.")
            }
        }
        .navigationTitle("Add Card")
    }
}

struct ManualCardEntryView: View {
    @Environment(AppModel.self) private var model
    @State private var cardNumber: String
    @State private var expiry: String
    @State private var cvv: String
    @State private var nickname = ""
    @State private var errorMessage: String?

    init(prefill: ScanCandidate?) {
        _cardNumber = State(initialValue: prefill?.cardNumber ?? "")
        _expiry = State(initialValue: CardRules.formatExpiryInput(prefill?.expiry ?? ""))
        _cvv = State(initialValue: prefill?.cvv ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField("Card Number", text: $cardNumber)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("manual.cardNumber")
                Text(CardRules.inferNetwork(cardNumber).displayName).foregroundStyle(.secondary)
                TextField("Expiry (MM/YY)", text: Binding(get: { expiry }, set: { expiry = CardRules.formatExpiryInput($0) }))
                    .keyboardType(.numbersAndPunctuation)
                    .accessibilityIdentifier("manual.expiry")
                SecureField("CVV", text: $cvv)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("manual.cvv")
                TextField("Nickname (optional)", text: $nickname)
                    .accessibilityIdentifier("manual.nickname")
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            Button("Save Card") {
                do {
                    let id = try model.addCard(CardInput(cardNumber: cardNumber, expiry: expiry, cvv: cvv, nickname: nickname))
                    model.routePath = [.detail(id)]
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .accessibilityIdentifier("manual.save")
        }
        .navigationTitle("Card Details")
    }
}

struct ScanCardView: View {
    @Environment(AppModel.self) private var model
    @State private var fallbackText = ""
    @State private var lastCandidate: ScanCandidate?
    @State private var showFallback = false

    var body: some View {
        List {
            Section {
                CameraCaptureView { image in
                    Task {
                        do {
                            let candidate = try await model.scanImage(image)
                            handle(candidate)
                        } catch {
                            showFallback = true
                            model.alertMessage = "Scan failed. Use text fallback or enter manually."
                        }
                    }
                }
                .frame(minHeight: 260)
            } header: {
                Text("Scan with your camera")
            } footer: {
                Text("Recognition runs on device. Review the prefilled form before saving.")
            }
            if let lastCandidate {
                Section("Last scan") {
                    Text("Card: \(lastCandidate.cardNumber ?? "Not found")")
                    Text("Expiry: \(lastCandidate.expiry ?? "Not found")")
                    Text("CVV: \(lastCandidate.cvv ?? "Not found")")
                    Text("Confidence: \((lastCandidate.confidence * 100).rounded().formatted())%")
                }
            }
            Section("Fallback OCR text") {
                Toggle("Use text fallback", isOn: $showFallback)
                if showFallback {
                    TextEditor(text: $fallbackText).frame(minHeight: 140)
                    Button("Use Text Result") {
                        handle(model.scanText(fallbackText))
                    }
                    .accessibilityIdentifier("scan.useText")
                }
            }
        }
        .navigationTitle("Scan Card")
    }

    private func handle(_ candidate: ScanCandidate) {
        lastCandidate = candidate
        fallbackText = candidate.recognizedText
        showFallback = true
        if candidate.hasCandidateData {
            model.routePath.append(.manualEntry(prefill: candidate))
        }
    }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    var onImage: (CGImage) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.onImage = onImage
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

final class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onImage: ((CGImage) -> Void)?
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        configure()
    }

    private func configure() {
        guard AVCaptureDevice.authorizationStatus(for: .video) != .denied,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(output)
        else {
            showFallbackMessage()
            return
        }
        session.addInput(input)
        session.addOutput(output)
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        let button = UIButton(type: .system)
        button.setTitle("Capture Card", for: .normal)
        button.addTarget(self, action: #selector(capture), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
        Task.detached { [session] in session.startRunning() }
    }

    @objc private func capture() {
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data)?.cgImage
        else { return }
        onImage?(image)
    }

    private func showFallbackMessage() {
        let label = UILabel()
        label.text = "Camera unavailable. Use text fallback or manual entry."
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

struct CardDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    let cardID: String
    @State private var revealedNumber: String?
    @State private var hideTask: Task<Void, Never>?
    @State private var confirmDelete = false

    var card: VaultCard? { model.cards.first { $0.id == cardID } }

    var body: some View {
        List {
            if let card {
                if card.fetchFailureCount > 0 {
                    Section {
                        Text(card.lastFetchedAt == nil ? "Balance refresh has failed \(card.fetchFailureCount) time(s). The card has not been synced yet." : "Balance data may be stale. Refresh has failed \(card.fetchFailureCount) time(s) since the last successful sync.")
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    Text(card.network.displayName)
                    Text(card.balance.map { $0.formatted(.currency(code: "USD")) } ?? "Balance unavailable").font(.title)
                    Text("Expires \(card.expiry)")
                    Text("Last updated \(card.lastFetchedAt?.formatted() ?? "Never")")
                    Button("Refresh In GiftCardMall") { model.routePath.append(.giftCardMall(cardID)) }
                }
                Section("Sensitive Details") {
                    HStack {
                        Text(revealedNumber ?? CardRules.mask(last4: card.last4))
                        Spacer()
                        Button(model.isAuthenticating ? "Checking..." : "Reveal") {
                            Task {
                                do {
                                    revealedNumber = try await model.revealCardNumber(id: cardID)
                                    scheduleHide()
                                } catch {
                                    model.alertMessage = error.localizedDescription
                                }
                            }
                        }
                        .accessibilityIdentifier("detail.reveal")
                    }
                }
                Section("Transactions") {
                    if card.transactions.isEmpty {
                        Text("No transaction history available.")
                    } else {
                        ForEach(card.transactions) { tx in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(tx.description)
                                    Text(tx.date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(tx.amount.formatted(.currency(code: "USD")))
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Card unavailable", systemImage: "creditcard.trianglebadge.exclamationmark", description: Text("This card may have been deleted."))
            }
        }
        .navigationTitle(card?.displayName ?? "Card")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { Task { model.alertMessage = describe(await model.refreshCard(id: cardID)) } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityIdentifier("detail.refresh")
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

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(30))
            if !Task.isCancelled {
                revealedNumber = nil
            }
        }
    }

    private func clearReveal() {
        hideTask?.cancel()
        revealedNumber = nil
    }

    private func describe(_ outcome: RefreshOutcome) -> String {
        switch outcome {
        case .success:
            return "Balance refreshed."
        case .failure(let failure):
            return failure.message
        case .cooldown(let date):
            return "Refresh available again at \(date.formatted())."
        }
    }
}

struct GiftCardMallRefreshView: View {
    @Environment(AppModel.self) private var model
    let cardID: String
    @State private var summary: GiftCardMallSummaryCapture?
    @State private var status = "Clear any challenge if prompted, then use secure autofill and submit inside GiftCardMall."

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(status)
                HStack {
                    Button("Secure Autofill") {
                        Task {
                            do {
                                let credentials = try await model.credentialsForAutofill(id: cardID)
                                NotificationCenter.default.post(name: .giftCardMallAutofill, object: credentials)
                                status = "Best-effort autofill sent. Review the fields and submit inside GiftCardMall."
                            } catch {
                                status = error.localizedDescription
                            }
                        }
                    }
                    Button("Reload Page") {
                        NotificationCenter.default.post(name: .giftCardMallReload, object: nil)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)
            GiftCardMallWebView { body, url in
                do {
                    if let captured = try GiftCardMallBridge.parseSummary(body, sourceURL: url) {
                        summary = captured
                        status = "GiftCardMall session connected. Balance summary captured."
                        return
                    }
                    if let summary, let result = try GiftCardMallBridge.parseTransactions(body, sourceURL: url, summary: summary) {
                        model.applyForegroundRefresh(id: cardID, result: result)
                        status = "VaultCard synced the latest balance and transactions from the active GiftCardMall session."
                    }
                } catch {
                    status = error.localizedDescription
                }
            }
        }
        .navigationTitle("GiftCardMall Refresh")
    }
}

extension Notification.Name {
    static let giftCardMallAutofill = Notification.Name("giftCardMallAutofill")
    static let giftCardMallReload = Notification.Name("giftCardMallReload")
}

struct GiftCardMallWebView: UIViewRepresentable {
    var onMessage: (Any, URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMessage: onMessage)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: GiftCardMallBridge.handlerName)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.load(URLRequest(url: GiftCardMallBridge.siteURL))
        context.coordinator.installObservers()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: GiftCardMallBridge.handlerName)
        coordinator.removeObservers()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onMessage: (Any, URL?) -> Void
        weak var webView: WKWebView?
        private var tokens: [NSObjectProtocol] = []

        init(onMessage: @escaping (Any, URL?) -> Void) {
            self.onMessage = onMessage
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard GiftCardMallBridge.isAllowed(webView.url) else { return }
            webView.evaluateJavaScript(GiftCardMallBridge.installScript())
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(GiftCardMallBridge.isAllowed(navigationAction.request.url) ? .allow : .cancel)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == GiftCardMallBridge.handlerName else { return }
            onMessage(message.body, webView?.url)
        }

        func installObservers() {
            tokens.append(NotificationCenter.default.addObserver(forName: .giftCardMallAutofill, object: nil, queue: .main) { [weak self] notification in
                guard let credentials = notification.object as? CardCredentials, let webView = self?.webView, GiftCardMallBridge.isAllowed(webView.url) else { return }
                webView.evaluateJavaScript(GiftCardMallBridge.autofillScript(credentials: credentials))
            })
            tokens.append(NotificationCenter.default.addObserver(forName: .giftCardMallReload, object: nil, queue: .main) { [weak self] _ in
                self?.webView?.reload()
            })
        }

        func removeObservers() {
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens.removeAll()
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("App Lock", isOn: Binding(get: { model.settings.appLockEnabled }, set: { value in model.updateSettings { $0.appLockEnabled = value } }))
                Toggle("Analytics", isOn: Binding(get: { model.settings.analyticsEnabled }, set: { value in model.updateSettings { $0.analyticsEnabled = value } }))
            }
            Section("Notifications") {
                Toggle("Expiry warnings", isOn: Binding(get: { model.settings.notificationPreferences.expiryWarning }, set: { value in model.updateSettings { $0.notificationPreferences.expiryWarning = value } }))
                Toggle("Low balance alerts", isOn: Binding(get: { model.settings.notificationPreferences.lowBalance }, set: { value in model.updateSettings { $0.notificationPreferences.lowBalance = value } }))
                Toggle("Balance updated", isOn: Binding(get: { model.settings.notificationPreferences.balanceUpdated }, set: { value in model.updateSettings { $0.notificationPreferences.balanceUpdated = value } }))
                Toggle("Refresh failed", isOn: Binding(get: { model.settings.notificationPreferences.refreshFailed }, set: { value in model.updateSettings { $0.notificationPreferences.refreshFailed = value } }))
                Toggle("Privacy-preserving content", isOn: Binding(get: { model.settings.notificationPreferences.privacyPreservingContent }, set: { value in model.updateSettings { $0.notificationPreferences.privacyPreservingContent = value } }))
            }
        }
        .navigationTitle("Settings")
    }
}

struct LockOverlayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock").font(.system(size: 56))
            Text("VaultCard is locked").font(.title2.bold())
            Text("Authenticate with biometrics or device passcode to continue.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(model.isAuthenticating ? "Unlocking..." : "Unlock") {
                Task { await model.unlockIfNeeded() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isAuthenticating)
        }
        .padding(28)
        .frame(maxWidth: 340)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
