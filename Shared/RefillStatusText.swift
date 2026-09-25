import Foundation

/// The one sentence Today, Supply and the detail screen all use for a refill
/// under way.
enum RefillStatusText {
    static func line(for medication: Medication, now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> String? {
        let date = medication.refillStatusDate
        // Days are read in the calendar passed in, from `now`, so the words
        // agree with the attention rule that is counted the same way.
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
        func day(_ date: Date) -> String {
            if calendar.isDate(date, inSameDayAs: now) { return "today" }
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
                return "tomorrow"
            }
            if let week = calendar.date(byAdding: .day, value: 6, to: calendar.startOfDay(for: now)), date <= week, date > now {
                return date.formatted(style.weekday(.wide))
            }
            return date.formatted(style.month(.abbreviated).day())
        }
        switch medication.refillStatus {
        case .none:
            return nil
        case .requested:
            guard let date else { return "Refill requested" }
            // "Expected" on a day already gone reads as reassurance it no longer is.
            if calendar.startOfDay(for: date) < calendar.startOfDay(for: now) {
                return "Refill requested · was expected \(day(date))"
            }
            return "Refill requested · expected \(day(date))"
        case .ready:
            guard let date else { return "Ready for pickup" }
            return date <= now ? "Ready for pickup" : "Pick up \(day(date))"
        }
    }
}

extension RefillStatus: Identifiable {
    var id: String { rawValue }
}
