import Foundation
import XCTest
@testable import VaultCard

final class CardRowTimestampTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    func testOmitsYearAtTheTwelveCalendarMonthCutoff() {
        let now = date(year: 2025, month: 10, day: 25)
        let cutoff = date(year: 2024, month: 10, day: 25)

        XCTAssertEqual(
            CardRowTimestamp.string(date: cutoff, now: now, calendar: calendar, locale: locale).replacingOccurrences(of: "\u{202F}", with: " "),
            "Oct 25, 10:21 AM"
        )
    }

    func testOmitsYearForRecentDateInPreviousCalendarYear() {
        let now = date(year: 2025, month: 10, day: 25)
        let recent = date(year: 2024, month: 11, day: 1)

        XCTAssertEqual(
            CardRowTimestamp.string(date: recent, now: now, calendar: calendar, locale: locale).replacingOccurrences(of: "\u{202F}", with: " "),
            "Nov 1, 10:21 AM"
        )
    }

    func testIncludesYearForDateOlderThanTwelveCalendarMonths() {
        let now = date(year: 2025, month: 10, day: 25)
        let older = date(year: 2024, month: 10, day: 24)

        XCTAssertEqual(
            CardRowTimestamp.string(date: older, now: now, calendar: calendar, locale: locale).replacingOccurrences(of: "\u{202F}", with: " "),
            "Oct 24, 2024, 10:21 AM"
        )
    }

    func testIncludesYearForFutureDate() {
        let now = date(year: 2025, month: 10, day: 25)
        let future = date(year: 2025, month: 10, day: 26)

        XCTAssertEqual(
            CardRowTimestamp.string(date: future, now: now, calendar: calendar, locale: locale).replacingOccurrences(of: "\u{202F}", with: " "),
            "Oct 26, 2025, 10:21 AM"
        )
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 10, minute: 21))!
    }
}
