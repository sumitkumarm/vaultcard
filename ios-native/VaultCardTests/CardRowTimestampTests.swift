import Foundation
import XCTest
@testable import VaultCard

final class CardRowTimestampTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    func testYearDisplayAcrossCalendarMonthBoundaryCases() {
        let now = date(year: 2025, month: 10, day: 25)
        let cases: [(date: Date, expected: String)] = [
            (date(year: 2024, month: 10, day: 25), "Oct 25, 10:21 AM"),
            (date(year: 2024, month: 11, day: 1), "Nov 1, 10:21 AM"),
            (date(year: 2024, month: 10, day: 24), "Oct 24, 2024, 10:21 AM"),
            (date(year: 2025, month: 10, day: 26), "Oct 26, 2025, 10:21 AM")
        ]

        for testCase in cases {
            XCTAssertEqual(
                CardRowTimestamp.string(date: testCase.date, now: now, calendar: calendar, locale: locale)
                    .replacingOccurrences(of: "\u{202F}", with: " "),
                testCase.expected
            )
        }
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
