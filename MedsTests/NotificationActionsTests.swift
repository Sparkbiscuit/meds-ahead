import SwiftData
import UserNotifications
import XCTest
@testable import Meds

final class NotificationActionsTests: XCTestCase {
    @MainActor
    func testReminderActionRecordsScheduledDoseQuantity() throws {
        let fixture = try makeFixture()

        let result = try NotificationDoseRecorder.record(
            status: .taken,
            medicationID: fixture.medication.id,
            scheduleID: fixture.schedule.id,
            notificationDate: fixture.notificationDate,
            in: fixture.context,
            calendar: fixture.calendar
        )

        XCTAssertEqual(result, .recorded)
        let events = try fixture.context.fetch(FetchDescriptor<DoseEvent>())
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.status, .taken)
        XCTAssertEqual(event.doseQuantity, 1.5)
        XCTAssertEqual(event.scheduledAt, fixture.scheduledDate)
        XCTAssertEqual(event.note, "Logged from reminder")
    }

    @MainActor
    func testReminderActionDoesNotDuplicateExistingLog() throws {
        let fixture = try makeFixture()
        _ = try NotificationDoseRecorder.record(
            status: .taken,
            medicationID: fixture.medication.id,
            scheduleID: fixture.schedule.id,
            notificationDate: fixture.notificationDate,
            in: fixture.context,
            calendar: fixture.calendar
        )

        let secondResult = try NotificationDoseRecorder.record(
            status: .skipped,
            medicationID: fixture.medication.id,
            scheduleID: fixture.schedule.id,
            notificationDate: fixture.notificationDate,
            in: fixture.context,
            calendar: fixture.calendar
        )

        XCTAssertEqual(secondResult, .alreadyRecorded)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<DoseEvent>()), 1)
    }

    func testOnlyMedicationQuickActionsMapToDoseStatuses() {
        XCTAssertEqual(
            MedicationNotificationAction.status(for: MedicationNotificationAction.markTakenIdentifier),
            .taken
        )
        XCTAssertEqual(
            MedicationNotificationAction.status(for: MedicationNotificationAction.markSkippedIdentifier),
            .skipped
        )
        XCTAssertNil(MedicationNotificationAction.status(for: UNNotificationDefaultActionIdentifier))
    }

    func testNotificationTapsRouteRefillsToSupplyAndDosesToToday() {
        XCTAssertEqual(
            MedicationNotificationRoute.destination(for: ["notificationKind": "refill"]),
            .supply
        )
        XCTAssertEqual(
            MedicationNotificationRoute.destination(for: ["notificationKind": "dose"]),
            .today
        )
        XCTAssertEqual(MedicationNotificationRoute.destination(for: [:]), .today)
    }

    @MainActor
    private func makeFixture() throws -> Fixture {
        let schema = Schema([Medication.self, DoseSchedule.self, DoseEvent.self, InventoryEvent.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 8, minute: 30))
        )
        let medication = Medication(name: "Example")
        let schedule = DoseSchedule(
            medicationID: medication.id,
            minutesAfterMidnight: 8 * 60 + 30,
            doseQuantity: 1.5,
            startDate: calendar.startOfDay(for: day)
        )
        context.insert(medication)
        context.insert(schedule)
        try context.save()

        return Fixture(
            container: container,
            context: context,
            medication: medication,
            schedule: schedule,
            notificationDate: day.addingTimeInterval(45),
            scheduledDate: day,
            calendar: calendar
        )
    }
}

private struct Fixture {
    let container: ModelContainer
    let context: ModelContext
    let medication: Medication
    let schedule: DoseSchedule
    let notificationDate: Date
    let scheduledDate: Date
    let calendar: Calendar
}
