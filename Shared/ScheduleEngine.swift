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
    /// How long either side of its time a dose counts as due rather than
    /// upcoming or overdue. The first-day rule in `scheduledDate` measures from
    /// the same window, so a dose Today would call due is never one it hides.
    static let dueWindow: TimeInterval = 30 * 60

    static func timingState(
        for scheduledAt: Date,
        now: Date = .now,
        dueWindow: TimeInterval = ScheduleEngine.dueWindow
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
        slotDate(
            minutesAfterMidnight: schedule.minutesAfterMidnight,
            weekdayMask: schedule.weekdayMask,
            startDate: schedule.startDate,
            endDate: schedule.endDate,
            on: day,
            calendar: calendar
        )
    }

    /// The same answer from a schedule's plain values. The notification
    /// planner works from copies taken off the store, and the days a reminder
    /// rings must be the days Today offers a dose, so both ask here.
    static func slotDate(
        minutesAfterMidnight: Int,
        weekdayMask: Int,
        startDate: Date,
        endDate: Date?,
        on day: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        let target = calendar.startOfDay(for: day)
        guard target >= calendar.startOfDay(for: startDate) else { return nil }
        if let endDate, target > calendar.startOfDay(for: endDate) { return nil }
        let weekday = calendar.component(.weekday, from: target) - 1
        guard weekdayMask & (1 << weekday) != 0 else { return nil }
        let hour = minutesAfterMidnight / 60
        let minute = minutesAfterMidnight % 60
        guard let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return nil }
        // A time already past when the schedule was saved was never a dose this
        // app asked for: offered anyway, a medication added at 15:00 showed its
        // 08:00 dose overdue, "Mark all due" charged it to the count just entered,
        // and the next morning asked whether it was missed. One still inside its
        // due window stays, since Today would call it due. Only the start day can
        // bind, and an edited time keeps its schedule's start date, so the days
        // before the edit keep their slots.
        guard date >= startDate.addingTimeInterval(-dueWindow) else { return nil }
        return date
    }

    /// Whether the schedule still has a dose at exactly this moment. A time
    /// drawn earlier, by a widget, may since have been edited, ended, or
    /// fallen before the schedule's first day; logging it anyway would record
    /// a dose at a time, or on a day, that no screen offers.
    static func hasSlot(
        _ schedule: DoseSchedule,
        at date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        scheduledDate(for: schedule, on: calendar.startOfDay(for: date), calendar: calendar) == date
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

    /// How far from a slot a dose logged outside it may lie and still be that
    /// slot's dose.
    static let nearbySlotTolerance: TimeInterval = 2 * 60 * 60

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
        tolerance: TimeInterval = nearbySlotTolerance,
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

    /// A medication's dose logs, filed for `unloggedDoses`. A forecast asks
    /// about every dose since the last count, which can be years of them, and
    /// `loggedEvent` reads every log it is handed once per dose. A log accounts
    /// only for a dose on its own day or, within `pastSlotTolerance`, on a
    /// neighbouring one, so logs naming a slot are filed by schedule and day,
    /// and the rest by day. File them with the calendar the doses are asked
    /// about in.
    struct DoseLogIndex {
        fileprivate var named: [UUID: [Date: [DoseEvent]]] = [:]
        fileprivate var outside: [Date: [DoseEvent]] = [:]

        init(doseEvents: [DoseEvent], medicationID: UUID, calendar: Calendar = .autoupdatingCurrent) {
            for event in doseEvents where event.medicationID == medicationID {
                if let scheduleID = event.scheduleID {
                    guard let scheduledAt = event.scheduledAt else { continue }
                    named[scheduleID, default: [:]][calendar.startOfDay(for: scheduledAt), default: []].append(event)
                } else {
                    outside[calendar.startOfDay(for: event.recordedAt), default: []].append(event)
                }
            }
        }
    }

    /// The doses from `startDate` through `endDate` that no log accounts for,
    /// in time order. A log naming a schedule accounts for the dose
    /// `loggedEvent` says it does, taken or skipped. A log outside every slot
    /// (Take Now with nothing due, or a Health dose no slot was near) accounts
    /// for the unlogged dose nearest it on its own day when one lies within
    /// `nearbySlotTolerance`, and for one dose at most: within reach it is that
    /// dose taken early or late, but hours from any slot it is as likely an
    /// extra one, and a late first dose on the day a medication was added
    /// belongs to a slot that day never offered. The pairing is made over the
    /// whole day, not the range asked about, so asking in pieces gives the same
    /// answer as asking once. The caller chooses which outside-slot logs count.
    static func unloggedDoses(
        schedules: [DoseSchedule],
        medicationID: UUID,
        from startDate: Date,
        through endDate: Date,
        doseEvents: [DoseEvent],
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [ScheduledDose] {
        unloggedDoses(
            schedules: schedules,
            medicationID: medicationID,
            from: startDate,
            through: endDate,
            logs: DoseLogIndex(doseEvents: doseEvents, medicationID: medicationID, calendar: calendar),
            now: now,
            calendar: calendar
        )
    }

    /// The same, from logs already filed, for a caller asking about more than
    /// one range of the same medication.
    static func unloggedDoses(
        schedules: [DoseSchedule],
        medicationID: UUID,
        from startDate: Date,
        through endDate: Date,
        logs: DoseLogIndex,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [ScheduledDose] {
        guard startDate <= endDate else { return [] }
        let own = schedules.filter { $0.medicationID == medicationID }
        guard !own.isEmpty else { return [] }

        var results: [ScheduledDose] = []
        var previous = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: startDate) ?? startDate)
        var day = calendar.startOfDay(for: startDate)
        let lastDay = calendar.startOfDay(for: endDate)
        while day <= lastDay {
            guard let following = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let next = calendar.startOfDay(for: following)
            var unlogged = own.compactMap { schedule -> ScheduledDose? in
                // A log on the dose's own day accounts for it, so its time is
                // never worked out; that is most of the doses in a logged history.
                let named = logs.named[schedule.id]
                guard named?[day] == nil,
                      let date = scheduledDate(for: schedule, on: day, calendar: calendar) else { return nil }
                let dose = ScheduledDose(medicationID: medicationID, scheduleID: schedule.id, date: date, quantity: schedule.doseQuantity)
                if let named, loggedEvent(for: dose, in: (named[previous] ?? []) + (named[next] ?? []), now: now, calendar: calendar) != nil {
                    return nil
                }
                return dose
            }
            for event in (logs.outside[day] ?? []).sorted(by: { $0.recordedAt < $1.recordedAt }) {
                let distance = { (dose: ScheduledDose) in abs(dose.date.timeIntervalSince(event.recordedAt)) }
                guard let nearest = unlogged.indices
                    .filter({ distance(unlogged[$0]) <= nearbySlotTolerance })
                    .min(by: { distance(unlogged[$0]) < distance(unlogged[$1]) }) else { continue }
                unlogged.remove(at: nearest)
            }
            results += unlogged.filter { $0.date >= startDate && $0.date <= endDate }
            previous = day
            day = next
        }
        return results.sorted { $0.date < $1.date }
    }
}
