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

    /// A reminder for the edited time refers to the same dose as the one that
    /// was already logged against the old time that day.
    @MainActor
    func testReminderActionAfterATimeEditDoesNotLogTheDoseAgain() throws {
        let fixture = try makeFixture()
        _ = try NotificationDoseRecorder.record(
            status: .taken,
            medicationID: fixture.medication.id,
            scheduleID: fixture.schedule.id,
            notificationDate: fixture.notificationDate,
            in: fixture.context,
            calendar: fixture.calendar
        )

        fixture.schedule.minutesAfterMidnight = 20 * 60
        try fixture.context.save()
        let result = try NotificationDoseRecorder.record(
            status: .taken,
            medicationID: fixture.medication.id,
            scheduleID: fixture.schedule.id,
            notificationDate: fixture.notificationDate.addingTimeInterval(11.5 * 60 * 60),
            in: fixture.context,
            calendar: fixture.calendar
        )

        XCTAssertEqual(result, .alreadyRecorded)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<DoseEvent>()), 1)
    }

    /// A dated reminder or a follow-up names its slot. A follow-up for a
    /// 23:45 dose arrives at 00:15, on a day with a 23:45 dose of its own,
    /// which is not the dose it asked about.
    @MainActor
    func testAReminderNamingItsSlotLogsThatDaysDose() throws {
        let fixture = try makeFixture()
        fixture.schedule.minutesAfterMidnight = 23 * 60 + 45
        try fixture.context.save()
        let slot = try XCTUnwrap(fixture.calendar.date(bySettingHour: 23, minute: 45, second: 0, of: fixture.scheduledDate))
        let delivered = slot.addingTimeInterval(ScheduleEngine.dueWindow)
        XCTAssertFalse(fixture.calendar.isDate(delivered, inSameDayAs: slot))

        let result = try NotificationDoseRecorder.record(
            status: .taken,
            medicationID: fixture.medication.id,
            scheduleID: fixture.schedule.id,
            notificationDate: delivered,
            slotDate: slot,
            in: fixture.context,
            calendar: fixture.calendar
        )

        XCTAssertEqual(result, .recorded)
        let event = try XCTUnwrap(try fixture.context.fetch(FetchDescriptor<DoseEvent>()).first)
        XCTAssertEqual(event.scheduledAt, slot)
        XCTAssertEqual(
            try NotificationDoseRecorder.record(status: .taken, medicationID: fixture.medication.id, scheduleID: fixture.schedule.id,
                                                notificationDate: delivered, slotDate: slot, in: fixture.context, calendar: fixture.calendar),
            .alreadyRecorded
        )
    }

    func testTheSlotARequestNamesSurvivesItsUserInfo() throws {
        let slot = Date(timeIntervalSince1970: 1_788_000_000.25)
        let userInfo: [AnyHashable: Any] = [NotificationIdentifiers.slotDateKey: NotificationIdentifiers.slotDateValue(slot)]
        XCTAssertEqual(NotificationIdentifiers.slotDate(in: userInfo), slot)
        XCTAssertNil(NotificationIdentifiers.slotDate(in: [:]))
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
