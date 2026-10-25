import Foundation

enum TransactionRefreshPolicy {
    /// Starts history at the beginning of the month before the newest saved
    /// transaction. Cards without history start at the beginning of this year.
    static func fromDate(
        transactions: [CardTransaction],
        now: Date,
        calendar: Calendar
    ) -> Date {
        guard let newestTransactionDate = transactions.map(\.date).max() else {
            if let yearStart = calendar.dateInterval(of: .year, for: now)?.start {
                return yearStart
            }

            var components = calendar.dateComponents([.era, .year], from: now)
            components.month = 1
            components.day = 1
            return calendar.date(from: components) ?? calendar.startOfDay(for: now)
        }

        if let monthStart = calendar.dateInterval(of: .month, for: newestTransactionDate)?.start,
           let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart) {
            return previousMonthStart
        }

        var components = calendar.dateComponents([.era, .year, .month], from: newestTransactionDate)
        components.day = 1
        let monthStart = calendar.date(from: components) ?? calendar.startOfDay(for: newestTransactionDate)
        return calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
    }

    /// Formats a date using the supplied calendar's time zone and fixed ISO ordering.
    static func dateOnlyISO(_ date: Date, calendar: Calendar) -> String {
        formattedDate(date, format: "yyyy-MM-dd", calendar: calendar)
    }

    /// Formats a date using the supplied calendar's time zone and US ordering.
    static func dateOnlyUS(_ date: Date, calendar: Calendar) -> String {
        formattedDate(date, format: "MM/dd/yyyy", calendar: calendar)
    }

    /// Combines refreshed rows with saved history, preserving saved IDs for matches.
    /// Identical transactions are matched by multiplicity so legitimate repeated
    /// purchases remain separate rows.
    static func merge(existing: [CardTransaction], incoming: [CardTransaction]) -> [CardTransaction] {
        var merged = existing
        var unmatchedExistingCounts: [TransactionKey: Int] = [:]

        for transaction in existing {
            unmatchedExistingCounts[TransactionKey(transaction), default: 0] += 1
        }

        for transaction in incoming {
            let key = TransactionKey(transaction)
            if let existingCount = unmatchedExistingCounts[key], existingCount > 0 {
                unmatchedExistingCounts[key] = existingCount - 1
            } else {
                merged.append(transaction)
            }
        }

        return merged
    }

    private static func formattedDate(_ date: Date, format: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private struct TransactionKey: Hashable {
        let date: Date
        let description: String
        let amount: Double

        init(_ transaction: CardTransaction) {
            date = transaction.date
            description = transaction.description
            amount = transaction.amount
        }
    }
}
