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
    private struct ReadFailed: Error {}

    /// The store, except that one model type cannot be read.
    private struct Unreadable<Failing: PersistentModel>: ModelFetching {
        let context: ModelContext

        func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
            if T.self == Failing.self { throw ReadFailed() }
            return try context.fetch(descriptor)
        }
    }

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

    func testAFailedDoseReadStoresNoDoseAgain() async throws {
        let fixture = try makeFixture(createdAt: date(1, 0))
        let dose = record(date(10, 9))
        let mirrored = DoseEvent(medicationID: fixture.medication.id, recordedAt: dose.date, doseQuantity: 1, status: .taken,
                                 note: DoseEvent.appleHealthNote, healthSampleID: dose.sampleID)
        fixture.context.insert(mirrored)
        try fixture.context.save()

        let outcome = await HealthDoseSync.run(
            in: fixture.context,
            now: now,
            source: source(shared: [entry("zoloft")]) { _ in [dose] },
            reading: Unreadable<DoseEvent>(context: fixture.context)
        )

        XCTAssertEqual(outcome?.inserted, 0)
        XCTAssertEqual(try events(in: fixture).map(\.id), [mirrored.id], "a failed read is not an empty ledger")
    }

    /// Health's dose for a slot logged here two hours earlier is the same
    /// dose only by its slot, so the schedules must be read to know it.
    func testAFailedScheduleReadStoresNoSecondDose() async throws {
        let fixture = try makeFixture(createdAt: date(1, 0))
        let schedule = DoseSchedule(medicationID: fixture.medication.id, minutesAfterMidnight: 8 * 60, startDate: date(1, 0), createdAt: date(1, 0))
        // The sync finds slots in the phone's calendar, so 08:00 is the phone's.
        let slot = try XCTUnwrap(Calendar.autoupdatingCurrent.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 8)))
        let logged = DoseEvent(medicationID: fixture.medication.id, scheduleID: schedule.id, scheduledAt: slot,
                               recordedAt: slot, doseQuantity: 1, status: .taken)
        fixture.context.insert(schedule)
        fixture.context.insert(logged)
        try fixture.context.save()
        let late = HealthDoseRecord(sampleID: UUID(), date: slot.addingTimeInterval(2 * 60 * 60), scheduledDate: slot, quantity: 1, status: .taken)
        let source = source(shared: [entry("zoloft")]) { _ in [late] }

        let unread = await HealthDoseSync.run(in: fixture.context, now: now, source: source, reading: Unreadable<DoseSchedule>(context: fixture.context))
        XCTAssertNil(unread)
        XCTAssertEqual(try events(in: fixture).map(\.id), [logged.id], "a failed read is not a medication without schedules")

        let read = await HealthDoseSync.run(in: fixture.context, now: now, source: source)
        XCTAssertEqual(read?.inserted, 0, "read whole, the slot says it is the same dose")
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
