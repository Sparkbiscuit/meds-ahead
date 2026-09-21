import Foundation

struct ScheduledDose: Identifiable, Equatable {
    let id: String
    let medicationID: UUID
    let scheduleID: UUID
    let date: Date
    let quantity: Double

    init(medicationID: UUID, scheduleID: UUID, date: Date, quantity: Double) {
        self.medicationID = medicationID
        self.scheduleID = scheduleID
        self.date = date
        self.quantity = quantity
        self.id = "\(scheduleID.uuidString)-\(date.timeIntervalSince1970)"
    }
}

enum DoseTimingState: Equatable {
    case upcoming
    case due
    case overdue
}

enum ScheduleEngine {
    static func timingState(
        for scheduledAt: Date,
        now: Date = .now,
        dueWindow: TimeInterval = 30 * 60
    ) -> DoseTimingState {
        // The UI-test override lives here rather than in one screen's own copy, so
        // driving the overdue state cannot make Today and Take Now disagree about
        // whether a dose is actionable — the disagreement this method exists to end.
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-force-overdue-dose-state") {
            return .overdue
        }
#endif
        if scheduledAt < now.addingTimeInterval(-dueWindow) {
            return .overdue
        }
        if scheduledAt <= now.addingTimeInterval(dueWindow) {
            return .due
        }
        return .upcoming
    }

    static func isActive(
        _ schedule: DoseSchedule,
        on day: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        let start = calendar.startOfDay(for: schedule.startDate)
        let target = calendar.startOfDay(for: day)
        guard target >= start else { return false }
        if let endDate = schedule.endDate,
           target > calendar.startOfDay(for: endDate) {
            return false
        }
        let weekday = calendar.component(.weekday, from: target) - 1
        return schedule.weekdayMask & (1 << weekday) != 0
    }

    static func scheduledDate(
        for schedule: DoseSchedule,
        on day: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        guard isActive(schedule, on: day, calendar: calendar) else { return nil }
        let hour = schedule.minutesAfterMidnight / 60
        let minute = schedule.minutesAfterMidnight % 60
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    /// Every dose scheduled on the calendar day containing `day`. Today, the
    /// medication detail screen, and the missed-dose list all ask this question, and
    /// asking it in one place keeps them from disagreeing about the day's boundaries.
    static func doses(
        schedules: [DoseSchedule],
        medicationID: UUID,
        onDayOf day: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [ScheduledDose] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? day
        return doses(
            schedules: schedules,
            medicationID: medicationID,
            from: start,
            through: end,
            calendar: calendar
        )
    }

    /// How far a past slot may sit from the time a dose was logged against and
    /// still be that dose. A time-zone change moves every slot by the zone's
    /// offset while the logged time stays where it was, so a dose logged at
    /// 20:00 in New York reads as 01:00 the next day once the phone is in London.
    static let pastSlotTolerance: TimeInterval = 12 * 60 * 60

    /// The log that accounts for a scheduled dose, if one exists. A schedule
    /// yields at most one dose a day, so a log belongs to a slot when it names
    /// the same schedule on the same calendar day: the day, not the minute,
    /// because editing a time moves the slot and the logged dose must move with
    /// it, or Today offers it again and the supply is charged twice. A log that
    /// a time-zone change has carried onto the neighbouring day is still the
    /// same dose when it lies within half a day of the slot; that fallback is
    /// kept to past slots, because for today's slot the same geometry also
    /// describes yesterday's dose after a time edit of more than twelve hours,
    /// and today's dose must never read as taken when it was not. Every
    /// surface that asks "is this dose already logged" must ask here, or two of
    /// them will answer differently and log the same dose twice.
    static func loggedEvent(
        for dose: ScheduledDose,
        in doseEvents: [DoseEvent],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> DoseEvent? {
        let candidates = doseEvents.compactMap { event -> (DoseEvent, Date)? in
            guard event.scheduleID == dose.scheduleID, let scheduledAt = event.scheduledAt else { return nil }
            return (event, scheduledAt)
        }
        if let sameDay = candidates.first(where: { calendar.isDate($0.1, inSameDayAs: dose.date) }) {
            return sameDay.0
        }
        guard dose.date < calendar.startOfDay(for: now) else { return nil }
        return candidates.first { abs($0.1.timeIntervalSince(dose.date)) < pastSlotTolerance }?.0
    }

    static func loggedStatus(
        for dose: ScheduledDose,
        in doseEvents: [DoseEvent],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> DoseEventStatus? {
        loggedEvent(for: dose, in: doseEvents, now: now, calendar: calendar)?.status
    }

    /// The dose a "take it now" tap belongs to: the first dose of today that is
    /// already actionable — due or overdue — and has not been logged yet. Today
    /// offers exactly this set, so a tap on either screen claims the same dose.
    static func actionableDose(
        schedules: [DoseSchedule],
        medicationID: UUID,
        doseEvents: [DoseEvent],
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> ScheduledDose? {
        doses(schedules: schedules, medicationID: medicationID, onDayOf: now, calendar: calendar)
            .first {
                timingState(for: $0.date, now: now) != .upcoming &&
                loggedStatus(for: $0, in: doseEvents) == nil
            }
    }

    /// The scheduled dose a dose logged elsewhere belongs to: the slot on the same
    /// day nearest to the time it was meant for, when one lies within `tolerance`.
    /// Apple Health keeps its own schedule for a medication, and its times need
    /// not be this app's, so a Health dose meant for "8:00" claims this app's
    /// 8:30 slot and not a second, unscheduled dose beside it. Slot identity is
    /// answered here and nowhere else.
    static func nearestScheduledDose(
        to date: Date,
        schedules: [DoseSchedule],
        medicationID: UUID,
        tolerance: TimeInterval = 2 * 60 * 60,
        calendar: Calendar = .autoupdatingCurrent
    ) -> ScheduledDose? {
        doses(schedules: schedules, medicationID: medicationID, onDayOf: date, calendar: calendar)
            .filter { abs($0.date.timeIntervalSince(date)) <= tolerance }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// The amount to assume when a dose is logged outside any scheduled slot: the
    /// amount belonging to the schedule closest to this time of day. Reaching for
    /// the first schedule instead would always answer with the morning amount, so an
    /// evening dose of two tablets was recorded as one.
    static func nearestScheduledQuantity(
        schedules: [DoseSchedule],
        medicationID: UUID,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Double? {
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let minutesNow = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return schedules
            .filter { $0.medicationID == medicationID }
            .min {
                clockDistance($0.minutesAfterMidnight, minutesNow) <
                clockDistance($1.minutesAfterMidnight, minutesNow)
            }?
            .doseQuantity
    }

    /// Minutes between two times of day, measured the short way around the clock:
    /// 23:30 is thirty minutes from midnight, not twenty-three and a half hours.
    private static func clockDistance(_ lhs: Int, _ rhs: Int) -> Int {
        let day = 24 * 60
        let raw = abs(lhs - rhs) % day
        return min(raw, day - raw)
    }

    static func doses(
        schedules: [DoseSchedule],
        medicationID: UUID,
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [ScheduledDose] {
        guard startDate <= endDate else { return [] }
        var results: [ScheduledDose] = []
        var day = calendar.startOfDay(for: startDate)
        let lastDay = calendar.startOfDay(for: endDate)

        while day <= lastDay {
            for schedule in schedules where schedule.medicationID == medicationID {
                guard let date = scheduledDate(for: schedule, on: day, calendar: calendar),
                      date >= startDate,
                      date <= endDate else { continue }
                results.append(
                    ScheduledDose(
                        medicationID: medicationID,
                        scheduleID: schedule.id,
                        date: date,
                        quantity: schedule.doseQuantity
                    )
                )
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return results.sorted { $0.date < $1.date }
    }
}
