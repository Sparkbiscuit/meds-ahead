import SwiftData
import XCTest
@testable import Meds

/// A bottle added to a medication already tracked is one refill on its ledger:
/// the count rises, the refill in progress is done, and the label's refills,
/// expiry and Rx number are taken only when asked.
final class AddBottleRecordTests: XCTestCase {
    private let british = Locale(identifier: "en_GB")
    private var container: ModelContainer?

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Medication.self, DoseSchedule.self, DoseEvent.self, InventoryEvent.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        self.container = container
        return container.mainContext
    }

    @MainActor
    private func trackedFurosemide(in context: ModelContext) throws -> Medication {
        let medication = Medication(
            name: "Furosemide",
            strength: "20 mg",
            refillsRemaining: 2,
            expirationDate: Date(timeIntervalSince1970: 1_800_000_000),
            rxNumber: "RX-1",
            refillStatus: .requested,
            refillStatusDate: Date(timeIntervalSince1970: 1_790_000_000)
        )
        context.insert(medication)
        context.insert(InventoryEvent(medicationID: medication.id, delta: 28, reason: .openingCount))
        try context.save()
        return medication
    }

    @MainActor
    func testTheBottleIsARefillOnTheTrackedMedication() throws {
        let context = try makeContext()
        let medication = try trackedFurosemide(in: context)

        let event = AddBottleRecord.record(quantity: 30, note: "Second bottle", labelUpdates: nil, to: medication, in: context)
        try context.save()

        XCTAssertEqual(event.medicationID, medication.id)
        XCTAssertEqual(event.reason, .refill)
        XCTAssertEqual(event.delta, 30)
        XCTAssertEqual(event.note, "Second bottle")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Medication>()), 1, "no second medication")
        let ledger = try context.fetch(FetchDescriptor<InventoryEvent>())
        let forecast = ForecastEngine.forecast(medication: medication, schedules: [], inventoryEvents: ledger, doseEvents: [])
        XCTAssertEqual(forecast.currentSupply, 58)

        XCTAssertEqual(medication.refillStatus, .none, "the medication is in hand")
        XCTAssertNil(medication.refillStatusDate)
        XCTAssertEqual(medication.refillsRemaining, 2, "refills left changes only when the label says")
        XCTAssertEqual(medication.expirationDate, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(medication.rxNumber, "RX-1")
    }

    @MainActor
    func testTheLabelsValuesAreTakenWhenAsked() throws {
        let context = try makeContext()
        let medication = try trackedFurosemide(in: context)
        let expiry = Date(timeIntervalSince1970: 1_780_000_000)
        let updates = AddBottleRecord.LabelUpdates(refillsRemaining: 0, expirationDate: expiry, rxNumber: "RX-2")
        XCTAssertEqual(updates.changes(to: medication), updates, "an earlier expiry and fewer refills are all taken")
        XCTAssertEqual(updates.kept(by: medication, locale: british), [])

        AddBottleRecord.record(quantity: 60, note: "", labelUpdates: updates, to: medication, in: context)
        try context.save()

        XCTAssertEqual(medication.refillsRemaining, 0)
        XCTAssertEqual(medication.expirationDate, expiry)
        XCTAssertEqual(medication.rxNumber, "RX-2")
    }

    /// The pills already counted may be from the earlier bottle, and a label
    /// from an earlier fill shows refills since used. Either value would move
    /// a reminder later, so the medication keeps its own, and the sheet says so.
    @MainActor
    func testALaterExpiryAndMoreRefillsAreNotTaken() throws {
        let context = try makeContext()
        let medication = try trackedFurosemide(in: context)
        let onFile = try XCTUnwrap(medication.expirationDate)
        let later = Date(timeIntervalSince1970: 1_830_000_000)
        let updates = AddBottleRecord.LabelUpdates(refillsRemaining: 5, expirationDate: later, rxNumber: "RX-1")
        XCTAssertTrue(updates.changes(to: medication).isEmpty, "nothing here would change the record, the Rx number included")
        XCTAssertEqual(updates.kept(by: medication, locale: british, calendar: Calendar(identifier: .gregorian)), [
            "Refills left stay at 2, fewer than this label's 5",
            "Expiry stays \(onFile.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(british))), earlier than this label's"
        ])

        AddBottleRecord.record(quantity: 60, note: "", labelUpdates: updates, to: medication, in: context)
        try context.save()

        XCTAssertEqual(medication.refillsRemaining, 2)
        XCTAssertEqual(medication.expirationDate, onFile)
        XCTAssertEqual(medication.rxNumber, "RX-1")

        // Nothing on file yet: the label's values are all there is.
        let blank = Medication(name: "Furosemide", strength: "20 mg")
        XCTAssertEqual(updates.changes(to: blank), updates)
        XCTAssertEqual(updates.kept(by: blank, locale: british), [])
    }

    /// The toggle offers only what the label read, at the values the review
    /// screen shows now: a digit corrected there is the digit written.
    func testTheUpdatesOfferedAreWhatTheLabelReadAsReviewed() throws {
        var scanned = MedicationDraft(name: "Furosemide", strength: "20 mg", refillsRemaining: 3, source: .scanned)
        scanned.rxNumber = "RX-8"
        let updates = try XCTUnwrap(AddBottleRecord.LabelUpdates.reviewed(draft: scanned, refillsText: " 2 ", expirationDate: .now, rxNumber: "RX-9"))
        XCTAssertEqual(updates.refillsRemaining, 2)
        XCTAssertNil(updates.expirationDate, "the label printed no expiry")
        XCTAssertEqual(updates.rxNumber, "RX-9")
        XCTAssertEqual(updates.toggleTitle(locale: british), "Also update refills left and Rx number from this label")
        XCTAssertEqual(updates.lines(locale: british), ["2 refills left", "Rx RX-9"])

        let manual = MedicationDraft(name: "Furosemide", strength: "20 mg", refillsRemaining: 3)
        XCTAssertNil(AddBottleRecord.LabelUpdates.reviewed(draft: manual, refillsText: "3", expirationDate: nil, rxNumber: ""),
                     "a manual entry has no label to update from")

        let nothingRead = MedicationDraft(name: "Furosemide", source: .scanned)
        XCTAssertNil(AddBottleRecord.LabelUpdates.reviewed(draft: nothingRead, refillsText: "4", expirationDate: .now, rxNumber: "RX-1"))

        let everything = AddBottleRecord.LabelUpdates(refillsRemaining: 1, expirationDate: .now, rxNumber: "7")
        XCTAssertEqual(everything.toggleTitle(locale: british), "Also update refills left, expiry and Rx number from this label")
        XCTAssertEqual(AddBottleRecord.LabelUpdates(refillsRemaining: 0).lines(locale: british), ["No refills left"])
        XCTAssertEqual(AddBottleRecord.LabelUpdates(refillsRemaining: 1).lines(locale: british), ["1 refill left"])
    }
}
