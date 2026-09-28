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

    // MARK: - The forecast

    private func attention(_ medication: Medication, _ forecast: SupplyForecast, now: Date) -> SupplyAttention {
        SupplyAttention(medication: medication, forecast: forecast, now: now, calendar: calendar)
    }

    /// A course that ends before the supply does used to read "extends
    /// beyond the forecast window", with unknown confidence.
    func testASupplyThatOutlastsTheCourseIsEnoughToFinishIt() {
        let (medication, schedules, opening) = twiceDailyCourse(count: 24, through: 10)
        let now = september(1, 7, 30)
        let result = forecast(medication, schedules, [opening], now: now)

        XCTAssertNil(result.depletionDate)
        XCTAssertNil(result.daysRemaining)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertTrue(result.courseCovered)
        XCTAssertFalse(result.courseFinished)
        XCTAssertEqual(result.leftoverAtCourseEnd, 4, "twenty doses from twenty-four")
        XCTAssertEqual(result.courseEndDate, lastDay(10))
        XCTAssertEqual(result.explanation, "Enough to finish the course on \(ForecastEngine.dayText(lastDay(10), calendar: calendar)), with 4 tablets left.")
        XCTAssertEqual(result.currentSupply, 24)
        XCTAssertFalse(attention(medication, result, now: now).needsAttention)

        let exact = forecast(medication, schedules, [InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: 20, reason: .openingCount)], now: now)
        XCTAssertTrue(exact.courseCovered, "the last tablet for the last dose is enough, not a run-out on the last day")
        XCTAssertNil(exact.depletionDate)
        XCTAssertEqual(exact.leftoverAtCourseEnd, 0)
        XCTAssertTrue(exact.explanation.hasSuffix("with 0 tablets left."), exact.explanation)

        let liquid = twiceDailyCourse(count: 21.5, through: 10, form: .liquid)
        XCTAssertTrue(forecast(liquid.0, liquid.1, [liquid.2], now: now).explanation.hasSuffix("with 1.5 mL left."))
    }

    /// Running out first keeps the run-out date and the alert it drives,
    /// and says the course is not covered.
    func testASupplyThatRunsOutBeforeTheCourseEndsSaysSo() throws {
        let (medication, schedules, opening) = twiceDailyCourse(count: 15, through: 10)
        let now = september(1, 7, 30)
        let result = forecast(medication, schedules, [opening], now: now)
        let ongoing = schedules.map {
            DoseSchedule(id: $0.id, medicationID: medication.id, minutesAfterMidnight: $0.minutesAfterMidnight, startDate: $0.startDate)
        }

        XCTAssertEqual(result.depletionDate, september(8, 8), "the fifteenth dose")
        XCTAssertEqual(result.depletionDate, forecast(medication, ongoing, [opening], now: now).depletionDate)
        XCTAssertEqual(result.daysRemaining, 7)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertFalse(result.courseCovered)
        XCTAssertNil(result.leftoverAtCourseEnd)
        XCTAssertEqual(result.courseEndDate, lastDay(10))
        XCTAssertEqual(result.explanation, "Based on the confirmed count and current schedule. Runs out before the course ends on \(ForecastEngine.dayText(lastDay(10), calendar: calendar)).")

        // Nineteen for twenty doses: the last one is the one that runs short.
        let oneShort = forecast(medication, schedules, [InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: 19, reason: .openingCount)], now: now)
        XCTAssertEqual(oneShort.depletionDate, september(10, 8))
        XCTAssertFalse(oneShort.courseCovered)
        let halfShort = forecast(medication, schedules, [InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: 19.5, reason: .openingCount)], now: now)
        XCTAssertEqual(halfShort.depletionDate, september(10, 20), "half a tablet is not the last dose")
        XCTAssertFalse(halfShort.courseCovered)
    }

    /// The day after the last day, nothing is due and nothing needs a refill,
    /// however much or little is left in the bottle.
    func testAFinishedCourseNeedsNothing() {
        let (medication, schedules, opening) = twiceDailyCourse(count: 20, through: 10)
        let now = september(11, 9)
        let leftovers = forecast(medication, schedules, [opening], now: now)
        XCTAssertTrue(leftovers.courseFinished)
        XCTAssertFalse(leftovers.courseCovered)
        XCTAssertNil(leftovers.depletionDate)
        XCTAssertNil(leftovers.daysRemaining)
        XCTAssertEqual(leftovers.assumedDoses, 0, "nothing to assume about a course that is over")
        XCTAssertEqual(leftovers.currentSupply, 20, "the ledger's own number")
        XCTAssertEqual(leftovers.courseEndDate, lastDay(10))
        XCTAssertEqual(leftovers.explanation, "Course finished \(ForecastEngine.dayText(lastDay(10), calendar: calendar)).")
        XCTAssertFalse(attention(medication, leftovers, now: now).needsAttention)

        let allTaken = (1...10).flatMap { day in schedules.map { logged($0, on: day) } }
        let empty = forecast(medication, schedules, [opening], allTaken, now: now)
        XCTAssertTrue(empty.courseFinished)
        XCTAssertEqual(empty.currentSupply, 0)
        XCTAssertNil(empty.depletionDate, "not \"No confirmed supply remains\"")
        XCTAssertFalse(attention(medication, empty, now: now).isLow, "an empty bottle is how the course ended")
    }

    /// After the last dose of a course dispensed to the tablet, nothing is on
    /// record and nothing more is needed; with a dose still to come, nothing
    /// on record is still a gap.
    func testTheLastDayWithNothingLeftIsCoveredOnlyOnceTheLastDoseIsDone() {
        let (medication, schedules, opening) = twiceDailyCourse(count: 20, through: 10)
        let allTaken = (1...10).flatMap { day in schedules.map { logged($0, on: day) } }

        let done = forecast(medication, schedules, [opening], allTaken, now: september(10, 21))
        XCTAssertTrue(done.courseCovered)
        XCTAssertEqual(done.leftoverAtCourseEnd, 0)
        XCTAssertNil(done.depletionDate)
        XCTAssertEqual(done.confidence, .high)
        XCTAssertFalse(attention(medication, done, now: september(10, 21)).needsAttention)

        let beforeEvening = forecast(medication, schedules, [opening], Array(allTaken.dropLast()), now: september(10, 19))
        XCTAssertTrue(beforeEvening.courseCovered, "one tablet for the one dose left")
        XCTAssertEqual(beforeEvening.leftoverAtCourseEnd, 0)

        let shortOne = InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: 19, reason: .openingCount)
        let gap = forecast(medication, schedules, [shortOne], Array(allTaken.dropLast()), now: september(10, 19))
        XCTAssertFalse(gap.courseCovered)
        XCTAssertEqual(gap.explanation, "No confirmed supply remains.")
        XCTAssertEqual(gap.depletionDate, september(10, 19))
        XCTAssertTrue(attention(medication, gap, now: september(10, 19)).needsAttention)
    }

    /// Dispensed three short, the bottle empties on the 9th and the last
    /// three doses go by. Once the final one is overdue nothing is still to
    /// come, but the course was not finished from this supply: the warning
    /// stays until the course is over, whether the missed doses were left
    /// unlogged or skipped.
    func testACourseThatRanOutEarlyIsNotEnoughOnItsLastDay() {
        let (medication, schedules, _) = twiceDailyCourse(count: 17, through: 10)
        let opening = InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: 17, reason: .openingCount)
        let untilEmpty = Array((1...9).flatMap { day in schedules.map { logged($0, on: day) } }.prefix(17))
        let missed = [(schedules[1], 9), (schedules[0], 10), (schedules[1], 10)].map { schedule, day in
            let date = september(day, schedule.minutesAfterMidnight / 60)
            return DoseEvent(medicationID: medication.id, scheduleID: schedule.id, scheduledAt: date, recordedAt: date.addingTimeInterval(60),
                             doseQuantity: 1, status: .skipped)
        }

        for (doses, label) in [(untilEmpty, "unlogged"), (untilEmpty + missed, "skipped")] {
            let midCourse = forecast(medication, schedules, [opening], doses, now: september(9, 21))
            XCTAssertEqual(midCourse.explanation, "No confirmed supply remains.", label)

            let lastEvening = september(10, 20, 31)
            let afterLastDose = forecast(medication, schedules, [opening], doses, now: lastEvening)
            XCTAssertFalse(afterLastDose.courseCovered, label)
            XCTAssertNil(afterLastDose.leftoverAtCourseEnd, label)
            XCTAssertEqual(afterLastDose.explanation, "No confirmed supply remains.", label)
            XCTAssertEqual(afterLastDose.courseEndDate, lastDay(10), label)
            XCTAssertTrue(attention(medication, afterLastDose, now: lastEvening).needsAttention, label)

            XCTAssertTrue(forecast(medication, schedules, [opening], doses, now: september(11, 8)).courseFinished, label)
        }

        // Every dose logged, the last one at 20:00: an empty bottle at 20:31
        // is the course finished from what was dispensed.
        let (exact, exactSchedules, exactOpening) = twiceDailyCourse(count: 20, through: 10)
        let allTaken = (1...10).flatMap { day in exactSchedules.map { logged($0, on: day) } }
        XCTAssertTrue(forecast(exact, exactSchedules, [exactOpening], allTaken, now: september(10, 20, 31)).courseCovered)

        // Never counted and nothing logged: nothing says the course was had.
        let uncounted = forecast(exact, exactSchedules, [], now: september(10, 20, 31))
        XCTAssertFalse(uncounted.courseCovered)
        XCTAssertEqual(uncounted.explanation, "No confirmed supply remains.")
    }

    /// The 1.1.1 rule still holds on a course: doses nobody logged are
    /// assumed taken before the course's remaining doses are weighed.
    func testUnloggedDosesAreAssumedTakenOnACourseToo() {
        let (medication, schedules, _) = twiceDailyCourse(count: 24, through: 10)
        let now = september(3, 7)
        let day = ForecastEngine.dayText(lastDay(10), calendar: calendar)

        let covered = forecast(medication, schedules, [InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: 24, reason: .openingCount)], now: now)
        XCTAssertEqual(covered.assumedDoses, 4)
        XCTAssertTrue(covered.courseCovered)
        XCTAssertEqual(covered.leftoverAtCourseEnd, 4, "24, less 4 assumed and 16 to come")
        XCTAssertEqual(covered.confidence, .estimated)
        XCTAssertEqual(covered.explanation,
                       "Enough to finish the course on \(day), with 4 tablets left. Assumes the 4 scheduled doses since your last count that weren't logged were taken.")

        let short = forecast(medication, schedules, [InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: 18, reason: .openingCount)], now: now)
        XCTAssertEqual(short.assumedDoses, 4)
        XCTAssertFalse(short.courseCovered)
        XCTAssertEqual(short.depletionDate, september(9, 20), "14 left after the assumed doses")
        XCTAssertEqual(short.confidence, .estimated)
        XCTAssertEqual(short.explanation,
                       "Assumes the 4 scheduled doses since your last count that weren't logged were taken. Runs out before the course ends on \(day).")
    }

    /// A count needed during a course still says count needed: whatever the
    /// course asks for, nobody knows what is left.
    func testACountNeededDuringACourseStillSaysCountNeeded() {
        let (medication, schedules, _) = twiceDailyCourse(count: 4, through: 10)
        let opening = InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: 4, reason: .openingCount)
        let now = september(3, 7)
        let result = forecast(medication, schedules, [opening], now: now)

        XCTAssertTrue(result.needsCount)
        XCTAssertFalse(result.courseCovered)
        XCTAssertFalse(result.courseFinished)
        XCTAssertEqual(result.assumedDoses, 4)
        XCTAssertEqual(result.courseEndDate, lastDay(10))
        XCTAssertTrue(result.explanation.contains("Count what is left"), result.explanation)
        XCTAssertTrue(attention(medication, result, now: now).needsAttention)
    }

    /// A course dispensed to the tablet whose last dose goes by unlogged:
    /// the doses assumed taken use up the supply exactly, and none is left
    /// to come. That is the course seen through, before its due window
    /// closes and after, not a count needed for the rest of the evening.
    func testTheLastDosePassingUnloggedLeavesAnExactCourseCovered() {
        let (medication, schedules, opening) = twiceDailyCourse(count: 20, through: 10)
        let day = ForecastEngine.dayText(lastDay(10), calendar: calendar)
        let allButLast = Array((1...10).flatMap { day in schedules.map { logged($0, on: day) } }.dropLast())

        let inWindow = forecast(medication, schedules, [opening], allButLast, now: september(10, 20, 29))
        XCTAssertTrue(inWindow.courseCovered)
        let after = forecast(medication, schedules, [opening], allButLast, now: september(10, 20, 31))
        XCTAssertFalse(after.needsCount)
        XCTAssertTrue(after.courseCovered)
        XCTAssertEqual(after.leftoverAtCourseEnd, 0)
        XCTAssertEqual(after.assumedDoses, 1)
        XCTAssertEqual(after.confidence, .estimated)
        XCTAssertEqual(after.explanation,
                       "Enough to finish the course on \(day), with 0 tablets left. Assumes the 1 scheduled dose since your last count that wasn't logged was taken.")
        XCTAssertFalse(attention(medication, after, now: september(10, 20, 31)).needsAttention)

        let nothingLogged = forecast(medication, schedules, [opening], now: september(10, 20, 31))
        XCTAssertTrue(nothingLogged.courseCovered)
        XCTAssertEqual(nothingLogged.assumedDoses, 20)

        // Once a day at 08:00: from 08:30 on its last day, not a count needed.
        let cefalexin = Medication(name: "Cefalexin", form: .tablet, createdAt: september(1, 7))
        let morning = DoseSchedule(medicationID: cefalexin.id, minutesAfterMidnight: 8 * 60, doseQuantity: 1,
                                   startDate: september(1, 7), endDate: lastDay(7))
        let seven = InventoryEvent(medicationID: cefalexin.id, date: september(1, 7), delta: 7, reason: .openingCount)
        let noon = forecast(cefalexin, [morning], [seven], (1...6).map { logged(morning, on: $0) }, now: september(7, 12))
        XCTAssertTrue(noon.courseCovered)
        XCTAssertFalse(noon.needsCount)

        // One tablet short of what the unlogged doses took is still a count.
        let short = InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: 19, reason: .openingCount)
        XCTAssertTrue(forecast(medication, schedules, [short], Array(allButLast.dropLast()), now: september(10, 20, 31)).needsCount)
    }

    /// A course is a scheduled medication's: schedules left behind when a
    /// medication was made as-needed do not end it. One whose last day lies
    /// past the forecast window is weighed like any other schedule.
    func testOnlyAScheduledCourseWithinTheWindowIsACourse() throws {
        let (medication, schedules, opening) = twiceDailyCourse(count: 20, through: 5)
        medication.isAsNeeded = true
        let doses = (1...3).map { DoseEvent(medicationID: medication.id, recordedAt: september($0, 12), doseQuantity: 1, status: .taken) }
        let asNeeded = forecast(medication, schedules, [opening], doses, now: september(8, 9))
        XCTAssertEqual(asNeeded, forecast(medication, [], [opening], doses, now: september(8, 9)))
        XCTAssertNil(asNeeded.courseEndDate)

        let longCourse = Medication(name: "Tacrolimus", createdAt: september(1, 7))
        let farEnd = ScheduleEngine.normalizedEndDate(forDay: try XCTUnwrap(calendar.date(byAdding: .year, value: 4, to: september(1))), calendar: calendar)
        let schedule = DoseSchedule(medicationID: longCourse.id, minutesAfterMidnight: 8 * 60, startDate: september(1, 7), endDate: farEnd)
        let plenty = InventoryEvent(medicationID: longCourse.id, date: september(1, 7), delta: 5000, reason: .openingCount)
        let result = forecast(longCourse, [schedule], [plenty], now: september(1, 7, 30))
        XCTAssertFalse(result.courseCovered, "four years out is past what the forecast can vouch for")
        XCTAssertEqual(result.confidence, .unknown)
        XCTAssertEqual(result.courseEndDate, farEnd)
    }
}
