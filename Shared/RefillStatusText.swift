import Foundation

/// The one sentence Today, Supply and the detail screen all use for a refill
/// under way.
enum RefillStatusText {
    static func line(for medication: Medication, now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> String? {
        let date = medication.refillStatusDate
        func day(_ date: Date) -> String {
            if calendar.isDateInToday(date) { return "today" }
            if calendar.isDateInTomorrow(date) { return "tomorrow" }
            if let week = calendar.date(byAdding: .day, value: 6, to: calendar.startOfDay(for: now)), date <= week, date > now {
                return date.formatted(.dateTime.weekday(.wide))
            }
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        switch medication.refillStatus {
        case .none:
            return nil
        case .requested:
            return date.map { "Refill requested · expected \(day($0))" } ?? "Refill requested"
        case .ready:
            guard let date else { return "Ready for pickup" }
            return date <= now ? "Ready for pickup" : "Pick up \(day(date))"
        }
    }
}

extension RefillStatus: Identifiable {
    var id: String { rawValue }
}
