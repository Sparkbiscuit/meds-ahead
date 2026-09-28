import Foundation

/// A month of one medication's doses, day by day, as a calendar shows them:
/// what was scheduled, what was logged, and what that adds up to. Computed over
/// plain values so the picture a clinician reads can be checked without a screen.
struct AdherenceDay: Equatable, Identifiable {
    enum State: Equatable {
        /// Nothing was scheduled and nothing was logged.
        case none
        /// Every scheduled dose was taken (or, with no schedule, something was logged).
        case complete
        /// Some scheduled doses were taken or skipped, not all.
        case partial
        /// The day is past, doses were scheduled, and none was logged.
        case missed
        /// Doses are scheduled but the day has not come.
        case upcoming
        /// Every scheduled dose was skipped.
        case skipped
    }

    let date: Date
    let scheduled: Int
    let taken: Int
    let skipped: Int
    let state: State

    var id: Date { date }
}

enum AdherenceSummary {
    /// The days of the month containing `month`, first to last, with the doses
    /// of `medicationID` counted onto them. Unscheduled doses count as taken on
    /// the day they were logged; a day with no schedule and a logged dose reads
    /// as complete, because there was nothing to miss.
    static func month(
        containing month: Date,
        medicationID: UUID,
        schedules: [DoseSchedule],
        doseEvents: [DoseEvent],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [AdherenceDay] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let events = doseEvents.filter { $0.medicationID == medicationID }
        let today = calendar.startOfDay(for: now)
        var days: [AdherenceDay] = []
        var day = interval.start
        while day < interval.end {
            let scheduledDoses = ScheduleEngine.doses(schedules: schedules, medicationID: medicationID, onDayOf: day, calendar: calendar)
            var taken = 0
            var skipped = 0
            var counted: Set<UUID> = []
            for dose in scheduledDoses {
                guard let event = ScheduleEngine.loggedEvent(for: dose, in: events, now: now, calendar: calendar) else { continue }
                counted.insert(event.id)
                if event.status == .taken { taken += 1 } else { skipped += 1 }
            }
            // Doses logged outside any slot — Take Now, an as-needed dose, a
            // dose brought over from Health — belong to the day they were logged.
            for event in events where !counted.contains(event.id) && calendar.isDate(event.recordedAt, inSameDayAs: day) {
                if event.status == .taken { taken += 1 } else { skipped += 1 }
            }
            let scheduled = scheduledDoses.count
            let state: AdherenceDay.State
            if scheduled == 0 {
                state = taken + skipped == 0 ? .none : (taken > 0 ? .complete : .skipped)
            } else if day > today {
                state = taken + skipped == 0 ? .upcoming : .partial
            } else if taken >= scheduled {
                state = .complete
            } else if taken + skipped == 0 {
                state = day == today ? .upcoming : .missed
            } else if taken == 0, skipped >= scheduled {
                state = .skipped
            } else {
                state = .partial
            }
            days.append(AdherenceDay(date: day, scheduled: scheduled, taken: taken, skipped: skipped, state: state))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }
}
