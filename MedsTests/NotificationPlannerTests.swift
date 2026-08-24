import XCTest
@testable import Meds

final class NotificationPlannerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testDailyScheduleUsesOneRepeatingNotification() throws {
        let plan = makePlan(refillRemindersEnabled: false)
        let notifications = NotificationPlanner.notifications(for: plan, calendar: calendar)

        XCTAssertEqual(notifications.count, 1)
        XCTAssertTrue(notifications.allSatisfy { $0.kind == .dose })
        XCTAssertEqual(notifications.first?.trigger, .daily(hour: 8, minute: 30))
        XCTAssertEqual(notifications.first?.groupedDoseCount, 1)
        XCTAssertEqual(notifications.first?.supportsDoseQuickActions, true)
    }

    func testSameTimeDailyMedicationsAreConsolidatedIntoOneReminder() throws {
        let first = makePlan(
            medicationID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            scheduleID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            displayName: "Morning One",
            refillRemindersEnabled: false
        )
        let second = makePlan(
            medicationID: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
            scheduleID: UUID(uuidString: "22222222-3333-4444-5555-666666666666")!,
            displayName: "Morning Two",
            refillRemindersEnabled: false
        )

        let doses = NotificationPlanner.notifications(for: [first, second], calendar: calendar)
            .filter { $0.kind == .dose }
        let reminder = try XCTUnwrap(doses.first)

        XCTAssertEqual(doses.count, 1)
        XCTAssertEqual(reminder.trigger, .daily(hour: 8, minute: 30))
        XCTAssertEqual(reminder.groupedDoseCount, 2)
        XCTAssertFalse(reminder.supportsDoseQuickActions)
        XCTAssertNil(reminder.medicationID)
        XCTAssertNil(reminder.scheduleID)
        XCTAssertTrue(reminder.title.lowercased().contains("meds are ready"))
    }

    func testMixedDailyAndWeekdaySchedulesStillProduceOnlyOneReminderPerSlot() throws {
        let daily = makePlan(
            medicationID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            scheduleID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            displayName: "Daily",
            refillRemindersEnabled: false
        )
        let monday = makePlan(
            medicationID: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
            scheduleID: UUID(uuidString: "22222222-3333-4444-5555-666666666666")!,
            displayName: "Monday",
            refillRemindersEnabled: false,
            weekdayMask: 1 << 1
        )

        let doses = NotificationPlanner.notifications(for: [daily, monday], calendar: calendar)
            .filter { $0.kind == .dose }
        let mondayReminder = try XCTUnwrap(
            doses.first { $0.trigger == .weekly(weekday: 2, hour: 8, minute: 30) }
        )

        XCTAssertEqual(doses.count, 7)
        XCTAssertEqual(Set(doses.map(\.trigger)).count, 7)
        XCTAssertEqual(mondayReminder.groupedDoseCount, 2)
        XCTAssertFalse(mondayReminder.supportsDoseQuickActions)
    }

    func testSelectedWeekdaysUseOneNotificationPerSelectedDay() {
        let plan = makePlan(refillRemindersEnabled: false, weekdayMask: (1 << 1) | (1 << 3))
        let notifications = NotificationPlanner.notifications(for: plan, calendar: calendar)

        XCTAssertEqual(notifications.count, 2)
        XCTAssertEqual(
            Set(notifications.map(\.trigger)),
            Set([
                .weekly(weekday: 2, hour: 8, minute: 30),
                .weekly(weekday: 4, hour: 8, minute: 30)
            ])
        )
    }

    func testPrivateNotificationCopyDoesNotRevealMedication() {
        let plan = makePlan(displayName: "Private Medicine", refillRemindersEnabled: false, detailedNotifications: false)
        let notifications = NotificationPlanner.notifications(for: plan, calendar: calendar)

        XCTAssertFalse(notifications.contains { $0.title.contains("Private Medicine") || $0.body.contains("Private Medicine") })
    }

    func testDetailedNotificationCopyNamesMedication() {
        let plan = makePlan(displayName: "Evening Tablet", refillRemindersEnabled: false, detailedNotifications: true)
        let notifications = NotificationPlanner.notifications(for: plan, calendar: calendar)

        XCTAssertTrue(notifications.contains { $0.title.contains("Evening Tablet") })
    }

    func testFutureRefillReminderUsesLeadDayAtNine() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        let depletion = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 8)))
        let plan = makePlan(doseRemindersEnabled: false, refillLeadDays: 7, depletionDate: depletion)
        let refill = try XCTUnwrap(NotificationPlanner.notifications(for: plan, now: now, calendar: calendar).first)

        guard case let .date(date) = refill.trigger else {
            return XCTFail("Expected a calendar date trigger")
        }
        XCTAssertEqual(calendar.component(.day, from: date), 13)
        XCTAssertEqual(calendar.component(.hour, from: date), 9)
    }

    func testPassedLeadDayCreatesNoRefillReminder() throws {
        // Lead day is 13 August; "now" is already past it, so the moment to warn
        // has gone. Re-announcing it here would fire again on every launch once
        // the person swiped the alert away.
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 12)))
        let depletion = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20)))
        let plan = makePlan(doseRemindersEnabled: false, refillLeadDays: 7, depletionDate: depletion)

        XCTAssertTrue(NotificationPlanner.notifications(for: plan, now: now, calendar: calendar).isEmpty)
    }

    func testDepletedSupplyCreatesNoRefillReminder() throws {
        // A medication saved with a current count of zero used to schedule an alert
        // three seconds after tapping Add.
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 12)))
        let plan = makePlan(doseRemindersEnabled: false, refillLeadDays: 7, depletionDate: now)

        XCTAssertTrue(NotificationPlanner.notifications(for: plan, now: now, calendar: calendar).isEmpty)
    }

    func testRefillReminderIdentityIsStableAcrossRebuilds() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        let depletion = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20)))
        let plan = makePlan(doseRemindersEnabled: false, refillLeadDays: 7, depletionDate: depletion)
        let first = try XCTUnwrap(NotificationPlanner.notifications(for: plan, now: now, calendar: calendar).first)
        let second = try XCTUnwrap(NotificationPlanner.notifications(for: plan, now: now, calendar: calendar).first)

        XCTAssertEqual(first.identifier, second.identifier)
    }

    func testUnknownForecastDoesNotCreateRefillNotification() {
        let plan = makePlan(doseRemindersEnabled: false, depletionDate: nil)
        XCTAssertTrue(NotificationPlanner.notifications(for: plan, calendar: calendar).isEmpty)
    }

    func testArchivedMedicationCreatesNoNotifications() {
        let plan = makePlan(isArchived: true)
        XCTAssertTrue(NotificationPlanner.notifications(for: plan, calendar: calendar).isEmpty)
    }

    private func makePlan(
        medicationID: UUID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        scheduleID: UUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        displayName: String = "Example",
        isArchived: Bool = false,
        doseRemindersEnabled: Bool = true,
        refillRemindersEnabled: Bool = true,
        detailedNotifications: Bool = false,
        refillLeadDays: Int = 7,
        depletionDate: Date? = nil,
        weekdayMask: Int = 0b1111111
    ) -> MedicationNotificationPlan {
        MedicationNotificationPlan(
            medicationID: medicationID,
            displayName: displayName,
            unitName: "tablet",
            isAsNeeded: false,
            isArchived: isArchived,
            doseRemindersEnabled: doseRemindersEnabled,
            refillRemindersEnabled: refillRemindersEnabled,
            detailedNotifications: detailedNotifications,
            refillLeadDays: refillLeadDays,
            depletionDate: depletionDate,
            schedules: [
                ScheduleNotificationPlan(
                    id: scheduleID,
                    minutesAfterMidnight: 8 * 60 + 30,
                    doseQuantity: 1,
                    weekdayMask: weekdayMask
                )
            ]
        )
    }
}
