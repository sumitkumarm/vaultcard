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
