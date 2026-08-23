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

    func testCorrectionCanNeverDisplayNegativeSupply() {
        let medication = Medication(name: "Example")
        let opening = InventoryEvent(medicationID: medication.id, delta: 1, reason: .openingCount)
        let taken = DoseEvent(medicationID: medication.id, doseQuantity: 2, status: .taken)
        XCTAssertEqual(
            ForecastEngine.currentSupply(medicationID: medication.id, inventoryEvents: [opening], doseEvents: [taken]),
            0
        )
    }
}
