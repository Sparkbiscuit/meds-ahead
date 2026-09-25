import XCTest
@testable import Meds

final class ForecastEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testScheduledSupplyDepletesOnThirtiethDose() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 7)))
        let medication = Medication(name: "Example", form: .tablet)
        let schedule = DoseSchedule(
            medicationID: medication.id,
            minutesAfterMidnight: 8 * 60,
            doseQuantity: 1,
            startDate: now
        )
        let opening = InventoryEvent(medicationID: medication.id, date: now, delta: 30, reason: .openingCount)

        let result = ForecastEngine.forecast(
            medication: medication,
            schedules: [schedule],
            inventoryEvents: [opening],
            doseEvents: [],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(result.currentSupply, 30)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertEqual(result.daysRemaining, 29)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(result.depletionDate)), 30)
    }

    // MARK: - Unlogged doses

    private func september(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    /// A tablet at 08:00 and `eveningQuantity` at 20:00, added and counted at
    /// 07:00 on September 1st.
    private func twiceDaily(count: Double = 30, eveningQuantity: Double = 1, addedAt: Date? = nil) -> (Medication, [DoseSchedule], InventoryEvent) {
        let added = addedAt ?? september(1, 7)
        let medication = Medication(name: "Example", createdAt: added)
        let schedules = [
            DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, doseQuantity: 1, startDate: added),
            DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 20 * 60, doseQuantity: eveningQuantity, startDate: added)
        ]
        return (medication, schedules, InventoryEvent(medicationID: medication.id, date: added, delta: count, reason: .openingCount))
    }

    private func forecast(
        _ medication: Medication,
        _ schedules: [DoseSchedule],
        _ inventory: [InventoryEvent],
        _ doses: [DoseEvent] = [],
        now: Date
    ) -> SupplyForecast {
        ForecastEngine.forecast(medication: medication, schedules: schedules, inventoryEvents: inventory, doseEvents: doses, now: now, calendar: calendar)
    }

    private func logged(_ status: DoseEventStatus, _ schedule: DoseSchedule, at date: Date) -> DoseEvent {
        DoseEvent(medicationID: schedule.medicationID, scheduleID: schedule.id, scheduledAt: date, recordedAt: date,
                  doseQuantity: schedule.doseQuantity, status: status)
    }

    /// Counting only the doses still to come let every unlogged day push the
    /// run-out date a day later, so the refill alert keyed to it never came.
    func testUnloggedDosesSinceTheCountAreAssumedTaken() throws {
        let (medication, schedules, opening) = twiceDaily()
        let now = september(6, 7)
        // A count confirmed at this moment assumes nothing: the rule as it was.
        let confirmedNow = InventoryEvent(medicationID: medication.id, date: now, delta: 0, reason: .correction)
        let asBefore = forecast(medication, schedules, [opening, confirmedNow], now: now)
        XCTAssertEqual(asBefore.depletionDate, september(20, 20))
        XCTAssertEqual(asBefore.assumedDoses, 0)
        XCTAssertEqual(asBefore.confidence, .high)

        let result = forecast(medication, schedules, [opening], now: now)
        XCTAssertEqual(result.currentSupply, 30, "the on-hand number stays the ledger's")
        XCTAssertEqual(result.assumedDoses, 10)
        XCTAssertEqual(result.depletionDate, september(15, 20))
        XCTAssertEqual(result.daysRemaining, 9)
        let earlier = calendar.dateComponents([.day], from: try XCTUnwrap(result.depletionDate), to: try XCTUnwrap(asBefore.depletionDate)).day
        XCTAssertEqual(earlier, 5, "five unlogged days bring the run-out five days nearer")
        XCTAssertEqual(result.confidence, .estimated)
        XCTAssertEqual(result.explanation, "Assumes the 10 scheduled doses since your last count that weren't logged were taken.")
        XCTAssertFalse(result.needsCount)
    }

    /// The morning of the day a medication was added is not a dose it missed.
    func testOnlyDosesSinceTheMedicationWasAddedAreAssumed() {
        let (medication, schedules, opening) = twiceDaily(addedAt: september(1, 15))
        let result = forecast(medication, schedules, [opening], now: september(1, 21))
        XCTAssertEqual(result.assumedDoses, 1)
        XCTAssertEqual(result.explanation, "Assumes the 1 scheduled dose since your last count that wasn't logged was taken.")
    }

    func testALoggedDoseIsNeverAssumedAndNeitherIsASkip() {
        let (medication, schedules, opening) = twiceDaily()
        let doses = [
            logged(.skipped, schedules[0], at: september(2, 8)),
            logged(.taken, schedules[1], at: september(3, 20))
        ]
        let result = forecast(medication, schedules, [opening], doses, now: september(6, 7))
        XCTAssertEqual(result.currentSupply, 29, "only the taken dose left the bottle")
        XCTAssertEqual(result.assumedDoses, 8)
        // 29 on record less 8 assumed leaves 21: the 21st dose from the 6th.
        XCTAssertEqual(result.depletionDate, september(16, 8))
    }

    /// Take Now with nothing due logs a dose outside any slot. It is still one
    /// of that day's doses: the nearest one, here the evening's two tablets.
    func testAnUnscheduledDoseCoversTheNearestSlotThatDay() {
        let (medication, schedules, opening) = twiceDaily(eveningQuantity: 2)
        let now = september(6, 7)
        let nothingLogged = forecast(medication, schedules, [opening], now: now)
        let takeNow = DoseEvent(medicationID: medication.id, recordedAt: september(2, 19), doseQuantity: 2, status: .taken)

        let result = forecast(medication, schedules, [opening], [takeNow], now: now)
        XCTAssertEqual(result.assumedDoses, nothingLogged.assumedDoses - 1)
        XCTAssertEqual(result.depletionDate, nothingLogged.depletionDate, "the two tablets leave the ledger instead of the assumption")

        // History imported from Health with the medication predates the count.
        let imported = DoseEvent(medicationID: medication.id, recordedAt: september(2, 19), doseQuantity: 2, status: .taken,
                                 note: DoseEvent.appleHealthNote, countsTowardSupply: false)
        XCTAssertEqual(forecast(medication, schedules, [opening], [imported], now: now).assumedDoses, nothingLogged.assumedDoses)
    }

    func testACorrectionReanchorsAndARefillDoesNot() {
        let (medication, schedules, opening) = twiceDaily()
        let now = september(6, 7)
        let correction = InventoryEvent(medicationID: medication.id, date: september(4, 12), delta: -6, reason: .correction)
        let corrected = forecast(medication, schedules, [opening, correction], now: now)
        XCTAssertEqual(corrected.currentSupply, 24)
        XCTAssertEqual(corrected.assumedDoses, 3, "the 4th's evening and the 5th's two")

        let refill = InventoryEvent(medicationID: medication.id, date: september(4, 12), delta: 30, reason: .refill)
        let refilled = forecast(medication, schedules, [opening, refill], now: now)
        XCTAssertEqual(refilled.currentSupply, 60)
        XCTAssertEqual(refilled.assumedDoses, 10, "a refill adds stock but confirms nothing about the doses before it")

        // With no count at all, the doses since the medication was added are the ones assumed.
        XCTAssertEqual(forecast(medication, schedules, [refill], now: now).assumedDoses, 10)

        // A count dated after now leaves nothing to assume.
        let later = InventoryEvent(medicationID: medication.id, date: september(7, 7), delta: 0, reason: .correction)
        XCTAssertEqual(forecast(medication, schedules, [opening, later], now: now).assumedDoses, 0)
    }

    /// Unlogged doses that would use up everything on record do not make the
    /// supply zero: they make the count unknown, which a count answers.
    func testAStaleCountAsksForACountRatherThanReportingNoneLeft() {
        let (medication, schedules, opening) = twiceDaily(count: 6)
        let now = september(6, 7)
        let result = forecast(medication, schedules, [opening], now: now)

        XCTAssertTrue(result.needsCount)
        XCTAssertEqual(result.currentSupply, 6)
        XCTAssertEqual(result.daysRemaining, 0)
        XCTAssertEqual(result.depletionDate, now)
        XCTAssertEqual(result.assumedDoses, 10)
        XCTAssertEqual(result.confidence, .estimated)
        XCTAssertTrue(result.explanation.contains("Count what is left"), result.explanation)
    }

    /// The assumption shapes the run-out date and nothing else: no event is
    /// written, and the ledger, a correction and the dose calendar still read
    /// only what was recorded.
    func testTheAssumptionLeavesTheLedgerAndAdherenceAlone() {
        let (medication, schedules, opening) = twiceDaily()
        let now = september(6, 7)
        let doses = [logged(.taken, schedules[0], at: september(2, 8))]
        let adherence = AdherenceSummary.month(containing: now, medicationID: medication.id, schedules: schedules, doseEvents: doses, now: now, calendar: calendar)

        XCTAssertEqual(forecast(medication, schedules, [opening], doses, now: now).assumedDoses, 9)
        XCTAssertEqual(ForecastEngine.rawSupplyBalance(medicationID: medication.id, inventoryEvents: [opening], doseEvents: doses), 29)
        XCTAssertEqual(ForecastEngine.correctionDelta(medicationID: medication.id, actualCount: 20, inventoryEvents: [opening], doseEvents: doses), -9)
        XCTAssertEqual(AdherenceSummary.month(containing: now, medicationID: medication.id, schedules: schedules, doseEvents: doses, now: now, calendar: calendar), adherence)
        XCTAssertEqual(adherence[2].state, .missed, "an assumed dose is not a logged one")
    }

    func testAnAsNeededForecastAssumesNothing() {
        let medication = Medication(name: "Example", isAsNeeded: true, createdAt: september(1, 7))
        let opening = InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: 20, reason: .openingCount)
        let doses = (1...4).map { DoseEvent(medicationID: medication.id, recordedAt: september($0, 12), doseQuantity: 1, status: .taken) }
        // A schedule left behind from before it was made as-needed.
        let stale = DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, doseQuantity: 1, startDate: september(1, 7))

        let result = forecast(medication, [stale], [opening], doses, now: september(6, 7))
        XCTAssertEqual(result, forecast(medication, [], [opening], doses, now: september(6, 7)))
        XCTAssertEqual(result.assumedDoses, 0)
        XCTAssertEqual(result.confidence, .estimated)
        XCTAssertTrue(result.explanation.contains("as-needed use"), result.explanation)
    }

    /// Stopping at a fixed look-back dropped the oldest unlogged dose each day
    /// as a new one came in, so an old count brought the slide back: here a
    /// count 500 days ago, refills since, and nothing logged.
    func testAnOldCountStillWeighsEveryUnloggedDose() throws {
        let now = september(6, 7)
        let added = try XCTUnwrap(calendar.date(byAdding: .day, value: -500, to: now))
        let medication = Medication(name: "Example", createdAt: added)
        let schedule = DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, doseQuantity: 1, startDate: added)
        var inventory = [InventoryEvent(medicationID: medication.id, date: added, delta: 60, reason: .openingCount)]
        for refill in 1...9 {
            inventory.append(InventoryEvent(medicationID: medication.id, date: try XCTUnwrap(calendar.date(byAdding: .day, value: 55 * refill, to: added)),
                                            delta: 60, reason: .refill))
        }

        let today = forecast(medication, [schedule], inventory, now: now)
        XCTAssertEqual(today.currentSupply, 600)
        XCTAssertEqual(today.assumedDoses, 500)
        XCTAssertEqual(today.daysRemaining, 99, "600 in and 500 assumed out leaves 100 doses, the first of them this morning")
        for later in [1, 7, 30] {
            let then = forecast(medication, [schedule], inventory, now: try XCTUnwrap(calendar.date(byAdding: .day, value: later, to: now)))
            XCTAssertEqual(then.depletionDate, today.depletionDate, "\(later) days on, with nothing logged, the date has not moved")
        }
    }

    /// Past doses stopped at the edge of the due window and doses to come
    /// started at now, so a dose inside its window was in neither and the
    /// run-out moved a dose later for half an hour. When that dose was the
    /// day's last, the refill alert moved a day and was then never planned.
    func testTheRunOutHoldsStillWhileADoseIsDue() {
        let (medication, schedules, opening) = twiceDaily()
        let doses = (1...12).flatMap { day in schedules.map { logged(.taken, $0, at: september(day, $0.minutesAfterMidnight / 60)) } }
        let dates = [september(13, 7, 50), september(13, 8, 10), september(13, 8, 40)].map {
            forecast(medication, schedules, [opening], doses, now: $0).depletionDate
        }
        XCTAssertEqual(dates, Array(repeating: september(15, 20), count: 3))

        // A dose logged a little early is in the ledger, and not also still to come.
        let early = DoseEvent(medicationID: medication.id, scheduleID: schedules[0].id, scheduledAt: september(13, 8),
                              recordedAt: september(13, 7, 45), doseQuantity: 1, status: .taken)
        let loggedEarly = forecast(medication, schedules, [opening], doses + [early], now: september(13, 7, 50))
        XCTAssertEqual(loggedEarly.currentSupply, 5)
        XCTAssertEqual(loggedEarly.depletionDate, september(15, 20))
    }

    /// On the day a medication is added, a dose given well after its time has
    /// no slot and is logged with Take Now. It stands for no other dose, so an
    /// evening that goes unlogged is still assumed.
    func testALateFirstDoseDoesNotStandForTheEvening() {
        let (medication, schedules, opening) = twiceDaily(addedAt: september(1, 9))
        let lateMorning = DoseEvent(medicationID: medication.id, recordedAt: september(1, 9, 5), doseQuantity: 1, status: .taken)
        let result = forecast(medication, schedules, [opening], [lateMorning], now: september(2, 7))
        XCTAssertEqual(result.currentSupply, 29)
        XCTAssertEqual(result.assumedDoses, 1, "the evening of the 1st")
    }

    func testSkippedDoseDoesNotReduceSupply() {
        let medication = Medication(name: "Example")
        let opening = InventoryEvent(medicationID: medication.id, delta: 10, reason: .openingCount)
        let taken = DoseEvent(medicationID: medication.id, doseQuantity: 2, status: .taken)
        let skipped = DoseEvent(medicationID: medication.id, doseQuantity: 4, status: .skipped)

        XCTAssertEqual(
            ForecastEngine.currentSupply(
                medicationID: medication.id,
                inventoryEvents: [opening],
                doseEvents: [taken, skipped]
            ),
            8
        )
    }

    /// A count long enough to outlast the forecast window is a mistyped one;
    /// it must not take the app down at launch on the way to being corrected.
    func testAHugeAsNeededCountForecastsWithoutTrapping() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 30, hour: 12)))
        let medication = Medication(name: "Example", isAsNeeded: true)
        let opening = InventoryEvent(medicationID: medication.id, date: now, delta: 1e20, reason: .openingCount)
        let doses = (1...3).map { daysAgo in
            DoseEvent(medicationID: medication.id, recordedAt: now.addingTimeInterval(-Double(daysAgo) * 86_400), doseQuantity: 1, status: .taken)
        }

        let result = ForecastEngine.forecast(
            medication: medication,
            schedules: [],
            inventoryEvents: [opening],
            doseEvents: doses,
            now: now,
            calendar: calendar
        )

        XCTAssertNil(result.depletionDate)
        XCTAssertNil(result.daysRemaining)
        XCTAssertEqual(result.confidence, .unknown)
        XCTAssertTrue(result.explanation.contains("beyond the forecast window"), result.explanation)
    }

    func testAsNeededMedicationRequiresHistory() {
        let medication = Medication(name: "Example", isAsNeeded: true)
        let opening = InventoryEvent(medicationID: medication.id, delta: 12, reason: .openingCount)
        let result = ForecastEngine.forecast(
            medication: medication,
            schedules: [],
            inventoryEvents: [opening],
            doseEvents: []
        )

        XCTAssertNil(result.depletionDate)
        XCTAssertEqual(result.confidence, .unknown)
        XCTAssertTrue(result.explanation.contains("three"))
    }

    /// Three doses taken this week divided across thirty days used to report four
    /// times the runway that existed — and an over-long supply estimate is the one
    /// direction this forecast must never be wrong in.
    func testAsNeededRateUsesTheHistoryThatExists() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 12)))
        let medication = Medication(name: "Ondansetron", isAsNeeded: true)
        let opening = InventoryEvent(medicationID: medication.id, date: now, delta: 20, reason: .openingCount)
        let doses = (0..<4).map { offset in
            DoseEvent(
                medicationID: medication.id,
                recordedAt: calendar.date(byAdding: .day, value: -offset, to: now) ?? now,
                doseQuantity: 1,
                status: .taken
            )
        }

        let result = ForecastEngine.forecast(
            medication: medication,
            schedules: [],
            inventoryEvents: [opening],
            doseEvents: doses,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(result.confidence, .estimated)
        // Twenty on hand less the four taken leaves sixteen, and four doses across
        // four days is one a day. Dividing those same four doses by a fixed thirty
        // reported a hundred and twenty days of supply instead of sixteen.
        XCTAssertEqual(result.daysRemaining, 16)
        XCTAssertTrue(result.explanation.contains("4 days"))
    }

    func testAsNeededRateOverAFullMonthIsUnchanged() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 12)))
        let medication = Medication(name: "Ondansetron", isAsNeeded: true)
        let opening = InventoryEvent(medicationID: medication.id, date: now, delta: 30, reason: .openingCount)
        let doses = [0, 14, 29].map { offset in
            DoseEvent(
                medicationID: medication.id,
                recordedAt: calendar.date(byAdding: .day, value: -offset, to: now) ?? now,
                doseQuantity: 1,
                status: .taken
            )
        }

        let result = ForecastEngine.forecast(
            medication: medication,
            schedules: [],
            inventoryEvents: [opening],
            doseEvents: doses,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(result.daysRemaining, 270, "twenty-seven left at a tenth of a dose a day")
        XCTAssertTrue(result.explanation.contains("30 days"))
    }

    /// History imported from Apple Health predates the count the person entered:
    /// it must give the as-needed estimate its rate without charging the supply.
    func testImportedHistoryFeedsTheRateButNotTheBalance() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 12)))
        let medication = Medication(name: "Ondansetron", isAsNeeded: true)
        let opening = InventoryEvent(medicationID: medication.id, date: now, delta: 20, reason: .openingCount)
        let imported = (1...4).map { offset in
            DoseEvent(
                medicationID: medication.id,
                recordedAt: calendar.date(byAdding: .day, value: -offset, to: now) ?? now,
                doseQuantity: 1,
                status: .taken,
                note: DoseEvent.appleHealthNote,
                countsTowardSupply: false
            )
        }

        let result = ForecastEngine.forecast(
            medication: medication,
            schedules: [],
            inventoryEvents: [opening],
            doseEvents: imported,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(result.currentSupply, 20, "the twenty were counted after those doses were taken")
        XCTAssertEqual(result.confidence, .estimated)
        // Four doses over the five days from the earliest to now: 0.8 a day, so
        // twenty last twenty-five days.
        XCTAssertEqual(result.daysRemaining, 25)
        XCTAssertEqual(
            ForecastEngine.correctionDelta(medicationID: medication.id, actualCount: 18, inventoryEvents: [opening], doseEvents: imported),
            -2,
            "a correction compares against the balance the imports never touched"
        )
    }

    func testCorrectionCanNeverDisplayNegativeSupply() {
        let medication = Medication(name: "Example")
        let opening = InventoryEvent(medicationID: medication.id, delta: 1, reason: .openingCount)
        let taken = DoseEvent(medicationID: medication.id, doseQuantity: 2, status: .taken)
        XCTAssertEqual(
            ForecastEngine.currentSupply(medicationID: medication.id, inventoryEvents: [opening], doseEvents: [taken]),
            0
        )
    }

    func testCorrectionDeltaUsesRawLedgerBalance() {
        let medication = Medication(name: "Example")
        let opening = InventoryEvent(medicationID: medication.id, delta: 1, reason: .openingCount)
        let taken = DoseEvent(medicationID: medication.id, doseQuantity: 3, status: .taken)

        let delta = ForecastEngine.correctionDelta(
            medicationID: medication.id,
            actualCount: 5,
            inventoryEvents: [opening],
            doseEvents: [taken]
        )
        let correction = InventoryEvent(
            medicationID: medication.id,
            delta: delta,
            reason: .correction
        )

        XCTAssertEqual(delta, 7)
        XCTAssertEqual(
            ForecastEngine.currentSupply(
                medicationID: medication.id,
                inventoryEvents: [opening, correction],
                doseEvents: [taken]
            ),
            5
        )
    }
}
