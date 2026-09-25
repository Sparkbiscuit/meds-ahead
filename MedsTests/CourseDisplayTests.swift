import SwiftData
import SwiftUI
import XCTest
@testable import Meds

/// What each screen says about a course: the detail screen, Supply, Today,
/// the printed list and the runs-out widget. A tablet at 08:00 and 20:00
/// from 07:00 on Tuesday 1 September 2026, looked at on the morning of the
/// 12th, in GMT.
final class CourseDisplayTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func september(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    private func lastDay(_ day: Int) -> Date {
        ScheduleEngine.normalizedEndDate(forDay: september(day, 0), calendar: calendar)
    }

    private var now: Date { september(12, 9) }

    private struct Course {
        let medication: Medication
        let schedules: [DoseSchedule]
        let inventory: [InventoryEvent]
        let doses: [DoseEvent]
    }

    /// Counted at the start, and every dose logged up to `loggedThrough`.
    private func course(_ name: String = "Amoxicillin", count: Double, through end: Int?, loggedThrough: Date? = nil) -> Course {
        let medication = Medication(name: name, createdAt: september(1, 7))
        let schedules = [8, 20].map {
            DoseSchedule(medicationID: medication.id, minutesAfterMidnight: $0 * 60, doseQuantity: 1, startDate: september(1, 7),
                         endDate: end.map(lastDay))
        }
        let opening = InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: count, reason: .openingCount)
        let logged = loggedThrough.map { through in
            ScheduleEngine.doses(schedules: schedules, medicationID: medication.id, from: september(1, 0), through: through, calendar: calendar).map {
                DoseEvent(medicationID: medication.id, scheduleID: $0.scheduleID, scheduledAt: $0.date, recordedAt: $0.date, doseQuantity: 1, status: .taken)
            }
        } ?? []
        return Course(medication: medication, schedules: schedules, inventory: [opening], doses: logged)
    }

    private func forecast(_ course: Course, now: Date? = nil) -> SupplyForecast {
        ForecastEngine.forecast(medication: course.medication, schedules: course.schedules, inventoryEvents: course.inventory,
                                doseEvents: course.doses, now: now ?? self.now, calendar: calendar)
    }

    /// Ended on the 9th with every dose logged: 2 of 20 left.
    private lazy var finished = makeFinished()
    /// Runs to the 20th; 22 left after this morning's dose, for 17 more.
    private lazy var covered = course(count: 45, through: 20, loggedThrough: september(12, 8))
    /// Runs to the 20th with 7 left: out on the 15th.
    private lazy var runsOutFirst = course(count: 30, through: 20, loggedThrough: september(12, 8))

    private func makeFinished() -> Course { course(count: 20, through: 9, loggedThrough: september(9, 23)) }

    func testTheFixturesAreTheCoursesTheyAreSaidToBe() {
        XCTAssertTrue(forecast(finished).courseFinished)
        XCTAssertEqual(forecast(finished).currentSupply, 2)
        XCTAssertTrue(forecast(covered).courseCovered)
        XCTAssertEqual(forecast(covered).leftoverAtCourseEnd, 5)
        XCTAssertFalse(forecast(runsOutFirst).courseCovered)
        XCTAssertEqual(forecast(runsOutFirst).daysRemaining, 3)
    }

    // MARK: - Detail screen

    /// A course is asked about before anything else: finished or seen
    /// through, it is never "Out of supply" or "Timing unknown", even with
    /// the bottle empty.
    func testTheDetailTitleSaysACourseIsFinishedOrCovered() {
        XCTAssertEqual(MedicationDetailView.forecastTitle(for: forecast(finished), calendar: calendar), "Course finished Sep 9")
        XCTAssertEqual(MedicationDetailView.forecastTitle(for: forecast(covered), calendar: calendar), "Enough to finish the course")
        XCTAssertEqual(MedicationDetailView.forecastTitle(for: forecast(runsOutFirst), calendar: calendar), "About 3 days left")

        let emptyAtTheEnd = course(count: 18, through: 9, loggedThrough: september(9, 23))
        XCTAssertEqual(forecast(emptyAtTheEnd).currentSupply, 0)
        XCTAssertEqual(MedicationDetailView.forecastTitle(for: forecast(emptyAtTheEnd), calendar: calendar), "Course finished Sep 9")
        let emptyOnTheLastEvening = forecast(emptyAtTheEnd, now: september(9, 21))
        XCTAssertTrue(emptyOnTheLastEvening.courseCovered)
        XCTAssertEqual(MedicationDetailView.forecastTitle(for: emptyOnTheLastEvening, calendar: calendar), "Enough to finish the course")
    }

    func testTheDetailLineDoesNotRepeatAFinishedCoursesTitle() {
        XCTAssertEqual(MedicationDetailView.forecastDetail(for: forecast(finished)), "No doses are scheduled after its last day.")
        XCTAssertEqual(MedicationDetailView.forecastDetail(for: forecast(covered)), forecast(covered).explanation)
        XCTAssertTrue(forecast(covered).explanation.hasPrefix("Enough to finish the course on Sep 20, with 5 tablets left."))
    }

    /// The ring reads complete for a course, never the question mark of a
    /// forecast that could not be made.
    func testTheGaugeReadsCompleteForACourse() {
        XCTAssertEqual(SupplyGauge.Course(forecast(covered)), .covered)
        XCTAssertEqual(SupplyGauge.Course(forecast(finished)), .finished)
        XCTAssertNil(SupplyGauge.Course(forecast(runsOutFirst)))

        let coveredGauge = SupplyGauge(daysRemaining: nil, leadDays: 7, course: .covered)
        XCTAssertNil(coveredGauge.shownDays)
        XCTAssertEqual(coveredGauge.color, AppTheme.accent)
        XCTAssertEqual(coveredGauge.accessibilityText, "Enough to finish the course")

        let finishedGauge = SupplyGauge(daysRemaining: nil, leadDays: 7, course: .finished)
        XCTAssertEqual(finishedGauge.color, .secondary)
        XCTAssertEqual(finishedGauge.accessibilityText, "Course finished")
        XCTAssertEqual(SupplyGauge(daysRemaining: 3, leadDays: 7).accessibilityText, "3 days of supply remaining", "a supply that runs out is unchanged")
    }

    /// Under the schedule's times: its last day while it runs, the day it
    /// finished once it has, nothing for a medication not on a course.
    func testTheScheduleCardSaysWhenTheCourseEnds() throws {
        let running = try XCTUnwrap(MedicationDetailView.courseLine(schedules: covered.schedules, medicationID: covered.medication.id, now: now, calendar: calendar))
        XCTAssertEqual(running.text, "Until Sunday, Sep 20")
        XCTAssertFalse(running.isFinished)

        let lastDay = try XCTUnwrap(MedicationDetailView.courseLine(schedules: covered.schedules, medicationID: covered.medication.id,
                                                                    now: september(20, 21), calendar: calendar))
        XCTAssertEqual(lastDay.text, "Until Sunday, Sep 20", "still running on its last evening")

        let over = try XCTUnwrap(MedicationDetailView.courseLine(schedules: finished.schedules, medicationID: finished.medication.id, now: now, calendar: calendar))
        XCTAssertEqual(over.text, "Course finished Sep 9")
        XCTAssertTrue(over.isFinished)

        let ongoing = course(count: 30, through: nil)
        XCTAssertNil(MedicationDetailView.courseLine(schedules: ongoing.schedules, medicationID: ongoing.medication.id, now: now, calendar: calendar))
    }

    // MARK: - Supply

    func testASupplyRowSaysACourseIsCoveredOrFinished() {
        XCTAssertEqual(SupplyRowText.summary(for: forecast(covered), isLow: false, refillStatus: nil, calendar: calendar),
                       "Enough to finish the course on Sep 20")
        XCTAssertEqual(SupplyRowText.summary(for: forecast(covered), isLow: false, refillStatus: "Refill requested", calendar: calendar),
                       "Enough to finish the course on Sep 20", "a refill is not what a covered course is waiting on")
        XCTAssertEqual(SupplyRowText.summary(for: forecast(finished), isLow: false, refillStatus: nil, calendar: calendar), "Course finished Sep 9")
        XCTAssertEqual(SupplyRowText.caption(for: forecast(covered), form: .tablet), "22 tablets on hand · 5 tablets left after the last dose")
        XCTAssertEqual(SupplyRowText.caption(for: forecast(finished), form: .tablet), "2 tablets on hand")
        let oneLeft = SupplyForecast(currentSupply: 4, depletionDate: nil, daysRemaining: nil, confidence: .high, explanation: "",
                                     courseEndDate: lastDay(20), courseCovered: true, leftoverAtCourseEnd: 1)
        XCTAssertEqual(SupplyRowText.caption(for: oneLeft, form: .capsule), "4 capsules on hand · 1 capsule left after the last dose")
    }

    /// Neither a covered course nor a finished one needs anyone; one that
    /// runs out before its last day keeps the warning.
    func testOnlyACourseThatRunsOutFirstNeedsAttention() {
        func attention(_ course: Course) -> SupplyAttention {
            SupplyAttention(medication: course.medication, forecast: forecast(course), now: now, calendar: calendar)
        }
        XCTAssertFalse(attention(covered).needsAttention)
        XCTAssertFalse(attention(finished).needsAttention)
        XCTAssertTrue(attention(runsOutFirst).needsAttention)
        XCTAssertTrue(SupplyRowText.summary(for: forecast(runsOutFirst), isLow: true, refillStatus: nil, calendar: calendar).hasPrefix("Act soon · around "))
    }

    /// Run-out dates first, soonest first; then courses, running before
    /// finished, by last day; then the ones nobody can forecast.
    func testSupplyOrdersCoursesAfterRunOutDatesAndBeforeUnknowns() {
        func entry(_ name: String, _ forecast: SupplyForecast) -> (Medication, SupplyForecast) { (Medication(name: name), forecast) }
        func dated(_ days: Int) -> SupplyForecast {
            SupplyForecast(currentSupply: 10, depletionDate: september(12 + days), daysRemaining: days, confidence: .high, explanation: "")
        }
        func courseForecast(end: Int, finished: Bool) -> SupplyForecast {
            SupplyForecast(currentSupply: 4, depletionDate: nil, daysRemaining: nil, confidence: .high, explanation: "",
                           courseEndDate: lastDay(end), courseCovered: !finished, courseFinished: finished)
        }
        let unknown = SupplyForecast(currentSupply: 10, depletionDate: nil, daysRemaining: nil, confidence: .unknown, explanation: "")
        let ordered = SupplyView.ordered([
            entry("Zinc", unknown),
            entry("Finished late", courseForecast(end: 10, finished: true)),
            entry("Covered later", courseForecast(end: 25, finished: false)),
            entry("Furosemide", dated(9)),
            entry("Finished early", courseForecast(end: 5, finished: true)),
            entry("Covered soon", courseForecast(end: 15, finished: false)),
            entry("Count needed", SupplyForecast(currentSupply: 3, depletionDate: now, daysRemaining: 0, confidence: .estimated, explanation: "",
                                                 assumedDoses: 4, needsCount: true)),
            entry("Aspirin", unknown),
            entry("Tacrolimus", dated(3))
        ])
        XCTAssertEqual(ordered.map(\.0.displayName), [
            "Count needed", "Tacrolimus", "Furosemide",
            "Covered soon", "Covered later",
            "Finished early", "Finished late",
            "Aspirin", "Zinc"
        ])
    }

    // MARK: - Today

    private func finishedCards(_ courses: [Course], setAside: Set<String> = [], now: Date? = nil) -> [FinishedCourseNotice.Item] {
        FinishedCourseNotice.items(
            medications: courses.map(\.medication),
            schedules: courses.flatMap(\.schedules),
            inventoryEvents: courses.flatMap(\.inventory),
            doseEvents: courses.flatMap(\.doses),
            setAside: setAside,
            now: now ?? self.now,
            calendar: calendar
        )
    }

    /// Finished on the 9th: offered on the 10th through the 12th, and not
    /// before its last day is over or after the third day.
    func testTodayOffersACourseForThreeDaysAfterItsLastDay() throws {
        let course = finished
        XCTAssertTrue(finishedCards([course], now: september(9, 21)).isEmpty, "still running on its last evening")
        for day in 10...12 {
            XCTAssertEqual(finishedCards([course], now: september(day, 9)).map(\.medicationID), [course.medication.id], "the \(day)th")
        }
        XCTAssertTrue(finishedCards([course], now: september(13, 9)).isEmpty, "four days on")

        let item = try XCTUnwrap(finishedCards([course]).first)
        XCTAssertEqual(item.end, lastDay(9))
        XCTAssertEqual(FinishedCourseNotice.title(for: item, calendar: calendar), "Amoxicillin's course finished on Sep 9.")
    }

    /// Nothing is offered for a medication that is not on a course, for a
    /// course still running, archived, as needed, or for one set aside.
    func testTodayOffersOnlyAFinishedCourseNobodySetAside() {
        XCTAssertTrue(finishedCards([covered, runsOutFirst, course("Ongoing", count: 30, through: nil)]).isEmpty)

        let archived = makeFinished()
        archived.medication.isArchived = true
        XCTAssertTrue(finishedCards([archived]).isEmpty)

        let asNeeded = makeFinished()
        asNeeded.medication.isAsNeeded = true
        XCTAssertTrue(finishedCards([asNeeded]).isEmpty)

        let course = makeFinished()
        let key = FinishedCourseNotice.key(medicationID: course.medication.id, end: lastDay(9), calendar: calendar)
        XCTAssertTrue(finishedCards([course], setAside: [key]).isEmpty)
        let otherCourse = FinishedCourseNotice.key(medicationID: course.medication.id, end: lastDay(3), calendar: calendar)
        XCTAssertEqual(finishedCards([course], setAside: [otherCourse]).count, 1, "set aside for an earlier course, not for this one")
    }

    /// A course whose supply ran short of its last day ended with doses
    /// missing, and an offer to archive it would read as a clean finish.
    /// One whose count covered the rest, logged or not, finished.
    func testTodayOffersNothingForACourseThatRanOutFirst() {
        let ranShort = course(count: 16, through: 9, loggedThrough: september(8, 9))
        XCTAssertTrue(forecast(ranShort).courseFinished, "the forecast calls it finished all the same")
        XCTAssertTrue(finishedCards([ranShort]).isEmpty)

        let notLoggedButEnough = course(count: 18, through: 9)
        XCTAssertEqual(finishedCards([notLoggedButEnough]).count, 1, "18 counted for the 18 doses the course asked for")
        let notLoggedAndShort = course(count: 17, through: 9)
        XCTAssertTrue(finishedCards([notLoggedAndShort]).isEmpty)

        let refilled = course(count: 16, through: 9, loggedThrough: september(9, 23))
        let withRefill = Course(medication: refilled.medication, schedules: refilled.schedules,
                                inventory: refilled.inventory + [InventoryEvent(medicationID: refilled.medication.id, date: september(8, 10), delta: 10, reason: .refill)],
                                doses: refilled.doses)
        XCTAssertEqual(finishedCards([withRefill]).count, 1, "a refill during the course saw it through")
    }

    /// Archive on the card marks the medication archived, as the detail
    /// screen's menu does, and writes nothing to its ledger: restored, it
    /// has the same history.
    @MainActor
    func testArchivingAFinishedCourseWritesNoLedgerEvent() throws {
        let schema = Schema([Medication.self, DoseSchedule.self, DoseEvent.self, InventoryEvent.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let course = makeFinished()
        context.insert(course.medication)
        course.schedules.forEach(context.insert)
        course.inventory.forEach(context.insert)
        course.doses.forEach(context.insert)
        try context.save()
        let inventoryBefore = try context.fetchCount(FetchDescriptor<InventoryEvent>())
        let dosesBefore = try context.fetchCount(FetchDescriptor<DoseEvent>())
        XCTAssertEqual(finishedCards([course]).count, 1)

        try FinishedCourseNotice.archive(course.medication, in: context, now: now)

        XCTAssertTrue(course.medication.isArchived)
        XCTAssertEqual(course.medication.updatedAt, now)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<InventoryEvent>()), inventoryBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DoseEvent>()), dosesBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DoseSchedule>()), 2, "its schedules stay for the calendar")
        XCTAssertTrue(finishedCards([course]).isEmpty, "archived, it is not offered again")
    }

    func testTheSetAsideListKeepsEachCourseOnce() {
        let first = FinishedCourseNotice.adding("a", to: "")
        XCTAssertEqual(first, "a")
        let both = FinishedCourseNotice.adding("b", to: first)
        XCTAssertEqual(FinishedCourseNotice.setAside(in: both), ["a", "b"])
        XCTAssertEqual(FinishedCourseNotice.adding("a", to: both), both)
        XCTAssertEqual(FinishedCourseNotice.setAside(in: ""), [])
    }

    // MARK: - Printed list

    private func listEntry(_ course: Course, schedules: [DoseSchedule]? = nil) throws -> MedicationListEntry {
        try XCTUnwrap(MedicationListDocument.entries(
            medications: [course.medication],
            schedules: schedules ?? course.schedules,
            inventoryEvents: course.inventory,
            doseEvents: course.doses,
            now: now,
            calendar: calendar
        ).first)
    }

    private func printedDay(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, calendar: calendar, timeZone: calendar.timeZone))
    }

    func testThePrintedListSaysWhenACourseEnds() throws {
        let running = try listEntry(covered)
        XCTAssertEqual(running.scheduleLines.count, 2)
        XCTAssertTrue(running.scheduleLines.allSatisfy { $0.hasSuffix(" · Every day · until \(printedDay(lastDay(20)))") }, "\(running.scheduleLines)")
        XCTAssertEqual(printedDay(lastDay(20)), "Sep 20, 2026")
        XCTAssertEqual(running.supplyLine, "22 tablets on hand · enough to finish the course on Sep 20, 2026")

        let over = try listEntry(finished)
        XCTAssertEqual(over.scheduleLines, ["Course finished Sep 9, 2026"], "no times for a course that is over")
        XCTAssertEqual(over.supplyLine, "2 tablets on hand")

        let ongoing = try listEntry(course(count: 30, through: nil, loggedThrough: september(12, 8)))
        XCTAssertFalse(ongoing.scheduleLines.contains { $0.contains("until") })
        XCTAssertTrue(ongoing.supplyLine.contains("runs out around"))
    }

    /// Enough for the course only if the unlogged doses were taken, as the
    /// run-out line says it.
    func testAPrintedCoveredCourseSaysWhatItAssumed() throws {
        let unlogged = try listEntry(course(count: 45, through: 20, loggedThrough: september(11, 23)))
        XCTAssertEqual(unlogged.supplyLine,
                       "23 tablets on record · 1 dose since the last count wasn't logged · enough to finish the course on Sep 20, 2026 if it was taken")
    }

    /// A course taken up again prints the times it is taken on now, not the
    /// ended course's beside them.
    func testThePrintedListShowsOnlyTheCourseTakenUpAgain() throws {
        let old = finished
        let reopened = [9, 21].map {
            DoseSchedule(medicationID: old.medication.id, minutesAfterMidnight: $0 * 60, doseQuantity: 1, startDate: now, endDate: lastDay(20))
        }
        let entry = try listEntry(old, schedules: old.schedules + reopened)
        XCTAssertEqual(entry.scheduleLines.count, 2, "the two times it is taken on now, not four: \(entry.scheduleLines)")
        XCTAssertTrue(entry.scheduleLines.allSatisfy { $0.hasSuffix("until Sep 20, 2026") })
    }
}
