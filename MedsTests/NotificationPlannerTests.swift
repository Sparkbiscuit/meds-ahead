import XCTest
@testable import Meds

final class NotificationPlannerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testDailyScheduleCreatesSevenWeeklyDoseNotifications() throws {
        let plan = makePlan(refillRemindersEnabled: false)
        let notifications = NotificationPlanner.notifications(for: plan, calendar: calendar)

        XCTAssertEqual(notifications.count, 7)
        XCTAssertTrue(notifications.allSatisfy { $0.kind == .dose })
        XCTAssertEqual(Set(notifications.map(\.identifier)).count, 7)
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

    func testAlreadyLowSupplyUsesOneImmediateReminderIdentity() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 12)))
        let depletion = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20)))
        let plan = makePlan(doseRemindersEnabled: false, refillLeadDays: 7, depletionDate: depletion)
        let first = try XCTUnwrap(NotificationPlanner.notifications(for: plan, now: now, calendar: calendar).first)
        let second = try XCTUnwrap(NotificationPlanner.notifications(for: plan, now: now, calendar: calendar).first)

        XCTAssertEqual(first.identifier, second.identifier)
        XCTAssertEqual(first.trigger, .interval(3))
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
        displayName: String = "Example",
        isArchived: Bool = false,
        doseRemindersEnabled: Bool = true,
        refillRemindersEnabled: Bool = true,
        detailedNotifications: Bool = false,
        refillLeadDays: Int = 7,
        depletionDate: Date? = nil
    ) -> MedicationNotificationPlan {
        MedicationNotificationPlan(
            medicationID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
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
                    id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                    minutesAfterMidnight: 8 * 60 + 30,
                    doseQuantity: 1,
                    weekdayMask: 0b1111111
                )
            ]
        )
    }
}
