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

    /// A count needed carries today as its run-out date. That is where the
    /// forecast's assumptions ran out, not the supply, so the trip cannot be
    /// vouched for either way until someone counts.
    func testACountNeededIsCantSayNotNeedsRefill() throws {
        let returnDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 18)))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 9)))
        let stale = Medication(name: "Furosemide")
        let countNeeded = SupplyForecast(currentSupply: 6, depletionDate: today, daysRemaining: 0, confidence: .estimated, explanation: "",
                                         assumedDoses: 10, needsCount: true)

        let check = TripCheck.make(returnDate: returnDate, forecasts: [(stale, countNeeded)], calendar: calendar)
        XCTAssertEqual(check.uncertain.map(\.displayName), ["Furosemide"])
        XCTAssertTrue(check.needsRefill.isEmpty)
        XCTAssertTrue(check.fine.isEmpty)
    }

    /// A course the supply covers has no run-out date, and neither does one
    /// that is over. Both used to land in "can't say", beside medications
    /// with no forecast at all.
    func testACoveredOrFinishedCourseIsFine() throws {
        let returnDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 18)))
        let day = { (d: Int) in self.calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: 12))! }
        let endsDuringTrip = Medication(name: "Amoxicillin")
        let endsBeforeTrip = Medication(name: "Valacyclovir")
        let finished = Medication(name: "Prednisone")
        let runsShort = Medication(name: "Nitrofurantoin")

        let check = TripCheck.make(returnDate: returnDate, forecasts: [
            (endsDuringTrip, SupplyForecast(currentSupply: 20, depletionDate: nil, daysRemaining: nil, confidence: .high, explanation: "",
                                            courseEndDate: day(25), courseCovered: true, leftoverAtCourseEnd: 2)),
            (endsBeforeTrip, SupplyForecast(currentSupply: 6, depletionDate: nil, daysRemaining: nil, confidence: .estimated, explanation: "",
                                            assumedDoses: 2, courseEndDate: day(16), courseCovered: true, leftoverAtCourseEnd: 0)),
            (finished, SupplyForecast(currentSupply: 0, depletionDate: nil, daysRemaining: nil, confidence: .high, explanation: "",
                                      courseEndDate: day(10), courseFinished: true)),
            (runsShort, SupplyForecast(currentSupply: 4, depletionDate: day(17), daysRemaining: 4, confidence: .high, explanation: "",
                                       courseEndDate: day(19)))
        ], calendar: calendar)

        XCTAssertEqual(check.fine.map(\.displayName), ["Amoxicillin", "Prednisone", "Valacyclovir"])
        XCTAssertTrue(check.uncertain.isEmpty)
        XCTAssertEqual(check.needsRefill.map(\.displayName), ["Nitrofurantoin"], "running out before the course ends still needs a refill")
    }

    /// Straight from the forecast: a count needed on a course is still "can't
    /// say", and a finished one is fine.
    func testCourseForecastsSortAsTheirForecastsSay() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 7)))
        let lastDay = ScheduleEngine.normalizedEndDate(forDay: try XCTUnwrap(calendar.date(byAdding: .day, value: 9, to: start)), calendar: calendar)
        func course(_ name: String, count: Double) -> (Medication, [DoseSchedule], InventoryEvent) {
            let medication = Medication(name: name, createdAt: start)
            let schedule = DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, startDate: start, endDate: lastDay)
            return (medication, [schedule], InventoryEvent(medicationID: medication.id, date: start, delta: count, reason: .openingCount))
        }
        let covered = course("Cefalexin", count: 12)
        let stale = course("Fluconazole", count: 2)
        let now = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: start))
        let later = try XCTUnwrap(calendar.date(byAdding: .day, value: 12, to: start))
        func forecast(_ course: (Medication, [DoseSchedule], InventoryEvent), at moment: Date) -> SupplyForecast {
            ForecastEngine.forecast(medication: course.0, schedules: course.1, inventoryEvents: [course.2], doseEvents: [], now: moment, calendar: calendar)
        }

        let returnDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 14, to: start))
        let during = TripCheck.make(returnDate: returnDate, forecasts: [(covered.0, forecast(covered, at: now)), (stale.0, forecast(stale, at: now))], calendar: calendar)
        XCTAssertEqual(during.fine.map(\.displayName), ["Cefalexin"])
        XCTAssertEqual(during.uncertain.map(\.displayName), ["Fluconazole"])

        let after = TripCheck.make(returnDate: returnDate, forecasts: [(stale.0, forecast(stale, at: later))], calendar: calendar)
        XCTAssertEqual(after.fine.map(\.displayName), ["Fluconazole"], "the course ended before the trip")
    }
}
