import XCTest
@testable import VaultCard

final class CardNotificationServiceTests: XCTestCase {
    func testExpiryPlansUseMonthEndAtNineAMAndHandleDecemberRollover() throws {
        let calendar = utcCalendar()
        let now = date(2025, 1, 1, calendar: calendar)

        let januaryPlans = CardNotificationPlanner.expiryNotifications(
            for: [card(id: "jan", expiry: "01/26")],
            preferences: NotificationPreferences(),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(januaryPlans.map(\.fireDate), [
            date(2026, 1, 1, hour: 9, calendar: calendar)
        ])

        let decemberPlans = CardNotificationPlanner.expiryNotifications(
            for: [card(id: "dec", expiry: "12/25")],
            preferences: NotificationPreferences(),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(decemberPlans.map(\.fireDate), [
            date(2025, 12, 1, hour: 9, calendar: calendar)
        ])
    }

    func testExpiryPlansUseConfiguredLeadDayAndRequireKnownPositiveBalance() {
        let calendar = utcCalendar()
        let now = date(2025, 1, 1, calendar: calendar)
        let valid = card(id: "valid", expiry: "01/26", balance: 2.5)
        let invalidCards = [
            card(id: "unknown", expiry: "01/26", balance: nil),
            card(id: "zero", expiry: "01/26", balance: 0),
            card(id: "negative", expiry: "01/26", balance: -1),
            card(id: "nan", expiry: "01/26", balance: .nan),
            card(id: "infinite", expiry: "01/26", balance: .infinity)
        ]
        var archived = card(id: "archived", expiry: "01/26", balance: 1)
        archived.archivedAt = now

        let plans = CardNotificationPlanner.expiryNotifications(
            for: [valid] + invalidCards + [archived],
            preferences: NotificationPreferences(expiryWarningDays: 14),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.cardID, "valid")
        XCTAssertEqual(plans.first?.kind, .expiry(daysBeforeEnd: 14))
        XCTAssertEqual(plans.first?.identifier, CardNotificationPlanner.expiryIdentifier(cardID: "valid", days: 14))
        XCTAssertEqual(plans.first?.fireDate, date(2026, 1, 17, hour: 9, calendar: calendar))
    }

    func testExpiryPlansRespectPreferenceArchivedCardsAndPastDates() {
        let calendar = utcCalendar()
        let now = date(2025, 12, 25, calendar: calendar)
        let active = card(id: "active", expiry: "12/26")
        var archived = card(id: "archived", expiry: "12/26")
        archived.archivedAt = now
        let alreadyPast = card(id: "past", expiry: "12/24")
        let cards = [active, archived, alreadyPast]

        XCTAssertTrue(CardNotificationPlanner.expiryNotifications(
            for: cards,
            preferences: NotificationPreferences(expiryWarning: false),
            now: now,
            calendar: calendar
        ).isEmpty)

        let plans = CardNotificationPlanner.expiryNotifications(
            for: cards,
            preferences: NotificationPreferences(),
            now: now,
            calendar: calendar
        )
        XCTAssertTrue(plans.allSatisfy { $0.cardID == "active" })
        XCTAssertEqual(plans.map(\.kind), [.expiry(daysBeforeEnd: 30)])
    }

    func testUseReminderRequiresFutureDateAndKnownFinitePositiveLowBalance() {
        let now = date(2026, 1, 1, calendar: utcCalendar())
        let valid = card(id: "valid", balance: 4.25, fetchedAt: now)
        let reminder = try? CardNotificationPlanner.makeUseReminder(
            for: valid,
            at: now.addingTimeInterval(60),
            now: now
        )
        XCTAssertEqual(reminder?.balance, 4.25)
        XCTAssertEqual(reminder?.lastCheckedAt, now)

        let invalidCards = [
            card(id: "unknown", balance: nil, fetchedAt: now),
            card(id: "zero", balance: 0, fetchedAt: now),
            card(id: "negative", balance: -1, fetchedAt: now),
            card(id: "threshold", balance: 10, fetchedAt: now),
            card(id: "nan", balance: .nan, fetchedAt: now),
            card(id: "infinite", balance: .infinity, fetchedAt: now),
            card(id: "unfetched", balance: 4, fetchedAt: nil)
        ]
        for invalid in invalidCards {
            XCTAssertThrowsError(try CardNotificationPlanner.makeUseReminder(
                for: invalid,
                at: now.addingTimeInterval(60),
                now: now
            ))
        }
        XCTAssertThrowsError(try CardNotificationPlanner.makeUseReminder(for: valid, at: now, now: now))

        var archived = valid
        archived.archivedAt = now
        XCTAssertThrowsError(try CardNotificationPlanner.makeUseReminder(
            for: archived,
            at: now.addingTimeInterval(60),
            now: now
        ))
    }

    func testRefreshPreservesDateAndUpdatesSnapshotUntilCardIsIneligible() throws {
        let now = date(2026, 1, 1, calendar: utcCalendar())
        let originalCard = card(id: "card", balance: 4, fetchedAt: now)
        let selectedDate = now.addingTimeInterval(3_600)
        let reminder = try CardNotificationPlanner.makeUseReminder(for: originalCard, at: selectedDate, now: now)
        let refreshedCard = card(id: "card", balance: 3.5, fetchedAt: now.addingTimeInterval(300))

        let refreshed = try XCTUnwrap(CardNotificationPlanner.reconciledUseReminder(reminder, with: refreshedCard, now: now))
        XCTAssertEqual(refreshed.fireDate, selectedDate)
        XCTAssertEqual(refreshed.balance, 3.5)
        XCTAssertEqual(refreshed.lastCheckedAt, refreshedCard.lastFetchedAt)

        let zeroBalanceCard = card(id: "card", balance: 0, fetchedAt: now.addingTimeInterval(600))
        XCTAssertNil(CardNotificationPlanner.reconciledUseReminder(refreshed, with: zeroBalanceCard, now: now))
        var archivedCard = refreshedCard
        archivedCard.archivedAt = now
        XCTAssertNil(CardNotificationPlanner.reconciledUseReminder(refreshed, with: archivedCard, now: now))
    }

    func testWholeCardReconciliationCancelsDeletedPlansAndKeepsFiredPlansVisible() throws {
        let now = date(2026, 1, 1, calendar: utcCalendar())
        let cards = [
            card(id: "positive", balance: 3, fetchedAt: now),
            card(id: "zero", balance: 0, fetchedAt: now)
        ]
        let reminders = [
            "positive": CardUseReminder(cardID: "positive", fireDate: now.addingTimeInterval(-60), balance: 4, lastCheckedAt: now.addingTimeInterval(-100)),
            "zero": CardUseReminder(cardID: "zero", fireDate: now.addingTimeInterval(600), balance: 2, lastCheckedAt: now),
            "deleted": CardUseReminder(cardID: "deleted", fireDate: now.addingTimeInterval(600), balance: 2, lastCheckedAt: now)
        ]

        let reconciled = CardNotificationPlanner.reconciledUseReminders(reminders, with: cards, now: now)
        XCTAssertEqual(Set(reconciled.keys), ["positive"])
        XCTAssertEqual(reconciled["positive"]?.fireDate, now.addingTimeInterval(-60))
        XCTAssertEqual(reconciled["positive"]?.balance, 3)
        XCTAssertEqual(reconciled["positive"]?.lastCheckedAt, now)
        XCTAssertTrue(CardNotificationPlanner.pendingNotifications(
            cards: cards,
            preferences: NotificationPreferences(),
            reminders: reconciled,
            now: now,
            calendar: utcCalendar()
        ).allSatisfy { $0.kind != .useReminder })
    }

    func testPendingLimitPrioritizesUserRemindersThenNearestExpiry() throws {
        let calendar = utcCalendar()
        let now = date(2025, 1, 1, calendar: calendar)
        let cards = (0..<70).map { index in
            card(id: String(format: "%02d", index), expiry: "09/29", balance: 5, fetchedAt: now)
        }
        let reminders = Dictionary(uniqueKeysWithValues: (0..<2).map { index in
            let id = String(format: "%02d", index)
            return (id, CardUseReminder(
                cardID: id,
                fireDate: now.addingTimeInterval(TimeInterval(3_600 + index)),
                balance: 5,
                lastCheckedAt: now
            ))
        })

        let pending = CardNotificationPlanner.pendingNotifications(
            cards: cards,
            preferences: NotificationPreferences(),
            reminders: reminders,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(pending.count, 64)
        XCTAssertEqual(pending.prefix(2).map(\.kind), [.useReminder, .useReminder])
        XCTAssertTrue(pending.dropFirst(2).allSatisfy {
            if case .expiry = $0.kind { return true }
            return false
        })
        XCTAssertEqual(pending.dropFirst(2).first?.fireDate, date(2029, 8, 31, hour: 9, calendar: calendar))
    }

    func testLegacyPreferencesIgnoreRemovedSwitchesAndKeepExpiryChoice() throws {
        let json = Data(#"{"analyticsEnabled":true,"notificationPreferences":{"expiryWarning":false,"lowBalance":true,"refreshFailed":true,"balanceUpdated":true}}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertFalse(settings.notificationPreferences.expiryWarning)
        XCTAssertEqual(settings.notificationPreferences.expiryWarningDays, 30)
        XCTAssertTrue(settings.notificationPreferences.privacyPreservingContent)
        let encoded = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        for obsolete in ["analyticsEnabled", "lowBalance", "refreshFailed", "balanceUpdated"] {
            XCTAssertFalse(encoded.contains(obsolete))
        }
    }

    private func card(
        id: String,
        expiry: String = "09/29",
        balance: Double? = 5,
        fetchedAt: Date? = Date(timeIntervalSince1970: 1_000)
    ) -> VaultCard {
        VaultCard(
            id: id,
            nickname: nil,
            network: .visa,
            last4: "1234",
            expiry: expiry,
            balance: balance,
            transactions: [],
            lastFetchedAt: fetchedAt,
            fetchFailureCount: 0,
            addedAt: Date(timeIntervalSince1970: 0),
            refreshBlockedUntil: nil,
            credentialVersion: 1
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
