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
