import CoreGraphics
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

    /// Doses nobody logged used up the count on record, so the forecast's
    /// run-out date is today. Printed, it would tell the pharmacy counter the
    /// supply is gone; the sheet says a count is needed instead.
    func testACountNeededPrintsNoRunOutDate() throws {
        var utc = calendar
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let counted = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 7)))
        let now = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 7)))
        let medication = Medication(name: "Furosemide", createdAt: counted)
        let schedules = [8, 20].map { DoseSchedule(medicationID: medication.id, minutesAfterMidnight: $0 * 60, doseQuantity: 1, startDate: counted) }
        let opening = InventoryEvent(medicationID: medication.id, date: counted, delta: 6, reason: .openingCount)

        let entry = try XCTUnwrap(MedicationListDocument.entries(
            medications: [medication],
            schedules: schedules,
            inventoryEvents: [opening],
            doseEvents: [],
            now: now,
            calendar: utc
        ).first)

        XCTAssertEqual(entry.supplyLine, "6 tablets on record · count needed: 10 doses since the last count weren't logged")
        XCTAssertFalse(entry.supplyLine.contains("runs out"))
    }

    /// A pharmacy can act on an NDC and a clinic on an RxNorm code; a pharmacy's
    /// own barcode payload means nothing to anyone else and stays off the sheet.
    func testExactProductCodesPrintAndBarcodePayloadsDoNot() {
        let exact = Medication(name: "Tacrolimus", productIdentifier: "00469-0617-73", productIdentifierType: "NDC")
        let coded = Medication(name: "Sertraline", productIdentifier: "312938", productIdentifierType: "RxNorm")
        let scanned = Medication(name: "Melatonin", productIdentifier: "323615013", productIdentifierType: "Code 128")

        let entries = MedicationListDocument.entries(
            medications: [exact, coded, scanned],
            schedules: [],
            inventoryEvents: [],
            doseEvents: [],
            calendar: calendar
        )

        XCTAssertTrue(entries[2].detailLine.contains("NDC 00469-0617-73"), entries[2].detailLine)
        XCTAssertTrue(entries[1].detailLine.contains("RxNorm 312938"), entries[1].detailLine)
        XCTAssertFalse(entries[0].detailLine.contains("323615013"), entries[0].detailLine)
    }

    /// A household with two people on the list reads it by person; a
    /// medication nobody is named for sorts last. And a clinician reads what was
    /// actually logged.
    func testEntriesGroupByPersonAndSayWhatWasLogged() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 12)))
        let tacrolimus = Medication(name: "Tacrolimus", createdAt: now.addingTimeInterval(-40 * 86_400), personName: "Ellis")
        let aspirin = Medication(name: "Aspirin", createdAt: now.addingTimeInterval(-2 * 86_400), personName: "Mom")
        let melatonin = Medication(name: "Melatonin", createdAt: now.addingTimeInterval(-40 * 86_400))
        let doses = [
            DoseEvent(medicationID: tacrolimus.id, recordedAt: now.addingTimeInterval(-86_400), doseQuantity: 1, status: .taken),
            DoseEvent(medicationID: tacrolimus.id, recordedAt: now.addingTimeInterval(-2 * 86_400), doseQuantity: 1, status: .skipped),
            DoseEvent(medicationID: tacrolimus.id, recordedAt: now.addingTimeInterval(-40 * 86_400), doseQuantity: 1, status: .taken),
            DoseEvent(medicationID: aspirin.id, recordedAt: now.addingTimeInterval(-3_600), doseQuantity: 1, status: .taken)
        ]

        let entries = MedicationListDocument.entries(
            medications: [melatonin, aspirin, tacrolimus],
            schedules: [],
            inventoryEvents: [],
            doseEvents: doses,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(entries.map(\.title), ["Tacrolimus", "Aspirin", "Melatonin"])
        XCTAssertEqual(entries.map(\.personName), ["Ellis", "Mom", ""])
        XCTAssertEqual(entries[0].adherenceLine, "1 dose logged in the last 30 days, 1 skipped")
        XCTAssertTrue(entries[1].adherenceLine.hasPrefix("1 dose logged in the last 30 days (added "), entries[1].adherenceLine)
        XCTAssertEqual(entries[2].adherenceLine, "No doses logged in the last 30 days")
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

    /// The household this was built for has more than a dozen medications. Rendered
    /// as one page sized to its content that was a sheet some three feet tall, which
    /// prints to nothing legible.
    @MainActor
    func testALongListPaginatesOntoLetterPages() throws {
        let entries = (0..<16).map { index in
            MedicationListEntry(
                id: UUID(),
                title: "Medication \(index)",
                subtitle: "10 mg · Tablet",
                directions: "Take 1 tablet by mouth twice daily with food",
                scheduleLines: ["8:00 AM — 1 tablet · Every day", "9:00 PM — 1 tablet · Every day"],
                supplyLine: "30 tablets on hand · runs out around Sep 20, 2026",
                detailLine: "2 refills remaining"
            )
        }
        let url = try XCTUnwrap(MedicationListPDFRenderer.render(entries: entries))
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))

        XCTAssertGreaterThan(document.numberOfPages, 1)
        for index in 1...document.numberOfPages {
            let page = try XCTUnwrap(document.page(at: index))
            let box = page.getBoxRect(.mediaBox)
            XCTAssertEqual(box.width, 612, accuracy: 1)
            XCTAssertEqual(box.height, 792, accuracy: 1, "every page is US Letter, not one endless strip")
        }
    }

    @MainActor
    func testShortListStillFitsOnOnePage() throws {
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
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(document.numberOfPages, 1)
    }

    @MainActor
    func testEmptyListRendersNothingToShare() {
        XCTAssertNil(MedicationListPDFRenderer.render(entries: []))
    }

    func testEntrySubtitleIncludesBrandWithoutNickname() throws {
        let medication = Medication(
            name: "Sertraline",
            brandName: "Zoloft",
            strength: "50 mg",
            form: .tablet
        )
        let entries = MedicationListDocument.entries(
            medications: [medication],
            schedules: [],
            inventoryEvents: [],
            doseEvents: [],
            calendar: calendar
        )

        XCTAssertEqual(try XCTUnwrap(entries.first).subtitle, "Brand: Zoloft · 50 mg · Tablet")
    }

    func testEntrySubtitleOrdersNameBrandStrengthAndFormForNicknamedMedication() throws {
        let medication = Medication(
            name: "Sertraline",
            nickname: "Morning pill",
            brandName: "Zoloft",
            strength: "50 mg",
            form: .tablet
        )
        let entries = MedicationListDocument.entries(
            medications: [medication],
            schedules: [],
            inventoryEvents: [],
            doseEvents: [],
            calendar: calendar
        )

        XCTAssertEqual(try XCTUnwrap(entries.first).subtitle, "Sertraline · Brand: Zoloft · 50 mg · Tablet")
    }
}
