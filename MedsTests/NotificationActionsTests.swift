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
            slotDay: slot,
            in: fixture.context,
            calendar: fixture.calendar
        )

        XCTAssertEqual(result, .recorded)
        let event = try XCTUnwrap(try fixture.context.fetch(FetchDescriptor<DoseEvent>()).first)
        XCTAssertEqual(event.scheduledAt, slot)
        XCTAssertEqual(
            try NotificationDoseRecorder.record(status: .taken, medicationID: fixture.medication.id, scheduleID: fixture.schedule.id,
                                                notificationDate: delivered, slotDay: slot, in: fixture.context, calendar: fixture.calendar),
            .alreadyRecorded
        )
    }

    func testTheDayARequestNamesSurvivesItsUserInfo() throws {
        var gmt = Calendar(identifier: .gregorian)
        gmt.timeZone = TimeZone(secondsFromGMT: 0)!
        let slot = try XCTUnwrap(gmt.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 23, minute: 45)))
        let userInfo: [AnyHashable: Any] = [NotificationIdentifiers.slotDayKey: NotificationIdentifiers.slotDayValue(slot, calendar: gmt)]
        XCTAssertEqual(userInfo[NotificationIdentifiers.slotDayKey] as? String, "20260910")
        XCTAssertEqual(NotificationIdentifiers.slotDay(in: userInfo, calendar: gmt),
                       gmt.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 12)))
        XCTAssertNil(NotificationIdentifiers.slotDay(in: [:], calendar: gmt))
        XCTAssertNil(NotificationIdentifiers.slotDay(in: [NotificationIdentifiers.slotDayKey: "1788000000.25"], calendar: gmt))

        // The same day whatever calendar the phone is set to.
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = gmt.timeZone
        XCTAssertEqual(NotificationIdentifiers.slotDayValue(slot, calendar: japanese), "20260910")
    }

    /// A course's reminder planned in Sydney for 08:00 on the 11th rings at
    /// 08:00 on the 11th in Los Angeles, where the family has flown: its
    /// trigger follows the phone's clock. That instant in Sydney is the 10th
    /// in Los Angeles, and Taken must still log the 11th's dose.
    @MainActor
    func testADatedReminderAnsweredInAnotherTimeZoneLogsTheDayItNamed() throws {
        var sydney = Calendar(identifier: .gregorian)
        sydney.timeZone = try XCTUnwrap(TimeZone(identifier: "Australia/Sydney"))
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let schema = Schema([Medication.self, DoseSchedule.self, DoseEvent.self, InventoryEvent.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let medication = Medication(name: "Course")
        let schedule = DoseSchedule(
            medicationID: medication.id,
            minutesAfterMidnight: 8 * 60,
            startDate: try XCTUnwrap(sydney.date(from: DateComponents(year: 2026, month: 9, day: 1))),
            endDate: try XCTUnwrap(sydney.date(from: DateComponents(year: 2026, month: 9, day: 13)))
        )
        context.insert(medication)
        context.insert(schedule)
        try context.save()

        let plannedAt = try XCTUnwrap(sydney.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 12)))
        let built = NotificationPlanBuilder.make(medication: medication, schedules: [schedule], inventoryEvents: [], doseEvents: [],
                                                 now: plannedAt, calendar: sydney)
        let reminder = try XCTUnwrap(NotificationPlanner.plan(for: [built], now: plannedAt, calendar: sydney)
            .notifications.first { $0.identifier == "meds.group.dose.date.20260911.0800" })
        let content = NotificationService.content(for: reminder, calendar: sydney)
        let deliveredInLosAngeles = try XCTUnwrap(losAngeles.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 8)))

        let result = try NotificationDoseRecorder.record(
            status: .taken,
            medicationID: medication.id,
            scheduleID: schedule.id,
            notificationDate: deliveredInLosAngeles,
            slotDay: NotificationIdentifiers.slotDay(in: content.userInfo, calendar: losAngeles),
            in: context,
            calendar: losAngeles
        )

        XCTAssertEqual(result, .recorded)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DoseEvent>()).first?.scheduledAt, deliveredInLosAngeles,
                       "the 11th's dose, at 08:00 where the phone is now")
    }

    /// A course whose last day was a week or more away was planned as a
    /// repeating request, and it rings past the end when nothing replanned
    /// in the course's last week. Its Taken finds no dose to log, and must
    /// still replan, or it rings every morning for a course that is over.
    @MainActor
    func testTakenOnAReminderForAnEndedCourseLogsNothingAndWithdrawsIt() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func at(_ day: Int, _ hour: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour)))
        }
        let schema = Schema([Medication.self, DoseSchedule.self, DoseEvent.self, InventoryEvent.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let medication = Medication(name: "Course", createdAt: try at(4, 0))
        let schedule = DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, startDate: try at(4, 0),
                                    endDate: ScheduleEngine.normalizedEndDate(forDay: try at(17, 0), calendar: calendar))
        context.insert(medication)
        context.insert(schedule)
        try context.save()

        let plannedOnThe9th = NotificationPlanner.plan(
            for: NotificationPlanBuilder.makeAll(medications: [medication], schedules: [schedule], inventoryEvents: [], doseEvents: [],
                                                 now: try at(9, 12), calendar: calendar),
            now: try at(9, 12),
            calendar: calendar
        )
        let stale = try XCTUnwrap(plannedOnThe9th.notifications.first { $0.identifier == "meds.group.dose.daily.0800" })
        XCTAssertTrue(stale.supportsDoseQuickActions)

        let answered = try NotificationDoseRecorder.respond(
            status: .taken,
            medicationID: medication.id,
            scheduleID: schedule.id,
            notificationDate: try at(18, 8),
            in: context,
            now: try at(18, 8),
            calendar: calendar
        )
        XCTAssertEqual(answered.result, .missingContext)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DoseEvent>()), 0, "nothing to log after the last day")
        let replanned = NotificationPlanner.plan(for: answered.plans, now: try at(18, 8), calendar: calendar)
        XCTAssertEqual(
            NotificationService.pendingIdentifiersToRemove(pending: [stale.identifier], planned: Set(replanned.notifications.map(\.identifier))),
            [stale.identifier],
            "the replan withdraws the reminder that rang past the course's end"
        )
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
