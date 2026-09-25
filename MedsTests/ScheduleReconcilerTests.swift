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
