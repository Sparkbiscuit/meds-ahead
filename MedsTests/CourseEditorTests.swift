import XCTest
@testable import Meds

/// The editor's Course ends control: the last day it saves, the days it
/// offers, and what its footer says.
final class CourseEditorTests: XCTestCase {
    private func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, in calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour)))
    }

    func testTheCourseEndIsNoneUntilTheToggleIsOn() throws {
        let newYork = try calendar("America/New_York")
        XCTAssertNil(MedicationEditorView.savedCourseEnd(courseEnds: false, lastDay: try date(20, 9, in: newYork), stored: nil, calendar: newYork))
        XCTAssertNil(MedicationEditorView.savedCourseEnd(courseEnds: false, lastDay: try date(20, 9, in: newYork),
                                                         stored: ScheduleEngine.normalizedEndDate(forDay: try date(20, 0, in: newYork), calendar: newYork),
                                                         calendar: newYork),
                     "turned off, the course becomes ongoing")
    }

    /// A newly picked day is stored at noon on that day, where a change of
    /// time zone of less than twelve hours cannot move it.
    func testANewlyPickedDayIsStoredAtNoon() throws {
        let newYork = try calendar("America/New_York")
        let picked = try date(20, 17, in: newYork)
        XCTAssertEqual(MedicationEditorView.savedCourseEnd(courseEnds: true, lastDay: picked, stored: nil, calendar: newYork), try date(20, 12, in: newYork))
        let stored = try date(18, 12, in: newYork)
        XCTAssertEqual(MedicationEditorView.savedCourseEnd(courseEnds: true, lastDay: picked, stored: stored, calendar: newYork), try date(20, 12, in: newYork),
                       "a different day replaces the stored one")
    }

    /// Chosen at home in New York, the last day is noon there, which Tokyo
    /// reads as one in the morning the next day. Saved from Tokyo with the
    /// day left alone, it must be the moment that was stored, not noon on
    /// the day Tokyo reads, or the course gains a day at home.
    func testADayLeftAsItWasKeepsTheStoredMomentAbroad() throws {
        let newYork = try calendar("America/New_York")
        let tokyo = try calendar("Asia/Tokyo")
        let stored = ScheduleEngine.normalizedEndDate(forDay: try date(20, 0, in: newYork), calendar: newYork)
        XCTAssertEqual(tokyo.component(.day, from: stored), 21, "why: abroad the stored noon reads as another day")

        XCTAssertEqual(MedicationEditorView.savedCourseEnd(courseEnds: true, lastDay: stored, stored: stored, calendar: tokyo), stored)
        let sameDayOtherTime = try XCTUnwrap(tokyo.date(bySettingHour: 18, minute: 0, second: 0, of: stored))
        XCTAssertEqual(MedicationEditorView.savedCourseEnd(courseEnds: true, lastDay: sameDayOtherTime, stored: stored, calendar: tokyo), stored,
                       "the picker may hand back another time on the same day")
        XCTAssertEqual(MedicationEditorView.savedCourseEnd(courseEnds: true, lastDay: stored, stored: stored, calendar: newYork), stored)
    }

    /// Today or later, except that a finished course's own last day stays
    /// on offer, so it loads as it was and saves back unchanged.
    func testThePickerOffersTodayOnOrAFinishedCoursesOwnLastDay() throws {
        let newYork = try calendar("America/New_York")
        let now = try date(12, 9, in: newYork)
        let today = try date(12, 0, in: newYork)
        XCTAssertEqual(MedicationEditorView.earliestCourseLastDay(stored: nil, now: now, calendar: newYork), today)
        XCTAssertEqual(MedicationEditorView.earliestCourseLastDay(stored: try date(20, 12, in: newYork), now: now, calendar: newYork), today)
        XCTAssertEqual(MedicationEditorView.earliestCourseLastDay(stored: try date(9, 12, in: newYork), now: now, calendar: newYork), try date(9, 0, in: newYork))
    }

    /// A day before today is saved only as a finished course's own last day,
    /// left as it was. The editor opened at 23:50 and saved at 00:05 keeps
    /// the day it opened on while the picker, whose range starts at today,
    /// shows today: saved, the new course would already be over, with not
    /// one reminder. A finished course's picker starts at its own last day,
    /// and a day between that and today would stretch the old course over
    /// days nobody was asked to take a dose on.
    func testADayBeforeTodayIsRefusedUnlessItIsTheStoredOne() throws {
        let newYork = try calendar("America/New_York")
        let opened = try date(25, 23, in: newYork).addingTimeInterval(50 * 60)
        let saved = try date(26, 0, in: newYork).addingTimeInterval(5 * 60)
        XCTAssertLessThan(opened, MedicationEditorView.earliestCourseLastDay(stored: nil, now: saved, calendar: newYork),
                          "why: the day kept is before the picker's range")
        XCTAssertEqual(MedicationEditorView.courseLastDayProblem(courseEnds: true, lastDay: opened, stored: nil, now: saved, calendar: newYork),
                       "Choose today or a later day for the course's last day.")
        XCTAssertNil(MedicationEditorView.courseLastDayProblem(courseEnds: true, lastDay: saved, stored: nil, now: saved, calendar: newYork), "today")
        XCTAssertNil(MedicationEditorView.courseLastDayProblem(courseEnds: true, lastDay: try date(30, 9, in: newYork), stored: nil, now: saved, calendar: newYork))
        XCTAssertNil(MedicationEditorView.courseLastDayProblem(courseEnds: false, lastDay: opened, stored: nil, now: saved, calendar: newYork),
                     "no course, no last day")

        let now = try date(12, 9, in: newYork)
        let finished = ScheduleEngine.normalizedEndDate(forDay: try date(9, 0, in: newYork), calendar: newYork)
        XCTAssertNil(MedicationEditorView.courseLastDayProblem(courseEnds: true, lastDay: finished, stored: finished, now: now, calendar: newYork),
                     "a finished course saved with its own last day stays finished")
        XCTAssertEqual(MedicationEditorView.courseLastDayProblem(courseEnds: true, lastDay: try date(11, 9, in: newYork), stored: finished, now: now, calendar: newYork),
                       "Choose today or a later day to start this course again, or \(ForecastEngine.dayText(finished, calendar: newYork)) to leave it finished.")
        XCTAssertNil(MedicationEditorView.courseLastDayProblem(courseEnds: true, lastDay: now, stored: finished, now: now, calendar: newYork),
                     "today starts it again")
        XCTAssertNil(MedicationEditorView.courseLastDayProblem(courseEnds: false, lastDay: try date(11, 9, in: newYork), stored: finished, now: now, calendar: newYork),
                     "no last day starts it again")

        let running = ScheduleEngine.normalizedEndDate(forDay: try date(20, 0, in: newYork), calendar: newYork)
        XCTAssertEqual(MedicationEditorView.courseLastDayProblem(courseEnds: true, lastDay: try date(11, 9, in: newYork), stored: running, now: now, calendar: newYork),
                       "Choose today or a later day for the course's last day.")
    }

    func testTheFooterSaysRemindersStopAfterTheLastDay() throws {
        let newYork = try calendar("America/New_York")
        let now = try date(12, 9, in: newYork)
        let base = "This schedule drives reminders and the supply forecast. Confirm it against the current label or clinician instructions. Half doses are fine — enter 2.5 for two and a half tablets."
        XCTAssertEqual(MedicationEditorView.scheduleFooter(courseEnds: false, storedCourseEnd: nil, now: now, calendar: newYork), base)
        XCTAssertEqual(MedicationEditorView.scheduleFooter(courseEnds: true, storedCourseEnd: nil, now: now, calendar: newYork),
                       base + " Reminders stop after the last day.")
        XCTAssertEqual(MedicationEditorView.scheduleFooter(courseEnds: true, storedCourseEnd: try date(12, 12, in: newYork), now: now, calendar: newYork),
                       base + " Reminders stop after the last day.", "a course ending today is still running")
        let finished = try date(9, 12, in: newYork)
        XCTAssertEqual(MedicationEditorView.scheduleFooter(courseEnds: true, storedCourseEnd: finished, now: now, calendar: newYork),
                       base + " Reminders stop after the last day. This course finished on \(ForecastEngine.dayText(finished, calendar: newYork)). Choosing today or a later day starts it again from today.")
        XCTAssertEqual(MedicationEditorView.scheduleFooter(courseEnds: false, storedCourseEnd: finished, now: now, calendar: newYork),
                       base + " This course finished on \(ForecastEngine.dayText(finished, calendar: newYork)). Saved without a last day, it starts again from today.")
        XCTAssertEqual(MedicationEditorView.scheduleFooter(courseEnds: false, storedCourseEnd: try date(20, 12, in: newYork), now: now, calendar: newYork), base)
    }
}
