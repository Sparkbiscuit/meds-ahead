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
    /// The schedules a follow-up asks about, comma-separated in its userInfo.
    static let memberScheduleIDsKey = "memberScheduleIDs"

    /// The one dated reminder for every dose due at this moment.
    static func dose(at slot: Date, calendar: Calendar) -> String {
        "meds.group.dose.date.\(dayCode(slot, calendar: calendar)).\(timeCode(slot, calendar: calendar))"
    }

    /// The follow-up for every dose due at this moment, named for the dose's
    /// moment, not its own.
    static func followUp(at slot: Date, calendar: Calendar) -> String {
        "meds.group.followup.\(dayCode(slot, calendar: calendar)).\(timeCode(slot, calendar: calendar))"
    }

    /// The weekly count check for one medication, on the day it asks.
    static func countCheck(medicationID: UUID, on day: Date, calendar: Calendar) -> String {
        countCheckPrefix(medicationID: medicationID) + dayCode(day, calendar: calendar)
    }

    static func countCheckPrefix(medicationID: UUID) -> String {
        "meds.countcheck.\(medicationID.uuidString)."
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

    static func memberScheduleIDsValue(_ scheduleIDs: [UUID]) -> String {
        scheduleIDs.map(\.uuidString).joined(separator: ",")
    }

    static func memberScheduleIDs(in userInfo: [AnyHashable: Any]) -> [UUID] {
        guard let value = userInfo[memberScheduleIDsKey] as? String else { return [] }
        return value.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }

    /// Whether every dose a follow-up asks about is logged, so the widget may
    /// withdraw it. One follow-up stands for every medication due at its
    /// moment, and logging one of them must not silence the question about
    /// the rest. A follow-up that does not say what it asks about, or names a
    /// schedule this store no longer has, is left to ring.
    static func followUpIsAnswered(
        memberScheduleIDs: [UUID],
        slot: Date,
        schedules: [DoseSchedule],
        doseEvents: [DoseEvent],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard !memberScheduleIDs.isEmpty else { return false }
        return memberScheduleIDs.allSatisfy { scheduleID in
            guard let schedule = schedules.first(where: { $0.id == scheduleID }) else { return false }
            let dose = ScheduledDose(medicationID: schedule.medicationID, scheduleID: scheduleID, date: slot, quantity: schedule.doseQuantity)
            return ScheduleEngine.loggedEvent(for: dose, in: doseEvents, now: now, calendar: calendar) != nil
        }
    }
}
