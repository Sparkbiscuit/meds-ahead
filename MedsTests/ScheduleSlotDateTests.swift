import XCTest
@testable import Meds

/// The notification planner decides which days a schedule rings from plain
/// values. These pin that answer to the one Today gets from the model.
final class ScheduleSlotDateTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ calendar: Calendar, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func slot(_ schedule: DoseSchedule, on day: Date, calendar: Calendar) -> Date? {
        ScheduleEngine.slotDate(
            minutesAfterMidnight: schedule.minutesAfterMidnight,
            weekdayMask: schedule.weekdayMask,
            startDate: schedule.startDate,
            endDate: schedule.endDate,
            on: day,
            calendar: calendar
        )
    }

    func testTheStartDayTheEndDayAndTheFirstDayRule() {
        let gmt = calendar("GMT")
        // Saved at 15:00 on the 10th, ending on the 12th.
        let schedule = DoseSchedule(medicationID: UUID(), minutesAfterMidnight: 8 * 60,
                                    startDate: date(gmt, 9, 10, 15), endDate: date(gmt, 9, 12, 6))
        XCTAssertNil(slot(schedule, on: date(gmt, 9, 9, 12), calendar: gmt), "before the start day")
        XCTAssertNil(slot(schedule, on: date(gmt, 9, 10, 12), calendar: gmt), "08:00 had passed when it was saved")
        XCTAssertEqual(slot(schedule, on: date(gmt, 9, 11, 12), calendar: gmt), date(gmt, 9, 11, 8))
        XCTAssertEqual(slot(schedule, on: date(gmt, 9, 12, 23), calendar: gmt), date(gmt, 9, 12, 8), "the end day is included")
        XCTAssertNil(slot(schedule, on: date(gmt, 9, 13, 0), calendar: gmt), "the day after the end day")

        let evening = DoseSchedule(medicationID: UUID(), minutesAfterMidnight: 20 * 60, startDate: date(gmt, 9, 10, 15))
        XCTAssertEqual(slot(evening, on: date(gmt, 9, 10, 1), calendar: gmt), date(gmt, 9, 10, 20), "later that day it is a dose")

        let justLate = DoseSchedule(medicationID: UUID(), minutesAfterMidnight: 15 * 60, startDate: date(gmt, 9, 10, 15, 20))
        XCTAssertEqual(slot(justLate, on: date(gmt, 9, 10), calendar: gmt), date(gmt, 9, 10, 15), "still inside its due window")
    }

    func testWeekdayMasks() {
        let gmt = calendar("GMT")
        // 24 August 2026 is a Monday; bit 1 is Monday, bit 3 Wednesday.
        let schedule = DoseSchedule(medicationID: UUID(), minutesAfterMidnight: 9 * 60,
                                    weekdayMask: (1 << 1) | (1 << 3), startDate: date(gmt, 8, 1))
        let days = (24...30).filter { slot(schedule, on: date(gmt, 8, $0), calendar: gmt) != nil }
        XCTAssertEqual(days, [24, 26])
    }

    func testDaylightSavingDays() {
        let newYork = calendar("America/New_York")
        // 2:30 does not exist on 8 March; 1:30 happens twice on 1 November.
        let skipped = DoseSchedule(medicationID: UUID(), minutesAfterMidnight: 2 * 60 + 30, startDate: date(newYork, 3, 1))
        let moved = slot(skipped, on: date(newYork, 3, 8), calendar: newYork)
        XCTAssertEqual(moved, date(newYork, 3, 8, 3))
        let repeated = DoseSchedule(medicationID: UUID(), minutesAfterMidnight: 60 + 30, startDate: date(newYork, 10, 1))
        XCTAssertEqual(slot(repeated, on: date(newYork, 11, 1), calendar: newYork).map { newYork.component(.hour, from: $0) }, 1)
    }

    /// The rules as 1.1 wrote them, before the planner needed them from plain
    /// values, written out again here. `scheduledDate` now asks `slotDate`, so
    /// comparing the two would only check that one passes its values to the
    /// other; this is something to compare them with.
    private func dayRulesAsTheyWere(_ schedule: DoseSchedule, on day: Date, calendar: Calendar) -> Bool {
        let target = calendar.startOfDay(for: day)
        guard target >= calendar.startOfDay(for: schedule.startDate) else { return false }
        if let endDate = schedule.endDate, target > calendar.startOfDay(for: endDate) { return false }
        return schedule.weekdayMask & (1 << (calendar.component(.weekday, from: target) - 1)) != 0
    }

    private func rulesAsTheyWere(_ schedule: DoseSchedule, on day: Date, calendar: Calendar) -> Date? {
        let hour = schedule.minutesAfterMidnight / 60
        let minute = schedule.minutesAfterMidnight % 60
        guard dayRulesAsTheyWere(schedule, on: day, calendar: calendar),
              let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return nil }
        return date >= schedule.startDate.addingTimeInterval(-30 * 60) ? date : nil
    }

    /// The plain-values answer and the model's are the rules as they were,
    /// across every kind of day the rules treat differently.
    func testThePlainValuesAnswerIsTheModelsAnswer() {
        for zone in ["GMT", "America/New_York", "Australia/Lord_Howe"] {
            let calendar = calendar(zone)
            let schedules = [
                DoseSchedule(medicationID: UUID(), minutesAfterMidnight: 8 * 60, startDate: date(calendar, 3, 5, 15)),
                DoseSchedule(medicationID: UUID(), minutesAfterMidnight: 2 * 60 + 30, weekdayMask: 0b0101010,
                             startDate: date(calendar, 3, 1), endDate: date(calendar, 3, 12)),
                DoseSchedule(medicationID: UUID(), minutesAfterMidnight: 23 * 60 + 45, startDate: date(calendar, 3, 7, 23, 50)),
                DoseSchedule(medicationID: UUID(), minutesAfterMidnight: 60 + 30, weekdayMask: 0b1000001,
                             startDate: date(calendar, 10, 25), endDate: date(calendar, 11, 8)),
                DoseSchedule(medicationID: UUID(), minutesAfterMidnight: 12 * 60, startDate: date(calendar, 4, 5, 9), endDate: date(calendar, 4, 5, 1))
            ]
            var checked = 0
            for schedule in schedules {
                for month in [3, 4, 10, 11] {
                    for day in 1...14 {
                        let day = date(calendar, month, day, 12)
                        let expected = rulesAsTheyWere(schedule, on: day, calendar: calendar)
                        XCTAssertEqual(slot(schedule, on: day, calendar: calendar), expected, "\(zone) \(day)")
                        XCTAssertEqual(ScheduleEngine.scheduledDate(for: schedule, on: day, calendar: calendar), expected, "\(zone) \(day)")
                        XCTAssertEqual(ScheduleEngine.isActive(schedule, on: day, calendar: calendar),
                                       dayRulesAsTheyWere(schedule, on: day, calendar: calendar), "\(zone) \(day)")
                        if expected != nil { checked += 1 }
                    }
                }
            }
            XCTAssertGreaterThan(checked, 40, "the sweep found slots to compare in \(zone)")
        }
    }
}
