import XCTest
@testable import Meds

final class ScheduleEngineTests: XCTestCase {
    // MARK: - Slot identity

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func slot(_ schedule: DoseSchedule, day: Int, calendar: Calendar) throws -> ScheduledDose {
        let noon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 12)))
        return try XCTUnwrap(ScheduleEngine.doses(schedules: [schedule], medicationID: schedule.medicationID, onDayOf: noon, calendar: calendar).first)
    }

    func testALoggedDoseStaysLoggedAfterItsTimeIsEdited() throws {
        let calendar = calendar("GMT")
        let schedule = DoseSchedule(medicationID: UUID(), minutesAfterMidnight: 8 * 60, doseQuantity: 1,
                                    startDate: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))))
        let taken = try slot(schedule, day: 10, calendar: calendar)
        let logged = DoseEvent(medicationID: schedule.medicationID, scheduleID: schedule.id, scheduledAt: taken.date,
                               recordedAt: taken.date.addingTimeInterval(5 * 60), doseQuantity: 1, status: .taken)
        let now = taken.date.addingTimeInterval(4 * 60 * 60)

        // Morning to evening. (Past twelve hours, yesterday's slot would also
        // read as logged when it sits within half a day of today's dose: the
        // same distance a time-zone change produces, which the rule accepts
        // for past slots on purpose.)
        schedule.minutesAfterMidnight = 19 * 60
        XCTAssertEqual(ScheduleEngine.loggedStatus(for: try slot(schedule, day: 10, calendar: calendar), in: [logged], now: now, calendar: calendar), .taken,
                       "today's dose was taken, at the old time")
        XCTAssertNil(ScheduleEngine.loggedStatus(for: try slot(schedule, day: 9, calendar: calendar), in: [logged], now: now, calendar: calendar),
                     "yesterday's slot is not claimed by today's dose")
        XCTAssertNil(ScheduleEngine.loggedStatus(for: try slot(schedule, day: 11, calendar: calendar), in: [logged], now: now, calendar: calendar))
    }

    func testALoggedDoseStaysLoggedAfterATimeZoneChange() throws {
        let newYork = calendar("America/New_York")
        let london = calendar("Europe/London")
        let losAngeles = calendar("America/Los_Angeles")
        let schedule = DoseSchedule(medicationID: UUID(), minutesAfterMidnight: 20 * 60, doseQuantity: 1,
                                    startDate: try XCTUnwrap(newYork.date(from: DateComponents(year: 2026, month: 9, day: 1))))
        let taken = try slot(schedule, day: 10, calendar: newYork)
        let logged = DoseEvent(medicationID: schedule.medicationID, scheduleID: schedule.id, scheduledAt: taken.date,
                               recordedAt: taken.date, doseQuantity: 1, status: .taken)

        // Flying east: 20:00 in New York is 01:00 the next day in London, and the
        // phone now reads the 10th as a past day.
        let londonMorning = try XCTUnwrap(london.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 9)))
        let londonSlot = try slot(schedule, day: 10, calendar: london)
        XCTAssertFalse(london.isDate(taken.date, inSameDayAs: londonSlot.date), "the logged time crossed midnight")
        XCTAssertEqual(ScheduleEngine.loggedStatus(for: londonSlot, in: [logged], now: londonMorning, calendar: london), .taken)

        // Flying west the same evening: 20:00 in New York is 17:00 in Los Angeles,
        // still the 10th, and still today.
        let losAngelesEvening = try XCTUnwrap(losAngeles.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 21)))
        XCTAssertEqual(ScheduleEngine.loggedStatus(for: try slot(schedule, day: 10, calendar: losAngeles), in: [logged], now: losAngelesEvening, calendar: losAngeles), .taken)
        XCTAssertNil(ScheduleEngine.loggedStatus(for: try slot(schedule, day: 11, calendar: losAngeles), in: [logged], now: losAngelesEvening, calendar: losAngeles))
    }

    /// The fallback that absorbs a time-zone change is not applied to today's
    /// slot: the same distance also describes yesterday's dose after the time
    /// was moved by more than twelve hours, and a dose must never read as taken
    /// today when it was not.
    func testYesterdaysDoseNeverStandsInForTodays() throws {
        let calendar = calendar("GMT")
        let schedule = DoseSchedule(medicationID: UUID(), minutesAfterMidnight: 22 * 60, doseQuantity: 1,
                                    startDate: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))))
        let yesterday = try slot(schedule, day: 9, calendar: calendar)
        let logged = DoseEvent(medicationID: schedule.medicationID, scheduleID: schedule.id, scheduledAt: yesterday.date,
                               recordedAt: yesterday.date, doseQuantity: 1, status: .taken)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 8)))

        schedule.minutesAfterMidnight = 9 * 60
        XCTAssertNil(ScheduleEngine.loggedStatus(for: try slot(schedule, day: 10, calendar: calendar), in: [logged], now: now, calendar: calendar))
        XCTAssertEqual(ScheduleEngine.loggedStatus(for: try slot(schedule, day: 9, calendar: calendar), in: [logged], now: now, calendar: calendar), .taken)
    }

    // MARK: - First day

    private func gmt(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar("GMT").date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func hours(_ doses: [ScheduledDose]) -> [Int] {
        doses.map { calendar("GMT").component(.hour, from: $0.date) }
    }

    private func morningAndEvening(startingAt start: Date) -> [DoseSchedule] {
        let medicationID = UUID()
        return [
            DoseSchedule(medicationID: medicationID, minutesAfterMidnight: 8 * 60, doseQuantity: 1, startDate: start),
            DoseSchedule(medicationID: medicationID, minutesAfterMidnight: 20 * 60, doseQuantity: 1, startDate: start)
        ]
    }

    /// A medication added at 15:00 was never due at 08:00 that day: offered
    /// anyway, it read as overdue and "Mark all due" charged the new count.
    func testATimeThatPassedBeforeTheScheduleExistedIsNoDose() {
        let calendar = calendar("GMT")
        let schedules = morningAndEvening(startingAt: gmt(10, 15))
        let medicationID = schedules[0].medicationID

        let today = ScheduleEngine.doses(schedules: schedules, medicationID: medicationID, onDayOf: gmt(10, 16), calendar: calendar)
        XCTAssertEqual(hours(today), [20])
        XCTAssertNil(ScheduleEngine.scheduledDate(for: schedules[0], on: gmt(10, 12), calendar: calendar))
        XCTAssertNil(
            ScheduleEngine.actionableDose(schedules: schedules, medicationID: medicationID, doseEvents: [], now: gmt(10, 16), calendar: calendar),
            "nothing is due or overdue on the afternoon it was added"
        )

        let tomorrow = ScheduleEngine.doses(schedules: schedules, medicationID: medicationID, onDayOf: gmt(11, 12), calendar: calendar)
        XCTAssertEqual(hours(tomorrow), [8, 20])
    }

    /// Ten minutes past a dose's time it is still due, so a medication added
    /// then keeps it; past the due window it does not.
    func testADoseStillInsideItsDueWindowIsOffered() {
        let calendar = calendar("GMT")
        let justAfter = morningAndEvening(startingAt: gmt(10, 8, 10))
        XCTAssertEqual(hours(ScheduleEngine.doses(schedules: justAfter, medicationID: justAfter[0].medicationID, onDayOf: gmt(10, 12), calendar: calendar)), [8, 20])
        let claimed = ScheduleEngine.actionableDose(schedules: justAfter, medicationID: justAfter[0].medicationID, doseEvents: [], now: gmt(10, 8, 10), calendar: calendar)
        XCTAssertEqual(claimed?.scheduleID, justAfter[0].id)

        let atTheEdge = morningAndEvening(startingAt: gmt(10, 8, 30))
        XCTAssertEqual(hours(ScheduleEngine.doses(schedules: atTheEdge, medicationID: atTheEdge[0].medicationID, onDayOf: gmt(10, 12), calendar: calendar)), [8, 20])

        let pastIt = morningAndEvening(startingAt: gmt(10, 8, 31))
        XCTAssertEqual(hours(ScheduleEngine.doses(schedules: pastIt, medicationID: pastIt[0].medicationID, onDayOf: gmt(10, 12), calendar: calendar)), [20])
    }

    /// A time added to a medication already on a schedule starts when it is
    /// saved; the times that were already there keep their days.
    func testATimeAddedLaterStartsWhenItIsSaved() {
        let calendar = calendar("GMT")
        var schedules = morningAndEvening(startingAt: gmt(1, 9))
        let medicationID = schedules[0].medicationID
        schedules.append(DoseSchedule(medicationID: medicationID, minutesAfterMidnight: 14 * 60, doseQuantity: 1, startDate: gmt(10, 16)))

        XCTAssertEqual(hours(ScheduleEngine.doses(schedules: schedules, medicationID: medicationID, onDayOf: gmt(10, 17), calendar: calendar)), [8, 20])
        XCTAssertEqual(hours(ScheduleEngine.doses(schedules: schedules, medicationID: medicationID, onDayOf: gmt(11, 12), calendar: calendar)), [8, 14, 20])
        XCTAssertEqual(hours(ScheduleEngine.doses(schedules: schedules, medicationID: medicationID, onDayOf: gmt(5, 12), calendar: calendar)), [8, 20])
    }

    /// The next morning's missed-dose list reads the two days before today, and
    /// must not ask about a dose from before the medication was added.
    func testTheMissedDoseWindowListsNothingFromBeforeTheScheduleExisted() {
        let calendar = calendar("GMT")
        let schedules = morningAndEvening(startingAt: gmt(10, 15))
        let startOfToday = calendar.startOfDay(for: gmt(11, 9))
        let window = ScheduleEngine.doses(
            schedules: schedules,
            medicationID: schedules[0].medicationID,
            from: calendar.date(byAdding: .day, value: -2, to: startOfToday)!,
            through: startOfToday.addingTimeInterval(-1),
            calendar: calendar
        )
        XCTAssertEqual(window.map(\.date), [gmt(10, 20)])
    }

    /// The rule hides slots; it never rewrites the ledger. A dose already
    /// logged against a slot the rule now hides stays logged and stays charged.
    func testHidingASlotLeavesTheLedgerAlone() {
        let calendar = calendar("GMT")
        let schedules = morningAndEvening(startingAt: gmt(10, 15))
        let medicationID = schedules[0].medicationID
        let opening = InventoryEvent(medicationID: medicationID, date: gmt(10, 15), delta: 30, reason: .openingCount)
        let loggedEarlier = DoseEvent(medicationID: medicationID, scheduleID: schedules[0].id, scheduledAt: gmt(10, 8),
                                      recordedAt: gmt(10, 15, 5), doseQuantity: 1, status: .taken)
        let events = [loggedEarlier]

        XCTAssertEqual(hours(ScheduleEngine.doses(schedules: schedules, medicationID: medicationID, onDayOf: gmt(10, 16), calendar: calendar)), [20])
        XCTAssertEqual(events.map(\.id), [loggedEarlier.id])
        XCTAssertEqual(loggedEarlier.scheduledAt, gmt(10, 8))
        XCTAssertEqual(ForecastEngine.rawSupplyBalance(medicationID: medicationID, inventoryEvents: [opening], doseEvents: events), 29)
    }

    /// Editing a time keeps the schedule and its start date, so only the first
    /// day is judged against the moment it was saved; every day since keeps
    /// its slot at the new time.
    func testAnEditedTimeKeepsItsPastDays() {
        let calendar = calendar("GMT")
        let schedule = DoseSchedule(medicationID: UUID(), minutesAfterMidnight: 20 * 60, doseQuantity: 1, startDate: gmt(1, 15))
        schedule.minutesAfterMidnight = 7 * 60

        let history = ScheduleEngine.doses(schedules: [schedule], medicationID: schedule.medicationID, from: gmt(1, 0), through: gmt(10, 23), calendar: calendar)
        XCTAssertEqual(history.count, 9, "the 2nd through the 10th; 07:00 on the 1st was before the schedule existed")
        XCTAssertEqual(history.first?.date, gmt(2, 7))
        XCTAssertEqual(history.last?.date, gmt(10, 7))
    }

    func testDoseTimingStateBoundaries() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(
            ScheduleEngine.timingState(for: now.addingTimeInterval(31 * 60), now: now),
            .upcoming
        )
        XCTAssertEqual(
            ScheduleEngine.timingState(for: now.addingTimeInterval(30 * 60), now: now),
            .due
        )
        XCTAssertEqual(
            ScheduleEngine.timingState(for: now.addingTimeInterval(-30 * 60), now: now),
            .due
        )
        XCTAssertEqual(
            ScheduleEngine.timingState(for: now.addingTimeInterval(-31 * 60), now: now),
            .overdue
        )
    }

    func testWeekdayMaskOnlyCreatesSelectedDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 24)))
        let medicationID = UUID()
        let mondayBit = 1 << 1
        let schedule = DoseSchedule(
            medicationID: medicationID,
            minutesAfterMidnight: 9 * 60,
            weekdayMask: mondayBit,
            startDate: monday
        )
        let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 13, to: monday))

        let doses = ScheduleEngine.doses(
            schedules: [schedule],
            medicationID: medicationID,
            from: monday,
            through: end,
            calendar: calendar
        )

        XCTAssertEqual(doses.count, 2)
        XCTAssertTrue(doses.allSatisfy { calendar.component(.weekday, from: $0.date) == 2 })
    }

    func testScheduleHonorsEndDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: start))
        let medicationID = UUID()
        let schedule = DoseSchedule(
            medicationID: medicationID,
            minutesAfterMidnight: 12 * 60,
            startDate: start,
            endDate: end
        )

        let horizon = try XCTUnwrap(calendar.date(byAdding: .day, value: 10, to: start))
        let doses = ScheduleEngine.doses(
            schedules: [schedule],
            medicationID: medicationID,
            from: start,
            through: horizon,
            calendar: calendar
        )
        XCTAssertEqual(doses.count, 3)
    }

    func testDailyScheduleProducesOneDosePerDayAcrossSpringForward() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 6))
        )
        let end = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 23, minute: 59))
        )
        let medicationID = UUID()
        let schedule = DoseSchedule(
            medicationID: medicationID,
            minutesAfterMidnight: 9 * 60,
            startDate: start
        )

        let doses = ScheduleEngine.doses(
            schedules: [schedule],
            medicationID: medicationID,
            from: start,
            through: end,
            calendar: calendar
        )

        XCTAssertEqual(doses.count, 6)
        XCTAssertEqual(Set(doses.map { calendar.ordinality(of: .day, in: .year, for: $0.date) }).count, 6)
        XCTAssertTrue(doses.allSatisfy { calendar.component(.hour, from: $0.date) == 9 })
    }

    /// Health keeps its own reminder times; the slot a Health dose belongs to is
    /// the nearest one on that day, within tolerance, and none when none is near.
    func testNearestScheduledDoseClaimsTheSlotWithinTolerance() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 10)))
        let medicationID = UUID()
        let schedules = [
            DoseSchedule(medicationID: medicationID, minutesAfterMidnight: 8 * 60 + 30, doseQuantity: 1, startDate: day),
            DoseSchedule(medicationID: medicationID, minutesAfterMidnight: 20 * 60, doseQuantity: 2, startDate: day)
        ]
        let eight = try XCTUnwrap(calendar.date(byAdding: .hour, value: 8, to: day))
        let claimed = try XCTUnwrap(ScheduleEngine.nearestScheduledDose(to: eight, schedules: schedules, medicationID: medicationID, calendar: calendar))
        XCTAssertEqual(claimed.scheduleID, schedules[0].id)

        let two = try XCTUnwrap(calendar.date(byAdding: .hour, value: 14, to: day))
        XCTAssertNil(ScheduleEngine.nearestScheduledDose(to: two, schedules: schedules, medicationID: medicationID, calendar: calendar))
        XCTAssertNotNil(ScheduleEngine.nearestScheduledDose(to: two, schedules: schedules, medicationID: medicationID, tolerance: 6 * 60 * 60, calendar: calendar))
        XCTAssertNil(ScheduleEngine.nearestScheduledDose(to: eight, schedules: schedules, medicationID: UUID(), calendar: calendar))
    }

    func testNonexistentSpringForwardTimeMovesToNextValidTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let springForwardDay = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))
        )
        let medicationID = UUID()
        let schedule = DoseSchedule(
            medicationID: medicationID,
            minutesAfterMidnight: 2 * 60 + 30,
            startDate: springForwardDay
        )

        let scheduled = try XCTUnwrap(
            ScheduleEngine.scheduledDate(for: schedule, on: springForwardDay, calendar: calendar)
        )

        XCTAssertEqual(calendar.component(.day, from: scheduled), 8)
        XCTAssertEqual(calendar.component(.hour, from: scheduled), 3)
        XCTAssertEqual(calendar.component(.minute, from: scheduled), 0)
    }
}
