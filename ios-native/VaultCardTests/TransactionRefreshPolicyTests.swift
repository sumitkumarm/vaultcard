import Foundation
import XCTest
@testable import VaultCard

final class TransactionRefreshPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    func testFromDateUsesExpectedCalendarBoundaryForEmptyAndJanuaryHistory() {
        let testCalendar = calendar
        let cases: [(name: String, transactions: [CardTransaction], now: Date, expected: Date)] = [
            (
                "empty history starts at the current year",
                [],
                date(2025, 7, 14, calendar: testCalendar),
                date(2025, 1, 1, calendar: testCalendar)
            ),
            (
                "January history rolls back to December",
                [transaction("jan", date: date(2025, 1, 8, calendar: testCalendar))],
                date(2025, 2, 1, calendar: testCalendar),
                date(2024, 12, 1, calendar: testCalendar)
            )
        ]

        for testCase in cases {
            let fromDate = TransactionRefreshPolicy.fromDate(
                transactions: testCase.transactions,
                now: testCase.now,
                calendar: testCalendar
            )
            XCTAssertEqual(fromDate, testCase.expected, testCase.name)
        }
    }

    func testUnsortedHistoryStartsMonthBeforeNewestTransactionAcrossDST() {
        let testCalendar = calendar
        let transactions = [
            transaction("old", date: date(2023, 12, 15, calendar: testCalendar)),
            transaction("newest", date: date(2024, 3, 10, hour: 3, minute: 30, calendar: testCalendar)),
            transaction("middle", date: date(2024, 2, 29, calendar: testCalendar))
        ]

        let fromDate = TransactionRefreshPolicy.fromDate(
            transactions: transactions,
            now: date(2024, 3, 11, calendar: testCalendar),
            calendar: testCalendar
        )

        XCTAssertEqual(fromDate, date(2024, 2, 1, calendar: testCalendar))
    }

    func testDateStringsUseSuppliedCalendarTimeZoneAndKeepLeapDay() {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let shortlyAfterMidnightUTC = date(2024, 3, 1, hour: 0, minute: 30, calendar: utcCalendar)
        let testCalendar = calendar

        XCTAssertEqual(TransactionRefreshPolicy.dateOnlyISO(shortlyAfterMidnightUTC, calendar: testCalendar), "2024-02-29")
        XCTAssertEqual(TransactionRefreshPolicy.dateOnlyUS(shortlyAfterMidnightUTC, calendar: testCalendar), "02/29/2024")
    }

    func testMergePreservesOlderRowsAndExistingIDsForOverlaps() {
        let testCalendar = calendar
        let older = transaction("older-id", date: date(2024, 1, 12, calendar: testCalendar), description: "Old purchase")
        let overlap = transaction("saved-id", date: date(2024, 3, 10, calendar: testCalendar), description: "Coffee", amount: -4.5)
        let newRow = transaction("new-id", date: date(2024, 4, 3, calendar: testCalendar), description: "Book", amount: -12)

        let merged = TransactionRefreshPolicy.merge(
            existing: [older, overlap],
            incoming: [
                transaction("fresh-uuid", date: overlap.date, description: overlap.description, amount: overlap.amount),
                newRow
            ]
        )

        XCTAssertEqual(merged.map(\.id), ["older-id", "saved-id", "new-id"])
        XCTAssertEqual(merged.count, 3)
    }

    func testMergeUsesMaximumMultiplicityForRepeatedIdenticalTransactions() {
        let testCalendar = calendar
        let repeatedDate = date(2024, 8, 17, calendar: testCalendar)
        let existing = [
            transaction("a1", date: repeatedDate, description: "Market", amount: -6),
            transaction("a2", date: repeatedDate, description: "Market", amount: -6),
            transaction("a3", date: repeatedDate, description: "Market", amount: -6),
            transaction("b1", date: repeatedDate, description: "Cafe", amount: -3)
        ]
        let incoming = [
            transaction("a-fresh-1", date: repeatedDate, description: "Market", amount: -6),
            transaction("a-fresh-2", date: repeatedDate, description: "Market", amount: -6),
            transaction("b-fresh-1", date: repeatedDate, description: "Cafe", amount: -3),
            transaction("b-fresh-2", date: repeatedDate, description: "Cafe", amount: -3)
        ]

        let merged = TransactionRefreshPolicy.merge(existing: existing, incoming: incoming)

        let markets = merged.filter { $0.description == "Market" }
        let cafes = merged.filter { $0.description == "Cafe" }
        XCTAssertEqual(markets.count, 3)
        XCTAssertEqual(markets.map(\.id), ["a1", "a2", "a3"])
        XCTAssertEqual(cafes.count, 2)
        XCTAssertEqual(cafes.map(\.id), ["b1", "b-fresh-2"])
    }

    private func transaction(
        _ id: String,
        date: Date,
        description: String = "Purchase",
        amount: Double = -1
    ) -> CardTransaction {
        CardTransaction(id: id, date: date, description: description, amount: amount)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }
}

final class TransactionDirectionAndAmountTests: XCTestCase {
    func testDirectionAndAmountOrderingPreserveSignedValues() {
        let amounts = [-100.0, 20, -5, 200, 0]
        XCTAssertEqual(amounts.filter(TransactionDirectionFilter.debits.includes), [-100, -5])
        XCTAssertEqual(amounts.filter(TransactionDirectionFilter.credits.includes), [20, 200])
        XCTAssertEqual(amounts.filter(TransactionDirectionFilter.all.includes), amounts)
        XCTAssertEqual(amounts.sorted(by: TransactionAmountOrder.highest.precedes), [200, -100, 20, -5, 0])
        XCTAssertEqual(amounts.sorted(by: TransactionAmountOrder.lowest.precedes), [0, -5, 20, -100, 200])
        XCTAssertFalse(TransactionAmountOrder.highest.precedes(-100, 100))
        XCTAssertFalse(TransactionAmountOrder.highest.precedes(100, -100))
        XCTAssertEqual(TransactionAppearance(amount: -100).formattedAmount, "−$100.00")
        XCTAssertEqual(TransactionAppearance(amount: 20).formattedAmount, "+$20.00")
    }
}

final class TransactionAmountRangeTests: XCTestCase {
    func testAmountRangeUsesInclusiveMagnitudesAndValidatesLocalizedInput() throws {
        let us = Locale(identifier: "en_US")
        let range = try TransactionAmountRange.parse(minimum: "20.50", maximum: "100", locale: us)
        for value in [-100.0, -20.50, 20.50, 100] { XCTAssertTrue(range.includes(value)) }
        for value in [-100.01, -20.49, 0, 100.01] { XCTAssertFalse(range.includes(value)) }
        XCTAssertFalse(try TransactionAmountRange.parse(minimum: "", maximum: "", locale: us).isActive)
        XCTAssertTrue(try TransactionAmountRange.parse(minimum: "", maximum: "100", locale: us).includes(-100))
        XCTAssertTrue(try TransactionAmountRange.parse(minimum: "100", maximum: "", locale: us).includes(-200))
        XCTAssertEqual(try TransactionAmountRange.parse(minimum: "1.234,50", maximum: "", locale: Locale(identifier: "de_DE")).minimum, 1234.5)
        for (lower, upper) in [("-1", ""), ("12x", ""), ("1.234", ""), ("1,2,3", ""), ("101", "100")] {
            XCTAssertThrowsError(try TransactionAmountRange.parse(minimum: lower, maximum: upper, locale: us))
        }
    }
}

@MainActor
final class TransactionInitialLoadTests: XCTestCase {
    func testEarliestRecordedCreditAndSavedCorrectionsDoNotReplaceAnotherCreditByAccident() throws {
        let environment = try AppEnvironment.uiTesting()
        let model = AppModel(environment: environment)
        let cardID = try model.addCard(CardInput(cardNumber: "4111111111111111", expiry: "09/29", cvv: "123"))
        let purchase = CardTransaction(id: "purchase", date: Date(timeIntervalSince1970: 0), description: "Purchase", amount: -100)
        let load = CardTransaction(id: "load", date: Date(timeIntervalSince1970: 100), description: "Online", amount: 50)
        let refund = CardTransaction(id: "refund", date: Date(timeIntervalSince1970: 200), description: "Refund", amount: 200)
        try environment.cardRepository.applyBalanceResult(cardID: cardID, result: BalanceResult(balance: 150, transactions: [refund, purchase, load], fetchedAt: Date()))
        model.reloadCards()
        let card = try XCTUnwrap(model.cards.first)
        XCTAssertEqual(TransactionInitialLoad.ids(for: card, overrides: [:]), ["load"])
        model.setTransactionInitialLoad(cardID: cardID, transactionID: "refund", isInitialLoad: true)
        let saved = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(environment.settingsRepository.load()))
        XCTAssertEqual(TransactionInitialLoad.ids(for: card, overrides: saved.transactionInitialLoadOverrides), ["refund"])
        model.setTransactionInitialLoad(cardID: cardID, transactionID: "refund", isInitialLoad: nil)
        XCTAssertEqual(TransactionInitialLoad.ids(for: card, overrides: model.settings.transactionInitialLoadOverrides), ["load"])
        model.setTransactionInitialLoad(cardID: cardID, transactionID: "load", isInitialLoad: false)
        XCTAssertTrue(TransactionInitialLoad.ids(for: card, overrides: model.settings.transactionInitialLoadOverrides).isEmpty)
        model.setTransactionInitialLoad(cardID: cardID, transactionID: "purchase", isInitialLoad: true)
        XCTAssertNil(model.settings.transactionInitialLoadOverrides[TransactionInitialLoad.key(cardID: cardID, transactionID: "purchase")])
        var anotherCard = card
        anotherCard.id = "another-card"
        XCTAssertEqual(TransactionInitialLoad.ids(for: anotherCard, overrides: model.settings.transactionInitialLoadOverrides), ["load"])
    }
}
