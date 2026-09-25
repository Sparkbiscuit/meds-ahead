import SwiftData
import XCTest
@testable import Meds

final class ScheduleReconcilerTests: XCTestCase {
    @MainActor
    func testUnchangedTimesPreserveScheduleIdentifiers() throws {
        let fixture = try makeFixture(minutes: [8 * 60, 20 * 60])
        let originalIDs = fixture.schedules.map(\.id)

        let reconciled = ScheduleReconciler.reconcile(
            medicationID: fixture.medicationID,
            definitions: definitions(minutes: [8 * 60, 20 * 60], quantity: 2),
            existing: fixture.schedules,
            in: fixture.context
        )
        try fixture.context.save()

        XCTAssertEqual(reconciled.map(\.id), originalIDs)
        XCTAssertTrue(reconciled.allSatisfy { $0.doseQuantity == 2 })
    }

    @MainActor
    func testChangedTimeReusesOnlyUnmatchedSchedule() throws {
        let fixture = try makeFixture(minutes: [8 * 60, 20 * 60])
        let morningID = fixture.schedules[0].id
        let eveningID = fixture.schedules[1].id

        let reconciled = ScheduleReconciler.reconcile(
            medicationID: fixture.medicationID,
            definitions: definitions(minutes: [9 * 60, 20 * 60]),
            existing: fixture.schedules,
            in: fixture.context
        )
        try fixture.context.save()

        XCTAssertEqual(reconciled[0].id, morningID)
        XCTAssertEqual(reconciled[0].minutesAfterMidnight, 9 * 60)
        XCTAssertEqual(reconciled[1].id, eveningID)
        XCTAssertEqual(reconciled[1].minutesAfterMidnight, 20 * 60)
    }

    /// The reason a changed time reuses the schedule: the dose logged against
    /// the old time is still today's dose, and Today must not offer it again.
    @MainActor
    func testALoggedDoseStaysLoggedAfterItsTimeIsEdited() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 12)))
        let fixture = try makeFixture(minutes: [8 * 60], startDate: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))))
        let slot = try XCTUnwrap(ScheduleEngine.doses(schedules: fixture.schedules, medicationID: fixture.medicationID, onDayOf: now, calendar: calendar).first)
        fixture.context.insert(
            DoseEvent(medicationID: fixture.medicationID, scheduleID: slot.scheduleID, scheduledAt: slot.date,
                      recordedAt: slot.date.addingTimeInterval(120), doseQuantity: 1, status: .taken)
        )
        try fixture.context.save()

        let reconciled = ScheduleReconciler.reconcile(
            medicationID: fixture.medicationID,
            definitions: definitions(minutes: [21 * 60]),
            existing: fixture.schedules,
            in: fixture.context
        )
        try fixture.context.save()

        let moved = try XCTUnwrap(ScheduleEngine.doses(schedules: reconciled, medicationID: fixture.medicationID, onDayOf: now, calendar: calendar).first)
        XCTAssertEqual(moved.date, slot.date.addingTimeInterval(13 * 60 * 60))
        let events = try fixture.context.fetch(FetchDescriptor<DoseEvent>())
        XCTAssertEqual(ScheduleEngine.loggedStatus(for: moved, in: events, now: now, calendar: calendar), .taken)
    }

    @MainActor
    func testRemovingScheduleKeepsItsDoseHistory() throws {
        let fixture = try makeFixture(minutes: [8 * 60, 20 * 60])
        let removedSchedule = fixture.schedules[1]
        let removedScheduleID = removedSchedule.id
        fixture.context.insert(
            DoseEvent(
                medicationID: fixture.medicationID,
                scheduleID: removedScheduleID,
                scheduledAt: .now,
                doseQuantity: 1,
                status: .taken
            )
        )
        try fixture.context.save()

        _ = ScheduleReconciler.reconcile(
            medicationID: fixture.medicationID,
            definitions: definitions(minutes: [8 * 60]),
            existing: fixture.schedules,
            in: fixture.context
        )
        try fixture.context.save()

        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<DoseSchedule>()), 1)
        let events = try fixture.context.fetch(FetchDescriptor<DoseEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.scheduleID, removedScheduleID)
    }

    @MainActor
    func testEachScheduleKeepsItsOwnQuantityAndWeekdays() throws {
        let fixture = try makeFixture(minutes: [8 * 60, 20 * 60])
        let weekdays = (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5)
        let weekends = (1 << 0) | (1 << 6)

        let reconciled = ScheduleReconciler.reconcile(
            medicationID: fixture.medicationID,
            definitions: [
                ScheduleDefinition(
                    minutesAfterMidnight: 8 * 60,
                    doseQuantity: 2,
                    weekdayMask: weekdays
                ),
                ScheduleDefinition(
                    minutesAfterMidnight: 20 * 60,
                    doseQuantity: 0.5,
                    weekdayMask: weekends
                )
            ],
            existing: fixture.schedules,
            in: fixture.context
        )
        try fixture.context.save()

        XCTAssertEqual(reconciled[0].doseQuantity, 2)
        XCTAssertEqual(reconciled[0].weekdayMask, weekdays)
        XCTAssertEqual(reconciled[1].doseQuantity, 0.5)
        XCTAssertEqual(reconciled[1].weekdayMask, weekends)
    }

    /// The reconciler rewrites a kept schedule's amount in place and deletes a
    /// dropped one, so the forecast weighs every unlogged dose since the count
    /// at the new schedule: a taper or a dropped dose moved the run-out date
    /// past the day the bottle empties. Such an edit asks for a count, and the
    /// count puts the date back where the supply really runs out.
    @MainActor
    func testATaperOrADroppedDoseWithUnloggedDosesAsksForACount() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func september(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
        }
        let schema = Schema([Medication.self, DoseSchedule.self, DoseEvent.self, InventoryEvent.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let now = september(11, 7)

        func scenario(minutes: [Int], quantity: Double, editedTo edited: [ScheduleDefinition])
            throws -> (before: SupplyForecast, after: SupplyForecast, asks: Bool, counted: (Double) -> SupplyForecast) {
            let medication = Medication(name: "Prednisone", createdAt: september(1, 7))
            context.insert(medication)
            let schedules = minutes.map { DoseSchedule(medicationID: medication.id, minutesAfterMidnight: $0, doseQuantity: quantity, startDate: september(1, 7)) }
            schedules.forEach(context.insert)
            let opening = InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: 60, reason: .openingCount)
            context.insert(opening)
            try context.save()
            func forecast(_ schedules: [DoseSchedule], _ inventory: [InventoryEvent]) -> SupplyForecast {
                ForecastEngine.forecast(medication: medication, schedules: schedules, inventoryEvents: inventory, doseEvents: [], now: now, calendar: calendar)
            }
            let before = forecast(schedules, [opening])
            let snapshot = ScheduleReconciler.snapshot(schedules)
            let reconciled = ScheduleReconciler.reconcile(medicationID: medication.id, definitions: edited, existing: schedules, in: context, startDate: now)
            try context.save()
            let asks = ScheduleReconciler.asksForCount(assumedDoses: before.assumedDoses, before: snapshot, after: reconciled)
            let counted: (Double) -> SupplyForecast = { count in
                let delta = ForecastEngine.correctionDelta(medicationID: medication.id, actualCount: count, inventoryEvents: [opening], doseEvents: [])
                return forecast(reconciled, [opening, InventoryEvent(medicationID: medication.id, date: now, delta: delta, reason: .correction)])
            }
            return (before, forecast(reconciled, [opening]), asks, counted)
        }

        // 4 tablets a day tapered to 2: ten doses of 4 went unlogged, so 20 are
        // left, not 40.
        let taper = try scenario(minutes: [8 * 60], quantity: 4,
                                 editedTo: [ScheduleDefinition(minutesAfterMidnight: 8 * 60, doseQuantity: 2, weekdayMask: 0b1111111)])
        XCTAssertEqual(taper.before.assumedDoses, 10)
        XCTAssertEqual(taper.before.daysRemaining, 4)
        XCTAssertEqual(taper.after.daysRemaining, 19, "the past, charged at the new amount, reads 10 days long")
        XCTAssertTrue(taper.asks)
        XCTAssertEqual(taper.counted(20).daysRemaining, 9, "20 tablets at 2 a day")

        // Twice a day cut to once: the evening's ten unlogged doses vanished
        // with its schedule.
        let dropped = try scenario(minutes: [8 * 60, 20 * 60], quantity: 1,
                                   editedTo: [ScheduleDefinition(minutesAfterMidnight: 8 * 60, doseQuantity: 1, weekdayMask: 0b1111111)])
        XCTAssertEqual(dropped.before.assumedDoses, 20)
        XCTAssertEqual(dropped.before.daysRemaining, 19)
        XCTAssertEqual(dropped.after.daysRemaining, 49, "the dropped evening's past went with it")
        XCTAssertTrue(dropped.asks)
        XCTAssertEqual(dropped.counted(40).daysRemaining, 39, "40 tablets at 1 a day")
    }

    /// Only an edit to what past days held asks: a new time or an added one
    /// keeps the past's amounts, and nothing asks when every dose was logged,
    /// since a logged dose keeps its own amount.
    @MainActor
    func testOnlyAnEditToThePastsAmountsAsksForACount() throws {
        let fixture = try makeFixture(minutes: [8 * 60, 20 * 60])
        func asks(_ before: [UUID: ScheduleDefinition], _ after: [DoseSchedule], assumedDoses: Int = 1) -> Bool {
            ScheduleReconciler.asksForCount(assumedDoses: assumedDoses, before: before, after: after)
        }
        let before = ScheduleReconciler.snapshot(fixture.schedules)
        let moved = ScheduleReconciler.reconcile(medicationID: fixture.medicationID, definitions: definitions(minutes: [9 * 60, 20 * 60]),
                                                 existing: fixture.schedules, in: fixture.context)
        XCTAssertFalse(asks(before, moved), "a new time keeps the past's amounts")

        let beforeAdding = ScheduleReconciler.snapshot(moved)
        let added = ScheduleReconciler.reconcile(medicationID: fixture.medicationID, definitions: definitions(minutes: [9 * 60, 14 * 60, 20 * 60]),
                                                 existing: moved, in: fixture.context)
        XCTAssertFalse(asks(beforeAdding, added), "an added time starts when it is saved")

        let beforeWeekdays = ScheduleReconciler.snapshot(added)
        let weekdays = (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5)
        let fewerDays = ScheduleReconciler.reconcile(
            medicationID: fixture.medicationID,
            definitions: [9 * 60, 14 * 60, 20 * 60].map {
                ScheduleDefinition(minutesAfterMidnight: $0, doseQuantity: 1, weekdayMask: $0 == 14 * 60 ? weekdays : 0b1111111)
            },
            existing: added, in: fixture.context
        )
        XCTAssertTrue(asks(beforeWeekdays, fewerDays), "fewer weekdays rewrite which past days held a dose")
        XCTAssertFalse(asks(beforeWeekdays, fewerDays, assumedDoses: 0), "with every dose logged, the past is what was logged")

        let beforeRaise = ScheduleReconciler.snapshot(fewerDays)
        let raised = ScheduleReconciler.reconcile(
            medicationID: fixture.medicationID,
            definitions: fewerDays.map { ScheduleDefinition(minutesAfterMidnight: $0.minutesAfterMidnight, doseQuantity: 2, weekdayMask: $0.weekdayMask) },
            existing: fewerDays, in: fixture.context
        )
        XCTAssertTrue(asks(beforeRaise, raised), "a raised amount charges past days more than they held, which asks too")
        XCTAssertFalse(asks(ScheduleReconciler.snapshot(raised), raised), "saved unchanged")

        let beforeAsNeeded = ScheduleReconciler.snapshot(raised)
        let asNeeded = ScheduleReconciler.reconcile(medicationID: fixture.medicationID, definitions: [], existing: raised, in: fixture.context)
        XCTAssertTrue(asks(beforeAsNeeded, asNeeded), "switched to as needed, every schedule's past goes with it")
    }

    /// A course's last day goes onto every schedule the edit keeps and every
    /// one it adds, and saving with no last day takes it off again: a course
    /// made ongoing must not still stop.
    @MainActor
    func testACoursesLastDayIsWrittenOnReusedAndNewSchedulesAndCleared() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let started = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9)))
        let fixture = try makeFixture(minutes: [8 * 60, 20 * 60], startDate: started)
        let lastDay = ScheduleEngine.normalizedEndDate(
            forDay: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 18))),
            calendar: calendar
        )
        XCTAssertEqual(lastDay, calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 12)))

        let course = ScheduleReconciler.reconcile(
            medicationID: fixture.medicationID,
            definitions: [8 * 60, 14 * 60, 20 * 60].map {
                ScheduleDefinition(minutesAfterMidnight: $0, doseQuantity: 1, weekdayMask: 0b1111111, endDate: lastDay)
            },
            existing: fixture.schedules,
            in: fixture.context,
            startDate: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 10)))
        )
        try fixture.context.save()
        XCTAssertEqual([course[0].id, course[2].id], fixture.schedules.map(\.id), "the 08:00 and 20:00 schedules are reused")
        XCTAssertEqual(course.map(\.endDate), [lastDay, lastDay, lastDay], "kept and added schedules alike")
        XCTAssertEqual(course[0].startDate, started, "a reused schedule keeps its start")
        XCTAssertEqual(ScheduleEngine.courseEnd(schedules: course, medicationID: fixture.medicationID), lastDay)
        XCTAssertEqual(ScheduleReconciler.snapshot(course)[course[0].id]?.endDate, lastDay, "a snapshot keeps the end it had")

        let ongoing = ScheduleReconciler.reconcile(
            medicationID: fixture.medicationID,
            definitions: [8 * 60, 14 * 60, 20 * 60, 22 * 60].map {
                ScheduleDefinition(minutesAfterMidnight: $0, doseQuantity: 1, weekdayMask: 0b1111111)
            },
            existing: course,
            in: fixture.context
        )
        try fixture.context.save()
        XCTAssertEqual(ongoing.map(\.id).prefix(3), course.map(\.id).prefix(3))
        XCTAssertTrue(ongoing.allSatisfy { $0.endDate == nil })
        XCTAssertNil(ScheduleEngine.courseEnd(schedules: ongoing, medicationID: fixture.medicationID))
    }

    /// The last day is a dose day, morning and evening, through the same
    /// question Today asks; the day after it holds nothing.
    @MainActor
    func testACoursesLastDayKeepsEveryDoseAndTheNextDayHasNone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func september(_ day: Int, _ hour: Int = 12) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
        }
        let fixture = try makeFixture(minutes: [8 * 60, 20 * 60], startDate: september(1, 7))
        let course = ScheduleReconciler.reconcile(
            medicationID: fixture.medicationID,
            definitions: [8 * 60, 20 * 60].map {
                ScheduleDefinition(minutesAfterMidnight: $0, doseQuantity: 1, weekdayMask: 0b1111111,
                                   endDate: ScheduleEngine.normalizedEndDate(forDay: september(10), calendar: calendar))
            },
            existing: fixture.schedules,
            in: fixture.context
        )
        try fixture.context.save()

        let lastDay = ScheduleEngine.doses(schedules: course, medicationID: fixture.medicationID, onDayOf: september(10), calendar: calendar)
        XCTAssertEqual(lastDay.map(\.date), [september(10, 8), september(10, 20)])
        XCTAssertTrue(ScheduleEngine.doses(schedules: course, medicationID: fixture.medicationID, onDayOf: september(11), calendar: calendar).isEmpty)
        XCTAssertEqual(ScheduleEngine.doses(schedules: course, medicationID: fixture.medicationID, from: september(1, 0), through: september(30), calendar: calendar).count,
                       20, "ten days, the first and the last included")
    }

    /// Moving a course's end across days already past rewrites what they
    /// held, as a taper does: ended three days back, the unlogged doses since
    /// leave what the forecast assumes. Moving it among days still to come
    /// does not.
    @MainActor
    func testMovingACoursesEndAcrossThePastAsksForACount() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func september(_ day: Int) -> Date { ScheduleEngine.normalizedEndDate(forDay: calendar.date(from: DateComponents(year: 2026, month: 9, day: day))!, calendar: calendar) }
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 9))!
        let fixture = try makeFixture(minutes: [8 * 60])
        func edit(from old: Date?, to new: Date?, assumedDoses: Int = 3) -> Bool {
            let before = [fixture.schedules[0].id: ScheduleDefinition(minutesAfterMidnight: 8 * 60, doseQuantity: 1, weekdayMask: 0b1111111, endDate: old)]
            fixture.schedules[0].endDate = new
            return ScheduleReconciler.asksForCount(assumedDoses: assumedDoses, before: before, after: fixture.schedules, now: now, calendar: calendar)
        }

        XCTAssertTrue(edit(from: nil, to: september(9)), "ended three days back")
        // A course already over forecasts no assumed doses, so these are
        // asked with the none the editor has.
        XCTAssertTrue(edit(from: september(9), to: nil, assumedDoses: 0), "a finished course made ongoing again")
        XCTAssertTrue(edit(from: september(11), to: september(20), assumedDoses: 0), "yesterday's end moved on")
        XCTAssertFalse(edit(from: september(5), to: september(9), assumedDoses: 0), "still over, so the forecast weighs nothing")
        XCTAssertFalse(edit(from: nil, to: september(12)), "ending today leaves every day so far as it was")
        XCTAssertFalse(edit(from: september(15), to: september(20)))
        XCTAssertFalse(edit(from: nil, to: september(20)))
        XCTAssertFalse(edit(from: september(20), to: september(20)))
        XCTAssertFalse(edit(from: nil, to: september(9), assumedDoses: 0), "with every dose logged, the past is what was logged")
    }

    /// The editor's own save, for a course that ended on the 9th and is
    /// extended on the 12th: its forecast before the edit assumes nothing,
    /// the reused schedules bring back the 10th and 11th, and without a
    /// count the forecast would assume their doses were taken though the
    /// course was not running.
    @MainActor
    func testExtendingAFinishedCourseAsksForACount() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func september(_ day: Int, _ hour: Int = 12) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
        }
        let now = september(12, 9)
        let schema = Schema([Medication.self, DoseSchedule.self, DoseEvent.self, InventoryEvent.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let medication = Medication(name: "Example", createdAt: september(1, 7))
        context.insert(medication)
        let schedules = [8, 20].map {
            DoseSchedule(medicationID: medication.id, minutesAfterMidnight: $0 * 60, doseQuantity: 1, startDate: september(1, 7),
                         endDate: ScheduleEngine.normalizedEndDate(forDay: september(9), calendar: calendar))
        }
        schedules.forEach(context.insert)
        let opening = InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: 40, reason: .openingCount)
        context.insert(opening)
        let taken = (1...9).flatMap { day in
            schedules.map { schedule in
                let date = september(day, schedule.minutesAfterMidnight / 60)
                return DoseEvent(medicationID: medication.id, scheduleID: schedule.id, scheduledAt: date, recordedAt: date,
                                 doseQuantity: 1, status: .taken)
            }
        }
        taken.forEach(context.insert)
        try context.save()
        func forecast(_ schedules: [DoseSchedule], _ inventory: [InventoryEvent]) -> SupplyForecast {
            ForecastEngine.forecast(medication: medication, schedules: schedules, inventoryEvents: inventory, doseEvents: taken, now: now, calendar: calendar)
        }

        let before = forecast(schedules, [opening])
        XCTAssertTrue(before.courseFinished)
        XCTAssertEqual(before.assumedDoses, 0)

        let snapshot = ScheduleReconciler.snapshot(schedules)
        let extended = ScheduleReconciler.reconcile(
            medicationID: medication.id,
            definitions: [8, 20].map {
                ScheduleDefinition(minutesAfterMidnight: $0 * 60, doseQuantity: 1, weekdayMask: 0b1111111,
                                   endDate: ScheduleEngine.normalizedEndDate(forDay: september(20), calendar: calendar))
            },
            existing: schedules,
            in: context,
            startDate: now
        )
        try context.save()
        XCTAssertTrue(ScheduleReconciler.asksForCount(assumedDoses: before.assumedDoses, before: snapshot, after: extended, now: now, calendar: calendar))

        let uncounted = forecast(extended, [opening])
        XCTAssertEqual(uncounted.assumedDoses, 5, "the 10th, the 11th and this morning, none of them scheduled at the time")
        XCTAssertEqual(uncounted.leftoverAtCourseEnd, 0)

        let delta = ForecastEngine.correctionDelta(medicationID: medication.id, actualCount: 22, inventoryEvents: [opening], doseEvents: taken)
        let counted = forecast(extended, [opening, InventoryEvent(medicationID: medication.id, date: now, delta: delta, reason: .correction)])
        XCTAssertEqual(counted.assumedDoses, 0)
        XCTAssertTrue(counted.courseCovered)
        XCTAssertEqual(counted.leftoverAtCourseEnd, 5, "22 on hand for the 17 doses from this evening through the 20th")
        XCTAssertEqual(counted.confidence, .high)
    }

    @MainActor
    private func makeFixture(minutes: [Int], startDate: Date = .now) throws -> ReconcilerFixture {
        let schema = Schema([Medication.self, DoseSchedule.self, DoseEvent.self, InventoryEvent.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let medication = Medication(name: "Example")
        context.insert(medication)
        let schedules = minutes.map { minute in
            let schedule = DoseSchedule(
                medicationID: medication.id,
                minutesAfterMidnight: minute,
                startDate: startDate
            )
            context.insert(schedule)
            return schedule
        }
        try context.save()
        return ReconcilerFixture(
            container: container,
            context: context,
            medicationID: medication.id,
            schedules: schedules
        )
    }

    private func definitions(minutes: [Int], quantity: Double = 1) -> [ScheduleDefinition] {
        minutes.map {
            ScheduleDefinition(
                minutesAfterMidnight: $0,
                doseQuantity: quantity,
                weekdayMask: 0b1111111
            )
        }
    }
}

private struct ReconcilerFixture {
    let container: ModelContainer
    let context: ModelContext
    let medicationID: UUID
    let schedules: [DoseSchedule]
}
