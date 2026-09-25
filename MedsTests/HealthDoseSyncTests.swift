import SwiftData
import XCTest
@testable import Meds

/// The pass that inserts and deletes supply-changing doses, run against an
/// in-memory store with Health's answers handed in as plain values. What the
/// reconciler decides is covered in `HealthDoseReconcilerTests`; this is what
/// the sync does with those decisions, and what it refuses to do.
@available(iOS 26.0, *)
@MainActor
final class HealthDoseSyncTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { date(12, 22) }

    private struct QueryFailed: Error {}

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let medication: Medication
    }

    private func makeFixture(createdAt: Date, code: String = "312938") throws -> Fixture {
        let schema = Schema([Medication.self, DoseSchedule.self, DoseEvent.self, InventoryEvent.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let medication = Medication(name: "Sertraline", createdAt: createdAt, rxNormCode: code)
        context.insert(medication)
        try context.save()
        return Fixture(container: container, context: context, medication: medication)
    }

    private func entry(_ id: String, code: String = "312938", archived: Bool = false) -> HealthSharedMedication {
        HealthSharedMedication(id: id, rxNormCodes: [code], isArchived: archived)
    }

    private func record(_ date: Date, id: UUID = UUID()) -> HealthDoseRecord {
        HealthDoseRecord(sampleID: id, date: date, scheduledDate: nil, quantity: 1, status: .taken)
    }

    private func source(
        shared: [HealthSharedMedication],
        records: @escaping @Sendable (String) async throws -> [HealthDoseRecord]
    ) -> HealthDoseSync.Source {
        HealthDoseSync.Source(
            isAvailable: { true },
            sharedMedications: { shared },
            doseRecords: { id, _, _ in try await records(id) }
        )
    }

    private func events(in fixture: Fixture) throws -> [DoseEvent] {
        try fixture.context.fetch(FetchDescriptor<DoseEvent>()).sorted { $0.recordedAt < $1.recordedAt }
    }

    func testAFailedQueryLeavesTheLedgerUntouched() async throws {
        let fixture = try makeFixture(createdAt: date(1, 0))
        let mirrored = DoseEvent(medicationID: fixture.medication.id, recordedAt: date(10, 9), doseQuantity: 1, status: .taken,
                                 note: DoseEvent.appleHealthNote, healthSampleID: UUID())
        fixture.context.insert(mirrored)
        try fixture.context.save()

        let outcome = await HealthDoseSync.run(
            in: fixture.context,
            now: now,
            source: source(shared: [entry("zoloft")]) { _ in throw QueryFailed() }
        )

        XCTAssertEqual(outcome, .init(linkedMedications: 1))
        XCTAssertEqual(try events(in: fixture).map(\.id), [mirrored.id], "a failed query says nothing about what Health holds")
    }

    func testDosesFromBeforeTheMedicationWasAddedDoNotChargeTheCount() async throws {
        let fixture = try makeFixture(createdAt: date(8, 12))
        let before = record(date(7, 20))
        let after = record(date(9, 20))

        let outcome = await HealthDoseSync.run(
            in: fixture.context,
            now: now,
            source: source(shared: [entry("zoloft")]) { _ in [before, after] }
        )

        XCTAssertEqual(outcome?.inserted, 1)
        let stored = try events(in: fixture)
        XCTAssertEqual(stored.map(\.healthSampleID), [after.sampleID])
        XCTAssertEqual(stored.first?.countsTowardSupply, true)
    }

    func testTwoOverlappingRunsInsertOnce() async throws {
        let fixture = try makeFixture(createdAt: date(1, 0))
        let dose = record(date(10, 9))
        let slow = source(shared: [entry("zoloft")]) { _ in
            try await Task.sleep(for: .milliseconds(150))
            return [dose]
        }

        async let first = HealthDoseSync.run(in: fixture.context, now: now, source: slow)
        async let second = HealthDoseSync.run(in: fixture.context, now: now, source: slow)
        let outcomes = await [first, second]

        XCTAssertEqual(outcomes.map { $0?.inserted }, [1, 1], "the second caller waits for the pass under way and gets its answer")
        XCTAssertEqual(try events(in: fixture).count, 1)
    }

    /// The brand archived in Health after a switch to the generic, both coded
    /// to the same drug: one history here, not two entries taking turns
    /// deleting each other's doses.
    func testTwoHealthEntriesForOneMedicationAreStableAcrossSyncs() async throws {
        let fixture = try makeFixture(createdAt: date(1, 0))
        let brandDose = record(date(9, 20))
        let genericDose = record(date(10, 20))
        let source = source(shared: [entry("brand", archived: true), entry("generic")]) { id in
            id == "brand" ? [brandDose] : [genericDose]
        }

        let first = await HealthDoseSync.run(in: fixture.context, now: now, source: source)
        XCTAssertEqual(first, .init(linkedMedications: 1, inserted: 2))

        let second = await HealthDoseSync.run(in: fixture.context, now: now, source: source)
        XCTAssertEqual(second, .init(linkedMedications: 1))
        XCTAssertEqual(try events(in: fixture).compactMap(\.healthSampleID), [brandDose.sampleID, genericDose.sampleID])
    }

    /// Settings' Check Now replans only after a pass that changed a dose
    /// here: reminders are planned from those doses.
    func testAPassThatChangesADoseAsksForAReplan() async throws {
        let fixture = try makeFixture(createdAt: date(1, 0))
        let dose = record(date(10, 9))
        let source = source(shared: [entry("zoloft")]) { _ in [dose] }

        let first = await HealthDoseSync.run(in: fixture.context, now: now, source: source)
        XCTAssertEqual(first?.changedDoses, true, "a dose brought over")
        let second = await HealthDoseSync.run(in: fixture.context, now: now, source: source)
        XCTAssertEqual(second?.changedDoses, false, "nothing new")

        XCTAssertTrue(HealthDoseSync.Outcome(linkedMedications: 1, removed: 1).changedDoses, "a dose undone in Health")
        XCTAssertTrue(HealthDoseSync.Outcome(linkedMedications: 1, updated: 1).changedDoses)
        XCTAssertTrue(HealthDoseSync.Outcome(linkedMedications: 1, adopted: 1).changedDoses)
    }

    func testAnEntryThatDescribesTwoMedicationsHereTouchesNeither() throws {
        let fixture = try makeFixture(createdAt: date(1, 0))
        let second = Medication(name: "Sertraline for someone else", createdAt: date(1, 0), rxNormCode: "312938")
        fixture.context.insert(second)

        let groups = HealthDoseSync.groups(of: [entry("zoloft")], matching: [fixture.medication, second], table: .shared)

        XCTAssertTrue(groups.isEmpty)
    }
}
