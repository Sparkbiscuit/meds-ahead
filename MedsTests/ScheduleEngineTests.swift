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
}
