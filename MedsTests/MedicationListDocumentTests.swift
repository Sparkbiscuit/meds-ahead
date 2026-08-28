import XCTest
@testable import Meds

final class MedicationListDocumentTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 1
        return calendar
    }

    func testEntryCarriesScheduleSupplyAndPrescriptionDetail() throws {
        let medication = Medication(
            name: "Tacrolimus",
            strength: "1 mg",
            form: .capsule,
            directions: "Take 1 capsule by mouth twice daily",
            refillsRemaining: 2
        )
        let schedule = DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, doseQuantity: 1)
        let opening = InventoryEvent(medicationID: medication.id, delta: 30, reason: .openingCount)

        let entries = MedicationListDocument.entries(
            medications: [medication],
            schedules: [schedule],
            inventoryEvents: [opening],
            doseEvents: [],
            calendar: calendar
        )
        let entry = try XCTUnwrap(entries.first)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.title, "Tacrolimus")
        XCTAssertTrue(entry.subtitle.contains("1 mg"))
        XCTAssertTrue(entry.subtitle.contains("Capsule"))
        XCTAssertEqual(entry.directions, "Take 1 capsule by mouth twice daily")
        XCTAssertEqual(entry.scheduleLines.count, 1)
        XCTAssertTrue(try XCTUnwrap(entry.scheduleLines.first).contains("1 capsule"))
        XCTAssertTrue(try XCTUnwrap(entry.scheduleLines.first).contains("Every day"))
        XCTAssertTrue(entry.supplyLine.contains("30 capsules on hand"))
        XCTAssertTrue(entry.supplyLine.contains("runs out around"))
        XCTAssertTrue(entry.detailLine.contains("2 refills remaining"))
    }

    func testArchivedMedicationsAreExcludedAndEntriesSortByDisplayName() {
        let zebra = Medication(name: "Zolpidem")
        let apple = Medication(name: "Amlodipine", nickname: "Blood pressure")
        let hidden = Medication(name: "Old med", isArchived: true)

        let entries = MedicationListDocument.entries(
            medications: [zebra, apple, hidden],
            schedules: [],
            inventoryEvents: [],
            doseEvents: [],
            calendar: calendar
        )

        XCTAssertEqual(entries.map(\.title), ["Blood pressure", "Zolpidem"])
        XCTAssertTrue(entries[0].subtitle.contains("Amlodipine"), "the real name must appear beside a nickname")
    }

    func testAsNeededMedicationSaysSoInsteadOfListingTimes() throws {
        let medication = Medication(name: "Melatonin", isAsNeeded: true)
        let entries = MedicationListDocument.entries(
            medications: [medication],
            schedules: [],
            inventoryEvents: [],
            doseEvents: [],
            calendar: calendar
        )
        XCTAssertEqual(try XCTUnwrap(entries.first).scheduleLines, ["Taken as needed"])
    }

    func testWeekdaySummaryReadsNaturally() {
        XCTAssertEqual(MedicationListDocument.weekdaySummary(mask: 0b1111111, calendar: calendar), "Every day")
        XCTAssertEqual(
            MedicationListDocument.weekdaySummary(mask: (1 << 1) | (1 << 3) | (1 << 5), calendar: calendar),
            "Mon, Wed, Fri"
        )

        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        XCTAssertEqual(
            MedicationListDocument.weekdaySummary(mask: (1 << 0) | (1 << 6), calendar: mondayFirst),
            "Sat, Sun",
            "a Monday-first week lists Saturday before Sunday"
        )
    }

    @MainActor
    func testRenderedPDFIsARealDocument() throws {
        let entry = MedicationListEntry(
            id: UUID(),
            title: "Tacrolimus",
            subtitle: "1 mg · Capsule",
            directions: "Take 1 capsule by mouth twice daily",
            scheduleLines: ["8:00 AM — 1 capsule · Every day"],
            supplyLine: "30 capsules on hand",
            detailLine: "2 refills remaining"
        )
        let url = try XCTUnwrap(MedicationListPDFRenderer.render(entries: [entry]))
        let data = try Data(contentsOf: url)
        XCTAssertTrue(data.starts(with: Array("%PDF".utf8)))
        XCTAssertGreaterThan(data.count, 1000)
    }

    @MainActor
    func testEmptyListRendersNothingToShare() {
        XCTAssertNil(MedicationListPDFRenderer.render(entries: []))
    }
}
