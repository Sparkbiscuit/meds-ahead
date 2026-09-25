import XCTest
@testable import Meds

/// One rule for when supply needs someone to act, and for how long a refill in
/// progress may stand in for the warning.
final class SupplyAttentionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func day(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }

    private func attention(
        daysRemaining: Int?,
        onHand: Bool = true,
        needsCount: Bool = false,
        refillLeadDays: Int = 7,
        refillsRemaining: Int? = nil,
        refillInProgress: Bool = true,
        daysSinceRefillDate: Int? = nil
    ) -> SupplyAttention {
        SupplyAttention(
            daysRemaining: daysRemaining,
            onHand: onHand,
            needsCount: needsCount,
            refillLeadDays: refillLeadDays,
            refillsRemaining: refillsRemaining,
            refillInProgress: refillInProgress,
            daysSinceRefillDate: daysSinceRefillDate
        )
    }

    /// The refill's date decides how long it quiets the warning, so marking a
    /// requested refill ready starts from the day it was marked. Opened on the
    /// date stored for the request, the sheet started a pause already over,
    /// and "A refill needs checking" sat beside "Ready for pickup".
    @MainActor
    func testMarkingARequestedRefillReadyStartsFromThatDay() {
        let medication = Medication(name: "Furosemide", refillStatus: .requested, refillStatusDate: day(10))
        let now = day(13)
        XCTAssertEqual(MedicationDetailView.refillStatusInitialDate(for: .ready, medication: medication, now: now), now)
        XCTAssertEqual(MedicationDetailView.refillStatusInitialDate(for: .requested, medication: medication, now: now), day(10),
                       "reopening the same status keeps the date it was given")
        XCTAssertEqual(MedicationDetailView.refillStatusInitialDate(for: .requested, medication: Medication(name: "Furosemide"), now: now), now)

        let fiveDaysLeft = SupplyForecast(currentSupply: 5, depletionDate: day(18), daysRemaining: 5, confidence: .high, explanation: "")
        let readyOn = MedicationDetailView.refillStatusInitialDate(for: .ready, medication: medication, now: now)
        medication.refillStatus = .ready
        medication.refillStatusDate = readyOn
        XCTAssertFalse(SupplyAttention(medication: medication, forecast: fiveDaysLeft, now: now, calendar: calendar).needsAttention)

        medication.refillStatusDate = day(10)
        XCTAssertTrue(SupplyAttention(medication: medication, forecast: fiveDaysLeft, now: now, calendar: calendar).needsAttention,
                      "the request's date, kept, had already ended the pause")
    }

    func testARefillExpectedAheadStillQuietsTheWarning() {
        let expected = attention(daysRemaining: 9, refillLeadDays: 10, daysSinceRefillDate: -3)
        XCTAssertTrue(expected.isLow)
        XCTAssertTrue(expected.refillPauseHolds)
        XCTAssertFalse(expected.needsAttention)

        let yesterday = attention(daysRemaining: 9, refillLeadDays: 10, daysSinceRefillDate: 1)
        XCTAssertFalse(yesterday.needsAttention, "a day late is an ordinary pharmacy")

        let undated = attention(daysRemaining: 9, refillLeadDays: 10, daysSinceRefillDate: nil)
        XCTAssertFalse(undated.needsAttention)
    }

    /// The pause ends at the start of the second day after the refill's date,
    /// the same morning the refill check asks about it.
    func testARefillThatRunsLateStopsQuietingTheWarning() {
        XCTAssertTrue(attention(daysRemaining: 9, refillLeadDays: 10, daysSinceRefillDate: 3).needsAttention)
        XCTAssertTrue(attention(daysRemaining: 9, refillLeadDays: 10, daysSinceRefillDate: 2).needsAttention)
        XCTAssertFalse(attention(daysRemaining: 20, refillLeadDays: 10, daysSinceRefillDate: 3).needsAttention,
                       "late, but nowhere near low: nothing to act on yet")
    }

    func testAFreshRequestCannotQuietTwoDaysLeftOrNothingOnHand() {
        XCTAssertTrue(attention(daysRemaining: 2, daysSinceRefillDate: 0).needsAttention)
        XCTAssertTrue(attention(daysRemaining: 2, daysSinceRefillDate: -5).needsAttention, "however far ahead it is expected")
        XCTAssertTrue(attention(daysRemaining: 0, onHand: false, daysSinceRefillDate: 0).needsAttention)
        XCTAssertTrue(attention(daysRemaining: nil, onHand: false, daysSinceRefillDate: nil).needsAttention)
        XCTAssertFalse(attention(daysRemaining: 3, daysSinceRefillDate: 0).needsAttention)
    }

    /// Told the refill comes only after the supply runs out, the app used to say
    /// it was on its way and hold back every warning until two days were left.
    func testARefillDueOnlyAfterTheSupplyRunsOutIsAGap() {
        let afterRunOut = attention(daysRemaining: 6, daysSinceRefillDate: -16)
        XCTAssertFalse(afterRunOut.refillPauseHolds)
        XCTAssertTrue(afterRunOut.needsAttention)
        XCTAssertTrue(attention(daysRemaining: 6, daysSinceRefillDate: -6).needsAttention, "due the day it runs out")
        XCTAssertFalse(attention(daysRemaining: 6, daysSinceRefillDate: -5).needsAttention, "due the day before: in time")
        XCTAssertFalse(attention(daysRemaining: 20, daysSinceRefillDate: -25).needsAttention, "due after it runs out, but nowhere near low: nothing to act on yet")
    }

    func testTheCheckComesOnTheMorningThePauseEnds() throws {
        let late = try XCTUnwrap(SupplyAttention.refillCheckMoment(refillStatusDate: day(10), depletionDate: day(30, hour: 8), calendar: calendar))
        XCTAssertEqual(late, day(12, hour: 9))
        let lateAttention = attention(daysRemaining: 18, refillLeadDays: 30, daysSinceRefillDate: SupplyAttention.days(from: day(10), to: late, calendar: calendar))
        XCTAssertFalse(lateAttention.refillPauseHolds)
        XCTAssertTrue(attention(daysRemaining: 19, refillLeadDays: 30, daysSinceRefillDate: 1).refillPauseHolds, "the day before, it still held")

        let short = try XCTUnwrap(SupplyAttention.refillCheckMoment(refillStatusDate: day(25), depletionDate: day(20, hour: 8), calendar: calendar))
        XCTAssertEqual(short, day(18, hour: 9))
        XCTAssertEqual(SupplyAttention.refillCheckMoment(refillStatusDate: nil, depletionDate: day(20, hour: 8), calendar: calendar), day(18, hour: 9))
        XCTAssertNil(SupplyAttention.refillCheckMoment(refillStatusDate: nil, depletionDate: nil, calendar: calendar))
    }

    /// No refills left, a seven-day lead, nine days of supply: the prescriber's
    /// ten days apply on Supply, in the widget and in the planner alike. They
    /// used to disagree, and only the alert knew.
    @MainActor
    func testNoRefillsLeftUsesThePrescriberLeadEverywhere() throws {
        let now = day(1)
        let medication = Medication(name: "Dimethyl fumarate", form: .capsule, refillsRemaining: 0, refillLeadDays: 7)
        let schedules = [DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, doseQuantity: 1, startDate: day(1, hour: 0))]
        let inventory = [InventoryEvent(medicationID: medication.id, delta: 9, reason: .openingCount)]
        let forecast = ForecastEngine.forecast(medication: medication, schedules: schedules, inventoryEvents: inventory, doseEvents: [], now: now, calendar: calendar)
        XCTAssertEqual(forecast.daysRemaining, 9)

        let supply = SupplyAttention(medication: medication, forecast: forecast, now: now, calendar: calendar)
        XCTAssertEqual(supply.leadDays, SupplyAttention.prescriberLeadDays)
        XCTAssertTrue(supply.needsAttention)

        let widget = try XCTUnwrap(RunsOutSnapshot.make(medications: [medication], schedules: schedules, inventoryEvents: inventory, doseEvents: [], now: now, calendar: calendar).soonest)
        XCTAssertTrue(widget.needsAttention)
        XCTAssertEqual(widget.tone, .attention)

        let plan = NotificationPlanBuilder.make(medication: medication, schedules: schedules, inventoryEvents: inventory, doseEvents: [], now: now, calendar: calendar)
        let outcome = NotificationPlanner.plan(for: [plan], now: now, calendar: calendar)
        XCTAssertTrue(outcome.notifications.filter { $0.kind == .refill }.isEmpty, "the ten-day moment has passed")
        XCTAssertTrue(outcome.retainedPrefixes.contains("meds.\(medication.id.uuidString).refill."), "and the alert it gave is still true")
    }

    /// The detail screen and the editor used to show the chosen seven days
    /// while the warning came on the tenth, which read as the app misbehaving.
    func testTheLeadTimeSaysWhenNoRefillsLengthenIt() {
        XCTAssertEqual(SupplyAttention.leadTimeText(refillLeadDays: 7, refillsRemaining: 0), "10 days before, because no refills are left")
        XCTAssertEqual(SupplyAttention.lengthenedLeadNote(refillLeadDays: 7, refillsRemaining: 0),
                       "No refills are left, so the warning comes 10 days before, to allow time for a new prescription.")

        for (lead, refills) in [(7, 2), (7, nil), (14, 0), (10, 0)] as [(Int, Int?)] {
            XCTAssertEqual(SupplyAttention.leadTimeText(refillLeadDays: lead, refillsRemaining: refills), "\(lead) days before")
            XCTAssertNil(SupplyAttention.lengthenedLeadNote(refillLeadDays: lead, refillsRemaining: refills), "the chosen lead is the one used")
        }
        XCTAssertEqual(SupplyAttention.leadTimeText(refillLeadDays: 1, refillsRemaining: 1), "1 day before")
    }

    func testARequestedRefillPastItsDateSaysSo() {
        let medication = Medication(name: "Furosemide", refillStatus: .requested, refillStatusDate: day(20))
        XCTAssertEqual(RefillStatusText.line(for: medication, now: day(23), calendar: calendar), "Refill requested · was expected Aug 20")
        XCTAssertEqual(RefillStatusText.line(for: medication, now: day(20, hour: 18), calendar: calendar), "Refill requested · expected today")
        XCTAssertEqual(RefillStatusText.line(for: medication, now: day(19), calendar: calendar), "Refill requested · expected tomorrow")
    }

    func testTheWarningLineComesFirstAndSaysOutWhenNothingIsLeft() {
        let out = SupplyForecast(currentSupply: 0, depletionDate: day(1), daysRemaining: 0, confidence: .high, explanation: "No confirmed supply remains.")
        XCTAssertEqual(SupplyAttention.line(for: out), "No confirmed supply remains")
        let low = SupplyForecast(currentSupply: 4, depletionDate: day(5), daysRemaining: 4, confidence: .high, explanation: "")
        XCTAssertTrue(SupplyAttention.line(for: low).hasPrefix("Act soon · around "))
    }

    // MARK: - Count needed

    /// Twice daily from the 1st, six on the opening count, nothing logged: by
    /// the 6th the ten doses the forecast must assume use up the ledger.
    @MainActor
    private func staleCount(refillStatus: RefillStatus = .none, refillStatusDate: Date? = nil) -> (Medication, SupplyForecast) {
        let medication = Medication(name: "Furosemide", createdAt: day(1, hour: 7), refillStatus: refillStatus, refillStatusDate: refillStatusDate)
        let schedules = [8, 20].map { DoseSchedule(medicationID: medication.id, minutesAfterMidnight: $0 * 60, doseQuantity: 1, startDate: day(1, hour: 7)) }
        let inventory = [InventoryEvent(medicationID: medication.id, date: day(1, hour: 7), delta: 6, reason: .openingCount)]
        return (medication, ForecastEngine.forecast(medication: medication, schedules: schedules, inventoryEvents: inventory, doseEvents: [], now: day(6, hour: 7), calendar: calendar))
    }

    /// The assumed doses used up the ledger, so what is left is unknown. That
    /// needs someone to count, whatever refill is on its way, and it is said
    /// as a count, never as "Act soon · around today".
    @MainActor
    func testACountNeededNeedsAttentionAndSaysSo() throws {
        let (medication, forecast) = staleCount(refillStatus: .requested, refillStatusDate: day(8))
        XCTAssertTrue(forecast.needsCount)

        let supply = SupplyAttention(medication: medication, forecast: forecast, now: day(6, hour: 7), calendar: calendar)
        XCTAssertTrue(supply.needsCount)
        XCTAssertTrue(supply.isLow)
        XCTAssertFalse(supply.refillPauseHolds, "a refill cannot stand in for a count nobody made")
        XCTAssertTrue(supply.needsAttention)

        XCTAssertEqual(SupplyAttention.line(for: forecast), "Count needed")
        XCTAssertEqual(SupplyAttention.countNeededReason(for: forecast), "10 doses since the last count weren't logged")
        XCTAssertEqual(SupplyAttention.quantityWords(for: forecast), "on record")

        // Plain values say the same, even with a long runway to go on.
        XCTAssertTrue(attention(daysRemaining: 30, needsCount: true, refillInProgress: true, daysSinceRefillDate: -1).needsAttention)
        XCTAssertFalse(attention(daysRemaining: 30, needsCount: true, refillInProgress: true, daysSinceRefillDate: -1).refillPauseHolds)
    }

    func testTheCountNeededReasonNamesTheEventItCountsFrom() {
        let fromRefill = SupplyForecast(currentSupply: 1, depletionDate: day(6), daysRemaining: 0, confidence: .estimated, explanation: "",
                                        assumedDoses: 1, needsCount: true, assumedSinceRefill: true)
        XCTAssertEqual(SupplyAttention.countNeededReason(for: fromRefill), "1 dose since the last refill wasn't logged")

        let low = SupplyForecast(currentSupply: 4, depletionDate: day(5), daysRemaining: 4, confidence: .estimated, explanation: "", assumedDoses: 3)
        XCTAssertNil(SupplyAttention.countNeededReason(for: low), "an estimate with supply to spare needs no count")
        XCTAssertTrue(SupplyAttention.line(for: low).hasPrefix("Act soon · around "))
    }

    /// Doses assumed short of a count needed still make the ledger's number
    /// only what was recorded: the run-out date beside it has already taken
    /// them out, so "on hand" and the date could not both be true.
    func testAnyAssumedDoseMakesTheLedgerOnlyWhatWasRecorded() {
        let assuming = SupplyForecast(currentSupply: 4, depletionDate: day(5), daysRemaining: 4, confidence: .estimated, explanation: "", assumedDoses: 3)
        XCTAssertEqual(SupplyAttention.quantityWords(for: assuming), "on record")
        XCTAssertEqual(SupplyAttention.assumedDosesReason(for: assuming), "3 doses since the last count weren't logged")
        XCTAssertNil(SupplyAttention.countNeededReason(for: assuming))

        let one = SupplyForecast(currentSupply: 4, depletionDate: day(5), daysRemaining: 4, confidence: .estimated, explanation: "",
                                 assumedDoses: 1, assumedSinceRefill: true)
        XCTAssertEqual(SupplyAttention.assumedDosesReason(for: one), "1 dose since the last refill wasn't logged")

        let logged = SupplyForecast(currentSupply: 4, depletionDate: day(5), daysRemaining: 4, confidence: .high, explanation: "")
        XCTAssertEqual(SupplyAttention.quantityWords(for: logged), "on hand")
        XCTAssertNil(SupplyAttention.assumedDosesReason(for: logged))
    }
}
