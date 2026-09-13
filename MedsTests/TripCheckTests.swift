import XCTest
@testable import Meds

/// Pure forecast arithmetic: which medications run out before a trip is over.
final class TripCheckTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func forecast(depletion: Date?, days: Int?) -> SupplyForecast {
        SupplyForecast(currentSupply: 10, depletionDate: depletion, daysRemaining: days, confidence: depletion == nil ? .unknown : .high, explanation: "")
    }

    func testMedicationsSortIntoNeedsRefillUncertainAndFine() throws {
        let returnDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 18)))
        let day = { (d: Int) in self.calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: 8))! }
        let early = Medication(name: "Zolpidem")
        let sameDay = Medication(name: "Aspirin")
        let later = Medication(name: "Melatonin")
        let unknown = Medication(name: "Lotion")
        let archived = Medication(name: "Old", isArchived: true)

        let check = TripCheck.make(returnDate: returnDate, forecasts: [
            (later, forecast(depletion: day(25), days: 13)),
            (unknown, forecast(depletion: nil, days: nil)),
            (early, forecast(depletion: day(18), days: 6)),
            (sameDay, forecast(depletion: day(20), days: 8)),
            (archived, forecast(depletion: day(15), days: 3))
        ], calendar: calendar)

        XCTAssertEqual(check.needsRefill.map(\.displayName), ["Zolpidem", "Aspirin"], "soonest first; running out on the return day counts")
        XCTAssertEqual(check.uncertain.map(\.displayName), ["Lotion"])
        XCTAssertEqual(check.fine.map(\.displayName), ["Melatonin"])
    }
}
