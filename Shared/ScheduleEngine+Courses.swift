import Foundation

/// Courses: a medication whose every schedule has a last day, the way the
/// antibiotics, antivirals and steroid courses in a discharge are written.
/// A schedule's `endDate` is the last day doses are taken, inclusive, and
/// `isActive` already honours it; these answer what the forecast and the
/// screens ask about the course as a whole, beside the engine that owns
/// which days hold a dose.
extension ScheduleEngine {
    /// The moment stored for a course's last day: noon, local, on that day.
    /// `isActive` reads only the day, in whatever zone the phone is in when
    /// it asks. A stored midnight reads as the day before as soon as the
    /// phone is anywhere west, and the last day's doses vanish from Today and
    /// the forecast; noon stays on the same calendar day for any change of
    /// less than twelve hours either way, so a family flying home from a
    /// transplant centre keeps the last day they were given.
    static func normalizedEndDate(forDay day: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: calendar.startOfDay(for: day)) ?? day
    }

    /// The last moment of the day a course ends, the same bound
    /// `doses(onDayOf:)` gives a day.
    static func courseLastMoment(_ end: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let start = calendar.startOfDay(for: end)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? end
    }

    /// The last day of a medication's course: the latest end among its
    /// schedules, and only when every one of them has an end. A schedule
    /// without one keeps the medication going, and a medication with no
    /// schedule is not on a course.
    static func courseEnd(schedules: [DoseSchedule], medicationID: UUID) -> Date? {
        let own = schedules.filter { $0.medicationID == medicationID }
        guard !own.isEmpty else { return nil }
        let ends = own.compactMap(\.endDate)
        guard ends.count == own.count else { return nil }
        return ends.max()
    }

    /// Whether the course's last day is before today. On its last day a
    /// course is still running, whatever the hour: an evening dose may be
    /// left.
    static func isCourseFinished(
        schedules: [DoseSchedule],
        medicationID: UUID,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard let end = courseEnd(schedules: schedules, medicationID: medicationID) else { return false }
        return calendar.startOfDay(for: end) < calendar.startOfDay(for: now)
    }

    /// How much the course still schedules from `now` through its last day;
    /// nil when the medication is not on a course. Asked through `doses`, so
    /// the first-day rule and the last-day rule are the ones Today follows.
    /// Logged doses are not subtracted: this is what the course asks for,
    /// not what the supply must still cover, which is the forecast's answer.
    static func remainingCourseQuantity(
        schedules: [DoseSchedule],
        medicationID: UUID,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Double? {
        guard let end = courseEnd(schedules: schedules, medicationID: medicationID) else { return nil }
        return doses(
            schedules: schedules,
            medicationID: medicationID,
            from: now,
            through: courseLastMoment(end, calendar: calendar),
            calendar: calendar
        )
        .reduce(0) { $0 + $1.quantity }
    }
}
