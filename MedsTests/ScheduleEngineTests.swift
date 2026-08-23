import XCTest
@testable import Meds

final class ScheduleEngineTests: XCTestCase {
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
