import XCTest
@testable import Meds

/// "Why this date?" explains the forecast's own arithmetic: its lines add up
/// to the ledger, its assumptions are the forecast's, its conclusion is the
/// forecast, and its alert is the one the planner schedules.
final class ForecastBreakdownTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func september(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func logged(_ schedule: DoseSchedule, on day: Int, healthSampleID: UUID? = nil) -> DoseEvent {
        let date = september(day, schedule.minutesAfterMidnight / 60)
        return DoseEvent(medicationID: schedule.medicationID, scheduleID: schedule.id, scheduledAt: date, recordedAt: date,
                         doseQuantity: schedule.doseQuantity, status: .taken, healthSampleID: healthSampleID)
    }

    private func breakdown(_ medication: Medication, _ schedules: [DoseSchedule], _ inventory: [InventoryEvent],
                           _ doses: [DoseEvent] = [], now: Date) -> ForecastBreakdown {
        ForecastEngine.breakdown(medication: medication, schedules: schedules, inventoryEvents: inventory, doseEvents: doses, now: now, calendar: calendar)
    }

    private func forecast(_ medication: Medication, _ schedules: [DoseSchedule], _ inventory: [InventoryEvent],
                          _ doses: [DoseEvent] = [], now: Date) -> SupplyForecast {
        ForecastEngine.forecast(medication: medication, schedules: schedules, inventoryEvents: inventory, doseEvents: doses, now: now, calendar: calendar)
    }

    /// The anchor, plus refills and the other changes, less the doses taken
    /// since, as the steps list them.
    private func walkedBalance(_ breakdown: ForecastBreakdown) -> Double? {
        var total: Double?
        for step in breakdown.steps {
            switch step {
            case let .anchor(anchor): total = anchor.balance
            case let .refills(tally): total = total.map { $0 + tally.quantity }
            case let .adjustment(adjustment): total = total.map { $0 + adjustment.quantity }
            case let .taken(tally, _): total = total.map { $0 - tally.quantity }
            default: break
            }
        }
        return total
    }

    /// A tablet at 08:00 and at 20:00, added and counted at 07:00 on the 1st.
    private func twiceDaily(count: Double = 30) -> (Medication, [DoseSchedule], InventoryEvent) {
        let medication = Medication(name: "Mycophenolate", createdAt: september(1, 7))
        let schedules = [8, 20].map { DoseSchedule(medicationID: medication.id, minutesAfterMidnight: $0 * 60, doseQuantity: 1, startDate: september(1, 7)) }
        return (medication, schedules, InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: count, reason: .openingCount))
    }

    func testTheLinesAddUpToTheLedgerAndConcludeWithTheForecast() throws {
        let (medication, schedules, opening) = twiceDaily()
        let beforeCount = [logged(schedules[0], on: 1), logged(schedules[1], on: 1), logged(schedules[0], on: 2)]
        let correction = InventoryEvent(
            medicationID: medication.id, date: september(4, 12),
            delta: ForecastEngine.correctionDelta(medicationID: medication.id, actualCount: 24, inventoryEvents: [opening], doseEvents: beforeCount),
            reason: .correction
        )
        let inventory = [
            opening, correction,
            InventoryEvent(medicationID: medication.id, date: september(6, 12), delta: 30, reason: .refill),
            InventoryEvent(medicationID: medication.id, date: september(7, 12), delta: -2, reason: .lost),
            InventoryEvent(medicationID: medication.id, date: september(7, 13), delta: -1, reason: .discarded)
        ]
        let sinceCount = [
            logged(schedules[1], on: 4),
            logged(schedules[0], on: 5, healthSampleID: UUID()),
            DoseEvent(medicationID: medication.id, recordedAt: september(6, 8, 10), doseQuantity: 1, status: .taken),
            DoseEvent(medicationID: medication.id, scheduleID: schedules[0].id, scheduledAt: september(7, 8), recordedAt: september(7, 8), doseQuantity: 1, status: .skipped),
            DoseEvent(medicationID: medication.id, recordedAt: september(3, 12), doseQuantity: 5, status: .taken, note: DoseEvent.appleHealthNote, countsTowardSupply: false)
        ]
        let doses = beforeCount + sinceCount
        let now = september(9, 7)
        let result = breakdown(medication, schedules, inventory, doses, now: now)
        let expected = forecast(medication, schedules, inventory, doses, now: now)
        let raw = ForecastEngine.rawSupplyBalance(medicationID: medication.id, inventoryEvents: inventory, doseEvents: doses)

        XCTAssertEqual(result.anchor, ForecastBreakdown.Anchor(kind: .count, date: september(4, 12), balance: 24))
        XCTAssertEqual(result.refills, ForecastBreakdown.Tally(count: 1, quantity: 30))
        XCTAssertEqual(result.adjustments, [
            ForecastBreakdown.Adjustment(reason: .lost, count: 1, quantity: -2),
            ForecastBreakdown.Adjustment(reason: .discarded, count: 1, quantity: -1)
        ])
        XCTAssertEqual(result.taken, ForecastBreakdown.Tally(count: 3, quantity: 3), "the skip and the imported history are not taken from the count")
        XCTAssertEqual(result.takenFromHealth, 1)
        XCTAssertEqual(raw, 48)
        XCTAssertEqual(result.ledgerBalance, raw)
        XCTAssertEqual(walkedBalance(result), raw, "24 + 30 − 2 − 1 − 3")

        XCTAssertEqual(result.forecast, expected)
        XCTAssertEqual(result.assumed.count, expected.assumedDoses)
        XCTAssertEqual(result.assumed, ForecastBreakdown.Tally(count: 5, quantity: 5),
                       "the 5th to the 8th's evenings and the 8th's morning; the 6th's is the Take Now dose, the 7th's was skipped")
        XCTAssertEqual(result.conclusion, .runsOut(date: try XCTUnwrap(expected.depletionDate), daysRemaining: try XCTUnwrap(expected.daysRemaining)))
        XCTAssertEqual(result.use, .daily(quantity: 2))
        XCTAssertNil(result.courseEnd)

        guard case .anchor = result.steps.first, case .alert = result.steps.last else {
            return XCTFail("\(result.steps)")
        }
        XCTAssertEqual(result.steps.count, 10)
        let lines = result.lines(calendar: calendar)
        let dayText = { ForecastEngine.dayText($0, calendar: self.calendar) }
        XCTAssertEqual(Array(lines.prefix(7)), [
            "Counted 24 tablets on \(dayText(september(4))).",
            "1 refill since then: +30 tablets.",
            "Lost or damaged since then: −2 tablets.",
            "Discarded since then: −1 tablet.",
            "3 doses logged as taken since then, 1 of them from Apple Health: −3 tablets.",
            "On record: 48 tablets.",
            "5 scheduled doses since the last count weren't logged (5 tablets). If they were taken, that leaves 43 tablets."
        ])
        XCTAssertEqual(lines[7], "The schedule uses 2 tablets a day.")
        XCTAssertEqual(lines[8], "Runs out around \(dayText(try XCTUnwrap(expected.depletionDate))). \(expected.explanation)")
        XCTAssertTrue(lines[9].hasPrefix("The low-supply alert comes"), lines[9])
    }

    func testTheWalkStartsFromAnOpeningCountARefillOntoNothingOrNothingAtAll() {
        let (medication, schedules, opening) = twiceDaily()
        let started = breakdown(medication, schedules, [opening], now: september(1, 7, 30))
        XCTAssertEqual(started.anchor, ForecastBreakdown.Anchor(kind: .openingCount, date: september(1, 7), balance: 30))
        XCTAssertEqual(started.lines(calendar: calendar).first, "Started with 30 tablets on \(ForecastEngine.dayText(september(1), calendar: calendar)).")
        XCTAssertEqual(started.taken, ForecastBreakdown.Tally(count: 0, quantity: 0))
        XCTAssertEqual(started.lines(calendar: calendar)[1], "No doses logged as taken since then.")

        let (other, otherSchedules, nothing) = twiceDaily(count: 0)
        let refill = InventoryEvent(medicationID: other.id, date: september(3, 12), delta: 30, reason: .refill)
        let refilled = breakdown(other, otherSchedules, [nothing, refill], now: september(5, 7))
        XCTAssertEqual(refilled.anchor, ForecastBreakdown.Anchor(kind: .refillOntoEmpty, date: september(3, 12), balance: 30))
        XCTAssertEqual(refilled.refills.count, 0, "the refill is the anchor, not one since it")
        XCTAssertEqual(refilled.assumed.count, refilled.forecast.assumedDoses)
        XCTAssertEqual(refilled.assumed.count, 3)
        XCTAssertEqual(walkedBalance(refilled), 30)
        XCTAssertTrue(refilled.lines(calendar: calendar).contains("3 scheduled doses since the last refill weren't logged (3 tablets). If they were taken, that leaves 27 tablets."))

        let neverCounted = Medication(name: "Sulfamethoxazole", createdAt: september(1, 7))
        let empty = breakdown(neverCounted, [], [], now: september(2))
        XCTAssertEqual(empty.anchor, ForecastBreakdown.Anchor(kind: .added, date: september(1, 7), balance: 0))
        XCTAssertEqual(empty.conclusion, .outOfSupply)
        XCTAssertNil(empty.alert, "nothing on hand is its own warning, and the planner writes no alert for it")
        XCTAssertEqual(empty.lines(calendar: calendar).last, "No confirmed supply remains.")
    }

    /// The alert date is the planner's, compared with the refill alert it
    /// actually plans: with the person's lead, with the prescriber's when no
    /// refills are left, and not at all when a refill in progress stands in.
    @MainActor
    func testTheAlertIsTheOneThePlannerPlans() throws {
        let now = september(1, 7, 30)
        func planned(_ medication: Medication, _ schedules: [DoseSchedule], _ inventory: [InventoryEvent], at moment: Date = now) -> [PlannedNotification] {
            let plan = NotificationPlanBuilder.make(medication: medication, schedules: schedules, inventoryEvents: inventory, doseEvents: [], now: moment, calendar: calendar)
            return NotificationPlanner.plan(for: [plan], now: moment, calendar: calendar).notifications
        }
        func trigger(_ kind: PlannedNotificationKind, in notifications: [PlannedNotification]) -> Date? {
            notifications.compactMap { notification -> Date? in
                guard notification.kind == kind, case let .date(date) = notification.trigger else { return nil }
                return date
            }.first
        }

        let (medication, schedules, opening) = twiceDaily()
        let usual = try XCTUnwrap(breakdown(medication, schedules, [opening], now: now).alert)
        XCTAssertEqual(usual.state, .planned)
        XCTAssertEqual(usual.leadDays, 7)
        XCTAssertFalse(usual.needsPrescriber)
        XCTAssertEqual(usual.date, september(8, 9), "run-out on the 15th, a week ahead, at nine")
        XCTAssertEqual(trigger(.refill, in: planned(medication, schedules, [opening])), usual.date)

        medication.refillsRemaining = 0
        let prescriber = try XCTUnwrap(breakdown(medication, schedules, [opening], now: now).alert)
        XCTAssertEqual(prescriber.leadDays, SupplyAttention.prescriberLeadDays)
        XCTAssertEqual(prescriber.chosenLeadDays, 7)
        XCTAssertTrue(prescriber.needsPrescriber)
        XCTAssertEqual(prescriber.date, september(5, 9))
        XCTAssertEqual(trigger(.refill, in: planned(medication, schedules, [opening])), prescriber.date)
        XCTAssertTrue(breakdown(medication, schedules, [opening], now: now).lines(calendar: calendar).last?.contains("No refills are left") == true)

        medication.refillsRemaining = 2
        medication.refillStatus = .ready
        medication.refillStatusDate = september(7)
        let paused = try XCTUnwrap(breakdown(medication, schedules, [opening], now: now).alert)
        let notifications = planned(medication, schedules, [opening])
        XCTAssertNil(trigger(.refill, in: notifications), "a refill due before the alert stands in for it")
        XCTAssertEqual(paused.state, .pausedByRefill(checkAt: september(9, 9)))
        XCTAssertEqual(trigger(.refillCheck, in: notifications), september(9, 9))

        medication.refillStatus = .none
        medication.refillStatusDate = nil
        medication.refillRemindersEnabled = false
        XCTAssertEqual(breakdown(medication, schedules, [opening], now: now).alert?.state, .off)
        XCTAssertNil(trigger(.refill, in: planned(medication, schedules, [opening])))

        medication.refillRemindersEnabled = true
        let later = september(10, 7, 30)
        let recount = InventoryEvent(medicationID: medication.id, date: september(10, 7), delta: -20, reason: .correction)
        let passed = try XCTUnwrap(breakdown(medication, schedules, [opening, recount], now: later).alert)
        XCTAssertEqual(passed.state, .passed, "ten left on the 10th runs out on the 14th; a week ahead was the 7th")
        XCTAssertNil(trigger(.refill, in: planned(medication, schedules, [opening, recount], at: later)))
    }

    func testAsNeededUseIsTheForecastsRate() {
        let medication = Medication(name: "Ondansetron", isAsNeeded: true, createdAt: september(1, 7))
        let opening = InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: 20, reason: .openingCount)
        let doses = (1...4).map { DoseEvent(medicationID: medication.id, recordedAt: september($0, 12), doseQuantity: 1, status: .taken) }
        let now = september(4, 18)
        let result = breakdown(medication, [], [opening], doses, now: now)

        XCTAssertEqual(result.forecast, forecast(medication, [], [opening], doses, now: now))
        XCTAssertEqual(result.use, .asNeeded(ForecastBreakdown.AsNeededRate(doseCount: 4, quantity: 4, windowDays: 4)))
        XCTAssertEqual(result.assumed.count, 0)
        XCTAssertEqual(result.taken, ForecastBreakdown.Tally(count: 4, quantity: 4))
        XCTAssertEqual(walkedBalance(result), 16)
        XCTAssertEqual(result.conclusion, .runsOut(date: result.forecast.depletionDate!, daysRemaining: 16))
        XCTAssertTrue(result.lines(calendar: calendar).contains("As-needed use: 4 tablets over the last 4 days, about 1 tablet a day."))

        let thin = breakdown(medication, [], [opening], Array(doses.prefix(2)), now: now)
        XCTAssertNil(thin.use)
        XCTAssertEqual(thin.conclusion, .unknown)
        XCTAssertNil(thin.alert)
        XCTAssertEqual(thin.lines(calendar: calendar).last, "Timing unknown. Log at least three as-needed doses to create an estimate.")
    }

    func testUnknownTimingHasNoAlertAndSaysWhy() {
        let medication = Medication(name: "Magnesium", createdAt: september(1, 7))
        let opening = InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: 60, reason: .openingCount)
        let unscheduled = breakdown(medication, [], [opening], now: september(2))
        XCTAssertEqual(unscheduled.conclusion, .unknown)
        XCTAssertNil(unscheduled.use)
        XCTAssertNil(unscheduled.alert)
        XCTAssertEqual(unscheduled.lines(calendar: calendar).last, "Timing unknown. Add a schedule to estimate when this supply will run out.")

        // Weekdays that differ are a week's use, not a day's.
        let weekly = [
            DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, doseQuantity: 1, weekdayMask: (1 << 1) | (1 << 3) | (1 << 5), startDate: september(1, 7)),
            DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 21 * 60, doseQuantity: 1, startDate: september(1, 7))
        ]
        let result = breakdown(medication, weekly, [opening], now: september(1, 7, 30))
        XCTAssertEqual(result.use, .weekly(quantity: 10))
        XCTAssertTrue(result.lines(calendar: calendar).contains("The schedule uses 10 tablets a week, about 1.43 tablets a day."))
    }

    /// A covered course and a finished one have no run-out day, so no alert;
    /// a count needed has none to warn ahead of.
    func testCoursesAndCountsNeededConcludeAsTheForecastDoes() throws {
        let medication = Medication(name: "Valganciclovir", createdAt: september(1, 7))
        let end = ScheduleEngine.normalizedEndDate(forDay: september(10), calendar: calendar)
        let schedule = DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, doseQuantity: 2, startDate: september(1, 7), endDate: end)
        let opening = InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: 24, reason: .openingCount)

        let covered = breakdown(medication, [schedule], [opening], now: september(1, 7, 30))
        XCTAssertEqual(covered.conclusion, .courseCovered(end: end, leftover: 4))
        XCTAssertEqual(covered.courseEnd, end)
        XCTAssertNil(covered.alert)
        let lines = covered.lines(calendar: calendar)
        XCTAssertEqual(lines.suffix(2), [
            "The course's last day is \(ForecastEngine.dayText(end, calendar: calendar)).",
            "Enough to finish the course on \(ForecastEngine.dayText(end, calendar: calendar)), with 4 tablets left."
        ])

        let finished = breakdown(medication, [schedule], [opening], now: september(11, 9))
        XCTAssertEqual(finished.conclusion, .courseFinished(end: end))
        XCTAssertEqual(finished.forecast, forecast(medication, [schedule], [opening], now: september(11, 9)))
        XCTAssertNil(finished.alert)

        let ten = InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: 10, reason: .openingCount)
        let stale = breakdown(medication, [schedule], [ten], now: september(8, 7))
        XCTAssertEqual(stale.conclusion, .countNeeded)
        XCTAssertEqual(stale.assumed.count, stale.forecast.assumedDoses)
        XCTAssertEqual(stale.assumed.quantity, 14, "seven mornings of two")
        XCTAssertNil(stale.alert)
        XCTAssertTrue(stale.lines(calendar: calendar).contains("7 scheduled doses since the last count weren't logged (14 tablets). If they were taken, none of the supply on record is left."))
    }
}
