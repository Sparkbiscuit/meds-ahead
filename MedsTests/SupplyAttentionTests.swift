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
        refillLeadDays: Int = 7,
        refillsRemaining: Int? = nil,
        refillInProgress: Bool = true,
        daysSinceRefillDate: Int? = nil
    ) -> SupplyAttention {
        SupplyAttention(
            daysRemaining: daysRemaining,
            onHand: onHand,
            refillLeadDays: refillLeadDays,
            refillsRemaining: refillsRemaining,
            refillInProgress: refillInProgress,
            daysSinceRefillDate: daysSinceRefillDate
        )
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
}
