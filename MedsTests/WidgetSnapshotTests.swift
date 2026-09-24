import XCTest
@testable import Meds

/// What the widgets say, decided over plain values.
final class WidgetSnapshotTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: hour, minute: minute))!
    }

    private func medications() -> (tacrolimus: Medication, furosemide: Medication, schedules: [DoseSchedule]) {
        let tacrolimus = Medication(name: "Tacrolimus", form: .capsule, accentIndex: 0)
        let furosemide = Medication(name: "Furosemide", form: .tablet, accentIndex: 1)
        let start = date(0)
        let schedules = [
            DoseSchedule(medicationID: tacrolimus.id, minutesAfterMidnight: 8 * 60, doseQuantity: 1, startDate: start),
            DoseSchedule(medicationID: tacrolimus.id, minutesAfterMidnight: 20 * 60, doseQuantity: 1, startDate: start),
            DoseSchedule(medicationID: furosemide.id, minutesAfterMidnight: 8 * 60, doseQuantity: 2, startDate: start)
        ]
        return (tacrolimus, furosemide, schedules)
    }

    // MARK: - Next dose

    func testTheNextDoseIsTheEarliestUnloggedTimeWithEverythingDueAtIt() throws {
        let (tacrolimus, furosemide, schedules) = medications()
        let snapshot = NextDoseSnapshot.make(medications: [tacrolimus, furosemide], schedules: schedules, doseEvents: [], now: date(7), calendar: calendar)

        guard case let .next(time, items) = snapshot.state else { return XCTFail("\(snapshot.state)") }
        XCTAssertEqual(time, date(8))
        XCTAssertEqual(items.map(\.displayName), ["Furosemide", "Tacrolimus"])
        XCTAssertEqual(items[0].quantityText, "2 tablets")
        XCTAssertNil(snapshot.actionable, "two medications at one time are never one tap")
        XCTAssertFalse(snapshot.isOverdue)
    }

    func testALoggedSlotGivesWayToTheNextOne() throws {
        let (tacrolimus, furosemide, schedules) = medications()
        let morning = ScheduleEngine.doses(schedules: schedules, medicationID: tacrolimus.id, onDayOf: date(7), calendar: calendar)[0]
        let furosemideMorning = ScheduleEngine.doses(schedules: schedules, medicationID: furosemide.id, onDayOf: date(7), calendar: calendar)[0]
        let logged = [
            DoseEvent(medicationID: tacrolimus.id, scheduleID: morning.scheduleID, scheduledAt: morning.date, doseQuantity: 1, status: .taken),
            DoseEvent(medicationID: furosemide.id, scheduleID: furosemideMorning.scheduleID, scheduledAt: furosemideMorning.date, doseQuantity: 2, status: .skipped)
        ]

        let snapshot = NextDoseSnapshot.make(medications: [tacrolimus, furosemide], schedules: schedules, doseEvents: logged, now: date(9), calendar: calendar)

        guard case let .next(time, items) = snapshot.state else { return XCTFail("\(snapshot.state)") }
        XCTAssertEqual(time, date(20))
        XCTAssertEqual(items.map(\.displayName), ["Tacrolimus"])
        XCTAssertNil(snapshot.actionable, "eight in the evening is still upcoming at nine in the morning")
    }

    func testASingleDueDoseIsActionableAndAnOverdueOneSaysSo() {
        let (tacrolimus, _, schedules) = medications()
        let due = NextDoseSnapshot.make(medications: [tacrolimus], schedules: schedules, doseEvents: [], now: date(7, 45), calendar: calendar)
        XCTAssertEqual(due.actionable?.displayName, "Tacrolimus")
        XCTAssertFalse(due.isOverdue)

        let overdue = NextDoseSnapshot.make(medications: [tacrolimus], schedules: schedules, doseEvents: [], now: date(11), calendar: calendar)
        XCTAssertEqual(overdue.actionable?.displayName, "Tacrolimus", "an overdue dose is still the one to log")
        XCTAssertTrue(overdue.isOverdue)
        if case let .next(time, _) = overdue.state { XCTAssertEqual(time, date(8), "the morning dose comes before the evening one, even late") }
    }

    func testAllLoggedNothingScheduledAndNoMedications() {
        let (tacrolimus, _, schedules) = medications()
        let doses = ScheduleEngine.doses(schedules: schedules, medicationID: tacrolimus.id, onDayOf: date(7), calendar: calendar)
        let logged = doses.map { DoseEvent(medicationID: tacrolimus.id, scheduleID: $0.scheduleID, scheduledAt: $0.date, doseQuantity: 1, status: .taken) }
        XCTAssertEqual(NextDoseSnapshot.make(medications: [tacrolimus], schedules: schedules, doseEvents: logged, now: date(21), calendar: calendar).state, .allLogged(count: 2))

        let asNeeded = Medication(name: "Melatonin", isAsNeeded: true)
        XCTAssertEqual(NextDoseSnapshot.make(medications: [asNeeded], schedules: [], doseEvents: [], now: date(9), calendar: calendar).state, .nothingScheduled)
        XCTAssertEqual(NextDoseSnapshot.make(medications: [], schedules: [], doseEvents: [], now: date(9), calendar: calendar).state, .noMedications)

        let archived = Medication(name: "Old", isArchived: true)
        XCTAssertEqual(NextDoseSnapshot.make(medications: [archived], schedules: [], doseEvents: [], now: date(9), calendar: calendar).state, .noMedications)
    }

    func testTheTimelineChangesAtDoseTimesTheirWindowsAndMidnight() {
        let (tacrolimus, _, schedules) = medications()
        let times = NextDoseSnapshot.changeTimes(medications: [tacrolimus], schedules: schedules, doseEvents: [], now: date(9), calendar: calendar)
        XCTAssertEqual(times, [date(19, 30), date(20), date(20, 30).addingTimeInterval(1), date(24)], "the morning dose is behind; the evening one has a window either side")
    }

    // MARK: - Runs out next

    func testMedicationsAreOrderedByWhenTheyRunOut() {
        let (tacrolimus, furosemide, schedules) = medications()
        let unknown = Medication(name: "Lotion", isAsNeeded: true)
        let inventory = [
            InventoryEvent(medicationID: tacrolimus.id, delta: 10, reason: .openingCount),
            InventoryEvent(medicationID: furosemide.id, delta: 60, reason: .openingCount),
            InventoryEvent(medicationID: unknown.id, delta: 5, reason: .openingCount)
        ]
        let snapshot = RunsOutSnapshot.make(medications: [unknown, furosemide, tacrolimus], schedules: schedules, inventoryEvents: inventory, doseEvents: [], now: date(9), calendar: calendar)

        XCTAssertEqual(snapshot.items.map(\.displayName), ["Tacrolimus", "Furosemide", "Lotion"])
        XCTAssertEqual(snapshot.soonest?.daysRemaining, 5, "ten capsules, one tonight and two a day after, run out on the sixth morning")
        XCTAssertTrue(snapshot.soonest?.needsAttention == true)
        XCTAssertNil(snapshot.items[2].daysRemaining)
    }

    func testARefillOnItsWayNeedsNoAttention() {
        let item = RunsOutSnapshot.Item(medicationID: UUID(), displayName: "Tacrolimus", daysRemaining: 3, depletionDate: date(9), refillLeadDays: 7,
                                        refillsRemaining: nil, refillInProgress: true, daysSinceRefillDate: nil, onHand: true, accentIndex: 0)
        XCTAssertFalse(item.needsAttention)
    }

    private func item(daysRemaining: Int?, onHand: Bool = true, refillInProgress: Bool, daysSinceRefillDate: Int? = nil) -> RunsOutSnapshot.Item {
        RunsOutSnapshot.Item(medicationID: UUID(), displayName: "Furosemide", daysRemaining: daysRemaining, depletionDate: date(9), refillLeadDays: 7,
                             refillsRemaining: nil, refillInProgress: refillInProgress, daysSinceRefillDate: daysSinceRefillDate, onHand: onHand, accentIndex: 0)
    }

    /// "Refill on its way" is said only while the refill can still answer for
    /// the supply. At zero it used to be what the widget said instead of out.
    func testARefillOnItsWayIsNeverSaidOverAnEmptySupply() {
        let out = item(daysRemaining: 0, onHand: false, refillInProgress: true, daysSinceRefillDate: 0)
        XCTAssertEqual(out.line, "Out of supply")
        XCTAssertEqual(out.tone, .out)
        XCTAssertTrue(out.needsAttention)

        let lastDose = item(daysRemaining: 0, refillInProgress: true, daysSinceRefillDate: -1)
        XCTAssertEqual(lastDose.line, "Out of supply")

        let onItsWay = item(daysRemaining: 5, refillInProgress: true, daysSinceRefillDate: -1)
        XCTAssertEqual(onItsWay.line, "Refill on its way")
        XCTAssertEqual(onItsWay.tone, .steady)

        let late = item(daysRemaining: 5, refillInProgress: true, daysSinceRefillDate: 3)
        XCTAssertEqual(late.line, "About 5 days left")
        XCTAssertEqual(late.tone, .attention)
        XCTAssertTrue(late.needsAttention)

        let dueAfterRunOut = item(daysRemaining: 5, refillInProgress: true, daysSinceRefillDate: -9)
        XCTAssertEqual(dueAfterRunOut.line, "About 5 days left", "a refill due after the supply is gone is not on its way in time")
        XCTAssertEqual(dueAfterRunOut.tone, .attention)

        XCTAssertEqual(item(daysRemaining: nil, refillInProgress: false).tone, .unknown)
        XCTAssertEqual(item(daysRemaining: 20, refillInProgress: false).line, "About 20 days left")
    }

    func testTheSnapshotCountsTheRefillsLatenessWhenItIsMade() throws {
        let (_, furosemide, schedules) = medications()
        furosemide.refillStatus = .requested
        furosemide.refillStatusDate = calendar.date(byAdding: .day, value: -3, to: date(9))
        let inventory = [InventoryEvent(medicationID: furosemide.id, delta: 10, reason: .openingCount)]
        let snapshot = RunsOutSnapshot.make(medications: [furosemide], schedules: schedules, inventoryEvents: inventory, doseEvents: [], now: date(9), calendar: calendar)
        let soonest = try XCTUnwrap(snapshot.soonest)

        XCTAssertEqual(soonest.daysSinceRefillDate, 3)
        XCTAssertTrue(soonest.needsAttention, "three days late with five days left")
        XCTAssertNotEqual(soonest.line, "Refill on its way")
    }
}
