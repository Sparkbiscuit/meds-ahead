import Foundation

/// The names and details of reminders planned for one day and time, shared by
/// the app's planner and the widget. The widget does not replan, so whatever
/// it does to a planned reminder it does by name; spelled differently in two
/// places, the name would miss.
enum NotificationIdentifiers {
    /// The scheduled moment a dated reminder or a follow-up stands for, kept in
    /// its userInfo. A follow-up for a 23:45 dose arrives after midnight, so
    /// the moment it is delivered does not say which day's dose it means.
    static let slotDateKey = "slotDate"

    /// The one dated reminder for every dose due at this moment.
    static func dose(at slot: Date, calendar: Calendar) -> String {
        "meds.group.dose.date.\(dayCode(slot, calendar: calendar)).\(timeCode(slot, calendar: calendar))"
    }

    /// A day as yyyyMMdd in the given calendar.
    static func dayCode(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// A time of day as HHmm in the given calendar.
    static func timeCode(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func slotDateValue(_ slot: Date) -> String {
        String(slot.timeIntervalSince1970)
    }

    static func slotDate(in userInfo: [AnyHashable: Any]) -> Date? {
        guard let value = userInfo[slotDateKey] as? String, let seconds = Double(value) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
