import Foundation
import UserNotifications

struct CardUseReminder: Codable, Equatable {
    var cardID: String
    var fireDate: Date
    var balance: Double
    var lastCheckedAt: Date
}

extension Notification.Name {
    static let vaultcardOpenReminderCard = Notification.Name("vaultcardOpenReminderCard")
}

struct PlannedCardNotification: Equatable {
    enum Kind: Equatable {
        case useReminder
        case expiry(daysBeforeEnd: Int)
    }

    var identifier: String
    var cardID: String
    var fireDate: Date
    var kind: Kind
}

/// Pure scheduling and reconciliation rules, kept separate from UserNotifications so
/// calendar boundaries and stale reminder handling can be checked without OS permission.
enum CardNotificationPlanner {
    static let useReminderThreshold = 10.0
    static let pendingRequestLimit = 64

    static func expiryNotifications(
        for cards: [VaultCard],
        preferences: NotificationPreferences,
        now: Date,
        calendar: Calendar
    ) -> [PlannedCardNotification] {
        guard preferences.expiryWarning else { return [] }
        let days = preferences.expiryWarningDays
        return cards.compactMap { card in
            guard !card.isArchived,
                  let balance = card.balance,
                  balance.isFinite,
                  balance > 0,
                  let date = expiryReminderDate(expiry: card.expiry, daysBeforeEnd: days, calendar: calendar),
                  date > now else { return nil }
            return PlannedCardNotification(
                identifier: expiryIdentifier(cardID: card.id, days: days),
                cardID: card.id,
                fireDate: date,
                kind: .expiry(daysBeforeEnd: days)
            )
        }
    }

    static func pendingNotifications(
        cards: [VaultCard],
        preferences: NotificationPreferences,
        reminders: [String: CardUseReminder],
        now: Date,
        calendar: Calendar
    ) -> [PlannedCardNotification] {
        let cardsByID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let usePlans = reminders.values.compactMap { reminder -> PlannedCardNotification? in
            guard reminder.fireDate > now,
                  let card = cardsByID[reminder.cardID],
                  isEligibleForUseReminder(card),
                  card.lastFetchedAt == reminder.lastCheckedAt else { return nil }
            return PlannedCardNotification(
                identifier: useReminderIdentifier(cardID: reminder.cardID),
                cardID: reminder.cardID,
                fireDate: reminder.fireDate,
                kind: .useReminder
            )
        }
        let expiryPlans = expiryNotifications(for: cards, preferences: preferences, now: now, calendar: calendar)
        let orderedUsePlans = usePlans.sorted {
            if $0.fireDate != $1.fireDate { return $0.fireDate < $1.fireDate }
            return $0.cardID < $1.cardID
        }
        let orderedExpiryPlans = expiryPlans.sorted {
            if $0.fireDate != $1.fireDate { return $0.fireDate < $1.fireDate }
            return $0.cardID < $1.cardID
        }
        return Array((orderedUsePlans + orderedExpiryPlans).prefix(pendingRequestLimit))
    }

    static func reconciledUseReminders(
        _ reminders: [String: CardUseReminder],
        with cards: [VaultCard],
        now: Date
    ) -> [String: CardUseReminder] {
        let cardsByID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [String: CardUseReminder] = [:]
        for (cardID, reminder) in reminders {
            guard let card = cardsByID[cardID],
                  let updated = reconciledUseReminder(reminder, with: card, now: now) else { continue }
            result[cardID] = updated
        }
        return result
    }

    static func reconciledUseReminder(
        _ reminder: CardUseReminder,
        with card: VaultCard,
        now: Date
    ) -> CardUseReminder? {
        _ = now
        guard isEligibleForUseReminder(card),
              let balance = card.balance,
              let lastCheckedAt = card.lastFetchedAt else { return nil }
        // Keep the chosen date and refresh the snapshot while the balance is still
        // eligible. A fired plan remains visible in the app until dismissed/re-armed.
        return CardUseReminder(cardID: card.id, fireDate: reminder.fireDate, balance: balance, lastCheckedAt: lastCheckedAt)
    }

    static func makeUseReminder(
        for card: VaultCard,
        at date: Date,
        now: Date
    ) throws -> CardUseReminder {
        guard date > now else {
            throw VaultError.validation("Choose a reminder time in the future.")
        }
        guard isEligibleForUseReminder(card),
              let lastCheckedAt = card.lastFetchedAt,
              let balance = card.balance else {
            throw VaultError.validation("A use reminder needs an active card with a saved balance greater than $0 and below $10.")
        }
        return CardUseReminder(cardID: card.id, fireDate: date, balance: balance, lastCheckedAt: lastCheckedAt)
    }

    static func isEligibleForUseReminder(_ card: VaultCard) -> Bool {
        guard !card.isArchived,
              card.lastFetchedAt != nil,
              let balance = card.balance,
              balance.isFinite else { return false }
        return balance > 0 && balance < useReminderThreshold
    }

    static func expiryReminderDate(expiry: String, daysBeforeEnd days: Int, calendar: Calendar) -> Date? {
        let parts = expiry.split(separator: "/")
        guard parts.count == 2,
              let month = Int(parts[0]), (1...12).contains(month),
              let shortYear = Int(parts[1]), (0...99).contains(shortYear),
              days >= 0 else { return nil }

        let year = 2000 + shortYear
        var firstOfMonthComponents = DateComponents()
        firstOfMonthComponents.year = year
        firstOfMonthComponents.month = month
        firstOfMonthComponents.day = 1
        guard let firstOfMonth = calendar.date(from: firstOfMonthComponents),
              let firstOfNextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfMonth),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: firstOfNextMonth),
              let targetDay = calendar.date(byAdding: .day, value: -days, to: lastDay) else { return nil }

        let dayComponents = calendar.dateComponents([.year, .month, .day], from: targetDay)
        var reminderComponents = DateComponents()
        reminderComponents.year = dayComponents.year
        reminderComponents.month = dayComponents.month
        reminderComponents.day = dayComponents.day
        reminderComponents.hour = 9
        reminderComponents.minute = 0
        reminderComponents.second = 0
        return calendar.date(from: reminderComponents)
    }

    static func expiryIdentifier(cardID: String, days: Int) -> String {
        "vaultcard.notification.\(cardID).expiry.\(days)"
    }

    static func useReminderIdentifier(cardID: String) -> String {
        "vaultcard.notification.\(cardID).useReminder"
    }
}

@MainActor
final class NoopNotificationService: NotificationScheduling {
    private var plans: [String: CardUseReminder] = [:]

    func requestAuthorization() async {}

    func syncForCard(_ card: VaultCard, preferences: NotificationPreferences) async {
        if let reminder = plans[card.id] {
            if let updated = CardNotificationPlanner.reconciledUseReminder(reminder, with: card, now: Date()) {
                plans[card.id] = updated
            } else {
                plans.removeValue(forKey: card.id)
            }
        }
    }

    func synchronize(cards: [VaultCard], preferences: NotificationPreferences) async {
        plans = CardNotificationPlanner.reconciledUseReminders(plans, with: cards, now: Date())
    }

    func scheduleUseReminder(for card: VaultCard, at date: Date) async throws {
        let reminder = try CardNotificationPlanner.makeUseReminder(for: card, at: date, now: Date())
        plans[card.id] = reminder
    }

    func cancelUseReminder(cardID: String) async {
        plans.removeValue(forKey: cardID)
    }

    func useReminders() -> [String: CardUseReminder] {
        return plans
    }

    func notificationsEnabled() async -> Bool { true }
}

@MainActor
final class NotificationService: NSObject, NotificationScheduling, UNUserNotificationCenterDelegate {
    private static let plansKey = "vaultcard.cardUseReminders.v1"
    private static let pendingReminderCardKey = "vaultcard.pendingReminderCardID.v1"

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private var privacyPreservingContent = true
    private var revision = 0

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.center = center
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        super.init()
        center.delegate = self
        center.setNotificationCategories([Self.makeReminderCategory()])
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func notificationsEnabled() async -> Bool {
        let settings = await center.notificationSettings()
        return [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
    }

    func syncForCard(_ card: VaultCard, preferences: NotificationPreferences) async {
        privacyPreservingContent = preferences.privacyPreservingContent
        let currentPlans = useReminders()
        var nextPlans = currentPlans
        if let oldPlan = currentPlans[card.id] {
            if let updated = CardNotificationPlanner.reconciledUseReminder(oldPlan, with: card, now: now()) {
                nextPlans[card.id] = updated
            } else {
                nextPlans.removeValue(forKey: card.id)
            }
        }
        if nextPlans != currentPlans {
            savePlans(nextPlans)
        }
        if currentPlans[card.id] != nil, nextPlans[card.id] == nil {
            await removeRequests(identifiers: [CardNotificationPlanner.useReminderIdentifier(cardID: card.id)])
        }

        let pendingRequests = await center.pendingNotificationRequests()
        let deliveredNotifications = await center.deliveredNotifications()
        let expiryIDs = Self.expiryRequestIdentifiers(
            for: card.id,
            identifiers: pendingRequests.map(\.identifier) + deliveredNotifications.map { $0.request.identifier }
        )
        await removeRequests(identifiers: legacyIdentifiers(for: card.id) + expiryIDs)
        let expiryPlans = CardNotificationPlanner.expiryNotifications(
            for: [card], preferences: preferences, now: now(), calendar: calendar
        )
        for plan in expiryPlans {
            await addExpiryRequest(plan, card: card, privacyPreserving: preferences.privacyPreservingContent)
        }
        if let reminder = nextPlans[card.id], reminder.fireDate > now() {
            try? await addUseReminderRequest(reminder, displayName: card.displayName, privacyPreserving: preferences.privacyPreservingContent)
        }
    }

    func synchronize(cards: [VaultCard], preferences: NotificationPreferences) async {
        revision += 1
        let currentRevision = revision
        privacyPreservingContent = preferences.privacyPreservingContent
        if !CardNotificationPlanner.expiryNotifications(
            for: cards, preferences: preferences, now: now(), calendar: calendar
        ).isEmpty {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined { await requestAuthorization() }
            guard currentRevision == revision, !Task.isCancelled else { return }
        }
        let existingPlans = useReminders()
        let nextPlans = CardNotificationPlanner.reconciledUseReminders(existingPlans, with: cards, now: now())
        savePlans(nextPlans)

        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        guard currentRevision == revision, !Task.isCancelled else { return }
        let existingOwnedIDs = Set((pending.map(\.identifier) + delivered.map { $0.request.identifier }).filter(Self.isOwnedRequestIdentifier))
        let pastReminderIDs = Set(nextPlans.values.filter { $0.fireDate <= now() }.map {
            CardNotificationPlanner.useReminderIdentifier(cardID: $0.cardID)
        })
        let planned = CardNotificationPlanner.pendingNotifications(
            cards: cards, preferences: preferences, reminders: nextPlans, now: now(), calendar: calendar
        )
        let plannedIDs = Set(planned.map(\.identifier))
        let preservedPastIDs = existingOwnedIDs.intersection(pastReminderIDs)
        let staleIDs = existingOwnedIDs.subtracting(plannedIDs.union(preservedPastIDs))
        await removeRequests(identifiers: Array(staleIDs))

        let cardsByID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for plan in planned where !preservedPastIDs.contains(plan.identifier) {
            guard currentRevision == revision, !Task.isCancelled else { return }
            guard let card = cardsByID[plan.cardID] else { continue }
            switch plan.kind {
            case .useReminder:
                guard let reminder = nextPlans[plan.cardID] else { continue }
                try? await addUseReminderRequest(reminder, displayName: card.displayName, privacyPreserving: preferences.privacyPreservingContent)
            case .expiry:
                await addExpiryRequest(plan, card: card, privacyPreserving: preferences.privacyPreservingContent)
            }
        }
    }

    func scheduleUseReminder(for card: VaultCard, at date: Date) async throws {
        let reminder = try CardNotificationPlanner.makeUseReminder(for: card, at: date, now: now())
        let settings = await center.notificationSettings()
        let hasAuthorization = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        let allowed: Bool
        if hasAuthorization {
            allowed = true
        } else if settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        } else {
            allowed = false
        }
        guard allowed else {
            throw VaultError.validation("Notifications are off. Allow them in Settings to save a use reminder.")
        }

        revision += 1
        try await makePendingCapacity(forCardID: card.id)
        try await addUseReminderRequest(reminder, displayName: card.displayName, privacyPreserving: privacyPreservingContent)
        center.removeDeliveredNotifications(withIdentifiers: [CardNotificationPlanner.useReminderIdentifier(cardID: card.id)])
        var plans = useReminders()
        plans[card.id] = reminder
        savePlans(plans)
    }

    func cancelUseReminder(cardID: String) async {
        revision += 1
        var plans = useReminders()
        plans.removeValue(forKey: cardID)
        savePlans(plans)
        await removeRequests(identifiers: [CardNotificationPlanner.useReminderIdentifier(cardID: cardID)])
    }

    func useReminders() -> [String: CardUseReminder] {
        guard let data = defaults.data(forKey: Self.plansKey),
              let plans = try? JSONDecoder().decode([String: CardUseReminder].self, from: data) else { return [:] }
        return plans
    }

    func consumePendingReminderCardID() -> String? {
        let cardID = defaults.string(forKey: Self.pendingReminderCardKey)
        defaults.removeObject(forKey: Self.pendingReminderCardKey)
        return cardID
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let completion = Once(completionHandler)
        let cardID = response.notification.request.content.userInfo["cardID"] as? String
        switch response.actionIdentifier {
        case CardReminderNotificationID.snoozeAction:
            guard let cardID else { completion.call(); return }
            Task { [weak self] in
                guard let self else { completion.call(); return }
                await self.snooze(cardID: cardID)
                completion.call()
            }
        case CardReminderNotificationID.dismissAction, UNNotificationDismissActionIdentifier:
            guard let cardID else { completion.call(); return }
            Task { [weak self] in
                guard let self else { completion.call(); return }
                await self.cancelUseReminder(cardID: cardID)
                completion.call()
            }
        case UNNotificationDefaultActionIdentifier:
            if let cardID {
                Task { @MainActor [weak self] in
                    guard let self else { completion.call(); return }
                    self.defaults.set(cardID, forKey: Self.pendingReminderCardKey)
                    NotificationCenter.default.post(name: .vaultcardOpenReminderCard, object: cardID)
                    completion.call()
                }
            } else {
                completion.call()
            }
        default:
            completion.call()
        }
    }

    private func snooze(cardID: String) async {
        guard var reminder = useReminders()[cardID] else { return }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now()) else { return }
        reminder.fireDate = tomorrow
        revision += 1
        do {
            try await makePendingCapacity(forCardID: cardID)
            try await addUseReminderRequest(reminder, displayName: nil, privacyPreserving: privacyPreservingContent)
            var plans = useReminders()
            plans[cardID] = reminder
            savePlans(plans)
            center.removeDeliveredNotifications(withIdentifiers: [CardNotificationPlanner.useReminderIdentifier(cardID: cardID)])
        } catch {
            // Preserve the fired reminder so it can still be re-armed in the app.
        }
    }

    private func addExpiryRequest(_ plan: PlannedCardNotification, card: VaultCard, privacyPreserving: Bool) async {
        guard case .expiry(let days) = plan.kind else { return }
        let content = UNMutableNotificationContent()
        content.title = "Card expiry reminder"
        content.body = privacyPreserving
            ? "Review the card’s last-known balance and expiry date in VaultCard."
            : "\(card.displayName) had an unused balance of \(Self.currencyString(card.balance ?? 0)) last checked \(card.lastFetchedAt.map(Self.dateString) ?? "recently"); it expires in about \(days) days."
        content.sound = .default
        content.userInfo = ["cardID": card.id]
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.fireDate),
            repeats: false
        )
        try? await center.add(UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger))
    }

    private func addUseReminderRequest(_ reminder: CardUseReminder, displayName: String?, privacyPreserving: Bool) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Time to use a saved card"
        if privacyPreserving {
            content.body = "Review your last-known balance, checked \(Self.dateString(reminder.lastCheckedAt))."
        } else {
            let cardName = displayName.map { "\($0): " } ?? ""
            content.body = "\(cardName)\(Self.currencyString(reminder.balance)) remained as of \(Self.dateString(reminder.lastCheckedAt))."
        }
        content.sound = .default
        content.categoryIdentifier = CardReminderNotificationID.reminderCategory
        content.userInfo = ["cardID": reminder.cardID]
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate),
            repeats: false
        )
        try await center.add(UNNotificationRequest(
            identifier: CardNotificationPlanner.useReminderIdentifier(cardID: reminder.cardID),
            content: content,
            trigger: trigger
        ))
    }

    private func savePlans(_ plans: [String: CardUseReminder]) {
        guard let data = try? JSONEncoder().encode(plans) else { return }
        defaults.set(data, forKey: Self.plansKey)
    }

    private func removeRequests(identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func makePendingCapacity(forCardID cardID: String) async throws {
        let existingID = CardNotificationPlanner.useReminderIdentifier(cardID: cardID)
        var pending = await center.pendingNotificationRequests().filter { Self.isOwnedRequestIdentifier($0.identifier) }
        guard !pending.contains(where: { $0.identifier == existingID }) else { return }
        while pending.count >= CardNotificationPlanner.pendingRequestLimit {
            let expiryRequests = pending.filter { Self.isExpiryRequestIdentifier($0.identifier) }
            guard let farthestExpiry = expiryRequests.max(by: {
                (($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture) < (($1.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture)
            }) else {
                throw VaultError.validation("There are already 64 pending reminders. Remove one before adding another.")
            }
            center.removePendingNotificationRequests(withIdentifiers: [farthestExpiry.identifier])
            pending.removeAll { $0.identifier == farthestExpiry.identifier }
        }
    }

    private func legacyIdentifiers(for cardID: String) -> [String] {
        ["\(cardID).low", "\(cardID).refreshFailed"]
    }

    private static func expiryRequestIdentifiers(for cardID: String, identifiers: [String]) -> [String] {
        let currentPrefix = "vaultcard.notification.\(cardID).expiry."
        let legacyPrefix = "\(cardID).expiry."
        return identifiers.filter { identifier in
            (identifier.hasPrefix(currentPrefix) || identifier.hasPrefix(legacyPrefix))
                && isExpiryRequestIdentifier(identifier)
        }
    }

    private static func isExpiryRequestIdentifier(_ identifier: String) -> Bool {
        guard let marker = identifier.range(of: ".expiry.", options: .backwards) else { return false }
        let day = identifier[marker.upperBound...]
        return !day.isEmpty && day.allSatisfy(\.isNumber)
    }

    private static func isOwnedRequestIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("vaultcard.notification.")
            || identifier.hasSuffix(".low")
            || identifier.hasSuffix(".refreshFailed")
            || isExpiryRequestIdentifier(identifier)
    }

    private static func makeReminderCategory() -> UNNotificationCategory {
        let snooze = UNNotificationAction(identifier: CardReminderNotificationID.snoozeAction, title: "Snooze Until Tomorrow", options: [])
        let dismiss = UNNotificationAction(identifier: CardReminderNotificationID.dismissAction, title: "Dismiss", options: [.destructive])
        return UNNotificationCategory(identifier: CardReminderNotificationID.reminderCategory, actions: [snooze, dismiss], intentIdentifiers: [], options: [.customDismissAction])
    }

    private static func currencyString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

private final class Once {
    private let lock = NSLock()
    private var completion: (() -> Void)?

    init(_ completion: @escaping () -> Void) { self.completion = completion }

    func call() {
        lock.lock()
        let action = completion
        completion = nil
        lock.unlock()
        action?()
    }
}

private enum CardReminderNotificationID {
    static let reminderCategory = "vaultcard.cardUseReminder"
    static let snoozeAction = "vaultcard.snoozeReminderTomorrow"
    static let dismissAction = "vaultcard.dismissReminder"
}
