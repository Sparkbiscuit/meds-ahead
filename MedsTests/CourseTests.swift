import XCTest
@testable import Meds

/// Short courses beside lifelong medications: when a course ends, what it
/// still asks for, and what the forecast says once the supply outlasts it.
final class CourseTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func september(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func lastDay(_ day: Int) -> Date {
        ScheduleEngine.normalizedEndDate(forDay: september(day, 0), calendar: calendar)
    }

    /// A tablet at 08:00 and at 20:00 from 07:00 on September 1st, through
    /// the last day given.
    private func twiceDailyCourse(count: Double, through end: Int?, form: MedicationForm = .tablet)
        -> (Medication, [DoseSchedule], InventoryEvent) {
        let medication = Medication(name: "Amoxicillin", form: form, createdAt: september(1, 7))
        let schedules = [8, 20].map {
            DoseSchedule(medicationID: medication.id, minutesAfterMidnight: $0 * 60, doseQuantity: 1,
                         startDate: september(1, 7), endDate: end.map(lastDay))
        }
        return (medication, schedules, InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: count, reason: .openingCount))
    }

    private func logged(_ schedule: DoseSchedule, on day: Int) -> DoseEvent {
        let date = september(day, schedule.minutesAfterMidnight / 60)
        return DoseEvent(medicationID: schedule.medicationID, scheduleID: schedule.id, scheduledAt: date, recordedAt: date,
                         doseQuantity: schedule.doseQuantity, status: .taken)
    }

    private func forecast(_ medication: Medication, _ schedules: [DoseSchedule], _ inventory: [InventoryEvent],
                          _ doses: [DoseEvent] = [], now: Date) -> SupplyForecast {
        ForecastEngine.forecast(medication: medication, schedules: schedules, inventoryEvents: inventory, doseEvents: doses, now: now, calendar: calendar)
    }

    // MARK: - The last day

    /// Stored at midnight, a last day chosen in New York reads as the day
    /// before in Los Angeles, and the course loses its final doses. Noon
    /// holds the same day anywhere less than twelve hours away.
    func testTheLastDayStaysTheSameDayAcrossATimeZoneChange() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let chosen = try XCTUnwrap(newYork.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 23, minute: 40)))
        let end = ScheduleEngine.normalizedEndDate(forDay: chosen, calendar: newYork)
        XCTAssertEqual(end, newYork.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 12)))

        let medication = Medication(name: "Valganciclovir")
        let schedule = DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 9 * 60,
                                    startDate: try XCTUnwrap(newYork.date(from: DateComponents(year: 2026, month: 9, day: 1))), endDate: end)
        for zone in ["America/New_York", "America/Los_Angeles", "Pacific/Honolulu", "Europe/London", "Asia/Kolkata"] {
            var away = Calendar(identifier: .gregorian)
            away.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
            let tenth = try XCTUnwrap(away.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 6)))
            let eleventh = try XCTUnwrap(away.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 6)))
            XCTAssertEqual(away.component(.day, from: end), 10, zone)
            XCTAssertEqual(ScheduleEngine.doses(schedules: [schedule], medicationID: medication.id, onDayOf: tenth, calendar: away).count, 1,
                           "\(zone): the last day still holds its dose")
            XCTAssertTrue(ScheduleEngine.doses(schedules: [schedule], medicationID: medication.id, onDayOf: eleventh, calendar: away).isEmpty, zone)
        }

        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let midnight = newYork.startOfDay(for: chosen)
        XCTAssertEqual(losAngeles.component(.day, from: midnight), 9, "why not midnight: the last day moves a day earlier")
    }

    func testACourseEndsOnlyWhenEverySchedulesEnds() {
        let medication = Medication(name: "Prednisone")
        let morning = DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, startDate: september(1, 7), endDate: lastDay(10))
        let evening = DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 20 * 60, startDate: september(1, 7), endDate: lastDay(12))
        let ongoing = DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 14 * 60, startDate: september(1, 7))
        let otherMedication = DoseSchedule(medicationID: UUID(), minutesAfterMidnight: 9 * 60, startDate: september(1, 7))

        XCTAssertEqual(ScheduleEngine.courseEnd(schedules: [morning, evening, otherMedication], medicationID: medication.id), lastDay(12), "the latest end")
        XCTAssertNil(ScheduleEngine.courseEnd(schedules: [morning, ongoing], medicationID: medication.id), "one schedule without an end keeps it going")
        XCTAssertNil(ScheduleEngine.courseEnd(schedules: [otherMedication], medicationID: medication.id), "no schedule, no course")

        XCTAssertFalse(ScheduleEngine.isCourseFinished(schedules: [morning, evening], medicationID: medication.id, now: september(12, 23, 59), calendar: calendar),
                       "still running all through its last day")
        XCTAssertTrue(ScheduleEngine.isCourseFinished(schedules: [morning, evening], medicationID: medication.id, now: september(13, 0, 1), calendar: calendar))
        XCTAssertFalse(ScheduleEngine.isCourseFinished(schedules: [morning, ongoing], medicationID: medication.id, now: september(30), calendar: calendar))
    }

    /// What the course still asks for runs through the last day's evening,
    /// and never includes a morning the first-day rule hid.
    func testTheRemainingCourseFollowsTheFirstDayAndLastDayRules() {
        let (medication, schedules, _) = twiceDailyCourse(count: 20, through: 10)
        XCTAssertEqual(ScheduleEngine.remainingCourseQuantity(schedules: schedules, medicationID: medication.id, now: september(10, 12), calendar: calendar), 1,
                       "the last day's evening")
        XCTAssertEqual(ScheduleEngine.remainingCourseQuantity(schedules: schedules, medicationID: medication.id, now: september(9, 7), calendar: calendar), 4)
        XCTAssertEqual(ScheduleEngine.remainingCourseQuantity(schedules: schedules, medicationID: medication.id, now: september(11, 7), calendar: calendar), 0)

        let addedAtNoon = DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, startDate: september(1, 12), endDate: lastDay(3))
        XCTAssertEqual(ScheduleEngine.remainingCourseQuantity(schedules: [addedAtNoon], medicationID: medication.id, now: september(1, 12), calendar: calendar), 2,
                       "the 2nd and the 3rd; the 1st's morning had passed when it was added")
        XCTAssertNil(ScheduleEngine.remainingCourseQuantity(schedules: [DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60)],
                                                            medicationID: medication.id, now: september(1), calendar: calendar))
    }
}
