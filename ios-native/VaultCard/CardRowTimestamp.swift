import Foundation

enum CardRowTimestamp {
    static func string(
        date: Date,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let cutoff = calendar.date(byAdding: .month, value: -12, to: now)
        let includesYear = (cutoff.map { date < $0 } ?? true) || date > now

        var dateStyle = Date.FormatStyle.dateTime.month(.abbreviated).day()
        dateStyle.locale = locale
        dateStyle.calendar = calendar
        dateStyle.timeZone = calendar.timeZone
        let displayedDate = date.formatted(includesYear ? dateStyle.year() : dateStyle)
        var timeStyle = Date.FormatStyle.dateTime.hour().minute()
        timeStyle.locale = locale
        timeStyle.calendar = calendar
        timeStyle.timeZone = calendar.timeZone
        let displayedTime = date.formatted(timeStyle)

        return "\(displayedDate), \(displayedTime)"
    }
}
