import SwiftUI
import XCTest
@testable import Meds

/// A forecast whose assumed doses used up the ledger comes with zero days and
/// today's date. The screens that read a forecast must ask for a count there,
/// never say the supply is gone or give a date.
final class CountNeededDisplayTests: XCTestCase {
    private let countNeeded = SupplyForecast(currentSupply: 6, depletionDate: .now, daysRemaining: 0, confidence: .estimated,
                                             explanation: "", assumedDoses: 10, needsCount: true)
    private let empty = SupplyForecast(currentSupply: 0, depletionDate: .now, daysRemaining: 0, confidence: .high,
                                       explanation: "No confirmed supply remains.")

    func testTheGaugeAsksRatherThanReadingEmpty() {
        let gauge = SupplyGauge(daysRemaining: 0, leadDays: 7, needsCount: true)
        XCTAssertNil(gauge.shownDays)
        XCTAssertEqual(gauge.color, .orange, "the attention colour, not the red of an empty supply")
        XCTAssertEqual(gauge.accessibilityText, "Count needed")

        let out = SupplyGauge(daysRemaining: 0, leadDays: 7)
        XCTAssertEqual(out.shownDays, 0)
        XCTAssertEqual(out.color, .red)
        XCTAssertEqual(out.accessibilityText, "0 days of supply remaining")
    }

    func testTheDetailScreenTitleSaysACountIsNeeded() {
        XCTAssertEqual(MedicationDetailView.forecastTitle(for: countNeeded), "Count needed")
        XCTAssertEqual(MedicationDetailView.forecastTitle(for: empty), "Out of supply")
        let steady = SupplyForecast(currentSupply: 20, depletionDate: .now, daysRemaining: 9, confidence: .high, explanation: "")
        XCTAssertEqual(MedicationDetailView.forecastTitle(for: steady), "About 9 days left")
    }

    /// Today's refill card heads itself with the reason: a refill on time
    /// beside a count nobody has made is not "A refill needs checking".
    func testTheRefillCardSaysWhetherACountOrARefillNeedsSomeone() {
        XCTAssertEqual(TodayView.refillAttentionTitle(refillsToCheck: 0, countsNeeded: 1), "A count is needed")
        XCTAssertEqual(TodayView.refillAttentionTitle(refillsToCheck: 0, countsNeeded: 2), "2 counts are needed")
        XCTAssertEqual(TodayView.refillAttentionTitle(refillsToCheck: 1, countsNeeded: 0), "A refill needs checking")
        XCTAssertEqual(TodayView.refillAttentionTitle(refillsToCheck: 3, countsNeeded: 0), "3 refills need checking")
        XCTAssertEqual(TodayView.refillAttentionTitle(refillsToCheck: 1, countsNeeded: 1), "A refill needs checking and a count is needed")
        XCTAssertEqual(TodayView.refillAttentionTitle(refillsToCheck: 2, countsNeeded: 1), "2 refills need checking and a count is needed")
    }

    /// Trip Check marked a count needed with a grey question mark, the look of
    /// "no forecast yet", while every other screen marks it for attention.
    func testTripCheckMarksACountNeededForAttention() {
        let mark = TripCheck.uncertainMark(for: countNeeded)
        XCTAssertEqual(mark.symbol, "exclamationmark.circle.fill")
        XCTAssertEqual(mark.tint, .orange)

        let noForecast = SupplyForecast(currentSupply: 20, depletionDate: nil, daysRemaining: nil, confidence: .unknown, explanation: "")
        XCTAssertEqual(TripCheck.uncertainMark(for: noForecast).symbol, "questionmark.circle")
        XCTAssertEqual(TripCheck.uncertainMark(for: noForecast).tint, .secondary)
    }

    /// Prefilled with the ledger's number, one tap on Save Count confirmed a
    /// count nobody made and cleared the doses the forecast had assumed.
    func testCorrectCountOpensEmptyWhileACountIsNeeded() {
        XCTAssertNil(SupplyChangeQuantity.countPrefill(for: countNeeded))
        XCTAssertNil(SupplyChangeQuantity.value(from: "", prefilled: nil, requiresMoreThanZero: false), "an empty field cannot be saved")
        XCTAssertEqual(SupplyChangeQuantity.value(from: "6", prefilled: nil, requiresMoreThanZero: false, locale: Locale(identifier: "en_US")), 6,
                       "the same number, typed after counting, is a count")

        XCTAssertEqual(SupplyChangeQuantity.countPrefill(for: empty), 0)
        let steady = SupplyForecast(currentSupply: 27.125, depletionDate: nil, daysRemaining: nil, confidence: .unknown, explanation: "")
        XCTAssertEqual(SupplyChangeQuantity.countPrefill(for: steady), 27.125)
    }

    /// Doses assumed short of using up the ledger are the same hazard: the
    /// ledger's number prefilled, one tap confirmed it, and the doses the
    /// forecast was charging vanished with the warning they had raised.
    func testCorrectCountOpensEmptyWhileAnyDoseIsAssumed() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func september(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
        }
        let medication = Medication(name: "Furosemide", createdAt: september(1, 7))
        let schedule = DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, doseQuantity: 1, startDate: september(1, 7))
        let opening = InventoryEvent(medicationID: medication.id, date: september(1, 7), delta: 30, reason: .openingCount)
        let stale = ForecastEngine.forecast(medication: medication, schedules: [schedule], inventoryEvents: [opening], doseEvents: [],
                                            now: september(26, 7), calendar: calendar)
        XCTAssertEqual(stale.assumedDoses, 25)
        XCTAssertFalse(stale.needsCount, "5 are still assumed on hand")
        XCTAssertEqual(stale.daysRemaining, 4)

        XCTAssertNil(SupplyChangeQuantity.countPrefill(for: stale), "the ledger's 30 is not a count")
        XCTAssertNil(SupplyChangeQuantity.value(from: "", prefilled: SupplyChangeQuantity.countPrefill(for: stale), requiresMoreThanZero: false),
                     "Save Count stays disabled until a number is typed")

        let counted = SupplyForecast(currentSupply: 30, depletionDate: nil, daysRemaining: nil, confidence: .high, explanation: "", assumedDoses: 0)
        XCTAssertEqual(SupplyChangeQuantity.countPrefill(for: counted), 30, "with every dose logged, the ledger is what is on hand")
    }
}
