import SwiftData
import XCTest
@testable import Meds

final class ScheduleReconcilerTests: XCTestCase {
    @MainActor
    func testUnchangedTimesPreserveScheduleIdentifiers() throws {
        let fixture = try makeFixture(minutes: [8 * 60, 20 * 60])
        let originalIDs = fixture.schedules.map(\.id)

        let reconciled = ScheduleReconciler.reconcile(
            medicationID: fixture.medicationID,
            definitions: definitions(minutes: [8 * 60, 20 * 60], quantity: 2),
            existing: fixture.schedules,
            in: fixture.context
        )
        try fixture.context.save()

        XCTAssertEqual(reconciled.map(\.id), originalIDs)
        XCTAssertTrue(reconciled.allSatisfy { $0.doseQuantity == 2 })
    }

    @MainActor
    func testChangedTimeReusesOnlyUnmatchedSchedule() throws {
        let fixture = try makeFixture(minutes: [8 * 60, 20 * 60])
        let morningID = fixture.schedules[0].id
        let eveningID = fixture.schedules[1].id

        let reconciled = ScheduleReconciler.reconcile(
            medicationID: fixture.medicationID,
            definitions: definitions(minutes: [9 * 60, 20 * 60]),
            existing: fixture.schedules,
            in: fixture.context
        )
        try fixture.context.save()

        XCTAssertEqual(reconciled[0].id, morningID)
        XCTAssertEqual(reconciled[0].minutesAfterMidnight, 9 * 60)
        XCTAssertEqual(reconciled[1].id, eveningID)
        XCTAssertEqual(reconciled[1].minutesAfterMidnight, 20 * 60)
    }

    @MainActor
    func testRemovingScheduleKeepsItsDoseHistory() throws {
        let fixture = try makeFixture(minutes: [8 * 60, 20 * 60])
        let removedSchedule = fixture.schedules[1]
        let removedScheduleID = removedSchedule.id
        fixture.context.insert(
            DoseEvent(
                medicationID: fixture.medicationID,
                scheduleID: removedScheduleID,
                scheduledAt: .now,
                doseQuantity: 1,
                status: .taken
            )
        )
        try fixture.context.save()

        _ = ScheduleReconciler.reconcile(
            medicationID: fixture.medicationID,
            definitions: definitions(minutes: [8 * 60]),
            existing: fixture.schedules,
            in: fixture.context
        )
        try fixture.context.save()

        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<DoseSchedule>()), 1)
        let events = try fixture.context.fetch(FetchDescriptor<DoseEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.scheduleID, removedScheduleID)
    }

    @MainActor
    private func makeFixture(minutes: [Int]) throws -> ReconcilerFixture {
        let schema = Schema([Medication.self, DoseSchedule.self, DoseEvent.self, InventoryEvent.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let medication = Medication(name: "Example")
        context.insert(medication)
        let schedules = minutes.map { minute in
            let schedule = DoseSchedule(
                medicationID: medication.id,
                minutesAfterMidnight: minute
            )
            context.insert(schedule)
            return schedule
        }
        try context.save()
        return ReconcilerFixture(
            container: container,
            context: context,
            medicationID: medication.id,
            schedules: schedules
        )
    }

    private func definitions(minutes: [Int], quantity: Double = 1) -> [ScheduleDefinition] {
        minutes.map {
            ScheduleDefinition(
                minutesAfterMidnight: $0,
                doseQuantity: quantity,
                weekdayMask: 0b1111111
            )
        }
    }
}

private struct ReconcilerFixture {
    let container: ModelContainer
    let context: ModelContext
    let medicationID: UUID
    let schedules: [DoseSchedule]
}
