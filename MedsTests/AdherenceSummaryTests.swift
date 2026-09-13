import XCTest
@testable import Meds

/// The month view a clinician reads, over plain values.
final class AdherenceSummaryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 8, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    func testADailyScheduleReadsDayByDay() throws {
        let medicationID = UUID()
        let schedule = DoseSchedule(medicationID: medicationID, minutesAfterMidnight: 8 * 60, doseQuantity: 1, startDate: date(1, 0))
        let slot = { (d: Int) in ScheduleEngine.doses(schedules: [schedule], medicationID: medicationID, onDayOf: self.date(d), calendar: self.calendar).first! }
        let events = [
            DoseEvent(medicationID: medicationID, scheduleID: schedule.id, scheduledAt: slot(1).date, recordedAt: date(1, 8, 5), doseQuantity: 1, status: .taken),
            DoseEvent(medicationID: medicationID, scheduleID: schedule.id, scheduledAt: slot(2).date, recordedAt: date(2, 8, 5), doseQuantity: 1, status: .skipped),
            // Sep 3: nothing logged, so missed.
            DoseEvent(medicationID: medicationID, scheduleID: schedule.id, scheduledAt: slot(4).date, recordedAt: date(4, 8), doseQuantity: 1, status: .taken),
            DoseEvent(medicationID: medicationID, recordedAt: date(4, 15), doseQuantity: 1, status: .taken),
            // Sep 5: an unscheduled dose only, which stands in for the slot.
            DoseEvent(medicationID: medicationID, recordedAt: date(5, 15), doseQuantity: 1, status: .taken),
            DoseEvent(medicationID: UUID(), scheduleID: schedule.id, scheduledAt: slot(6).date, recordedAt: date(6, 8), doseQuantity: 1, status: .taken)
        ]

        let days = AdherenceSummary.month(containing: date(12), medicationID: medicationID, schedules: [schedule], doseEvents: events, now: date(12, 12), calendar: calendar)

        XCTAssertEqual(days.count, 30)
        XCTAssertEqual(days[0].state, .complete)
        XCTAssertEqual(days[1].state, .skipped)
        XCTAssertEqual(days[2].state, .missed)
        XCTAssertEqual(days[3].state, .complete)
        XCTAssertEqual(days[3].taken, 2, "the extra dose is counted, not hidden")
        XCTAssertEqual(days[4].state, .complete)
        XCTAssertEqual(days[5].state, .missed, "another medication's dose is not this one's")
        XCTAssertEqual(days[11].state, .upcoming, "today, with the 8:00 slot unlogged, is not yet a miss")
        XCTAssertEqual(days[12].state, .upcoming)
        XCTAssertEqual(days[29].scheduled, 1)
    }

    func testAnAsNeededMedicationShowsOnlyWhatWasLogged() {
        let medicationID = UUID()
        let events = [
            DoseEvent(medicationID: medicationID, recordedAt: date(7, 21), doseQuantity: 1, status: .taken),
            DoseEvent(medicationID: medicationID, recordedAt: date(9, 21), doseQuantity: 1, status: .skipped)
        ]
        let days = AdherenceSummary.month(containing: date(12), medicationID: medicationID, schedules: [], doseEvents: events, now: date(12, 12), calendar: calendar)
        XCTAssertEqual(days[6].state, .complete)
        XCTAssertEqual(days[8].state, .skipped)
        XCTAssertEqual(days[0].state, .none)
        XCTAssertEqual(days[20].state, .none)
    }

    func testAScheduleThatStartsMidMonthLeavesEarlierDaysBlank() {
        let medicationID = UUID()
        let schedule = DoseSchedule(medicationID: medicationID, minutesAfterMidnight: 20 * 60, doseQuantity: 1, startDate: date(10, 0))
        let days = AdherenceSummary.month(containing: date(12), medicationID: medicationID, schedules: [schedule], doseEvents: [], now: date(12, 12), calendar: calendar)
        XCTAssertEqual(days[8].state, .none)
        XCTAssertEqual(days[9].state, .missed)
        XCTAssertEqual(days[10].state, .missed)
    }
}
