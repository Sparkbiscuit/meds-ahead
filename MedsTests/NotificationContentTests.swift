import UserNotifications
import XCTest
@testable import Meds

/// What each kind of planned request carries once it is a notification:
/// Taken and Skip, the widget and the tap all read it back. Planned on
/// Thursday 10 September 2026 at 07:00, in GMT.
final class NotificationContentTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { at(10, 7) }

    private func userInfo(_ content: UNNotificationContent) -> [String: String] {
        content.userInfo as? [String: String] ?? [:]
    }

    func testADatedReminderForOneDoseCarriesItsSlotAndQuickActions() throws {
        let course = plan(name: "Course", schedules: [schedule(8 * 60, start: at(1), end: at(12))])
        let reminder = try XCTUnwrap(NotificationPlanner.plan(for: [course], now: now, calendar: calendar)
            .notifications.first { $0.identifier == "meds.group.dose.date.20260911.0800" })
        let content = NotificationService.content(for: reminder)
        let info = userInfo(content)

        XCTAssertEqual(info["notificationKind"], "dose")
        XCTAssertEqual(info["medicationID"], course.medicationID.uuidString)
        XCTAssertEqual(info["scheduleID"], course.schedules[0].id.uuidString)
        XCTAssertEqual(NotificationIdentifiers.slotDate(in: content.userInfo), at(11, 8), "Taken logs the dose this reminder names")
        XCTAssertEqual(content.categoryIdentifier, MedicationNotificationAction.doseCategoryIdentifier)
        XCTAssertEqual(content.threadIdentifier, "meds.dose")
        XCTAssertEqual(content.interruptionLevel, .timeSensitive)
    }

    func testAFollowUpCarriesItsSlotAndWhatItAsksAbout() throws {
        let first = plan(name: "First", schedules: [schedule(8 * 60)])
        let second = plan(name: "Second", schedules: [schedule(8 * 60)])
        let options = NotificationPlanOptions(followUpReminders: true)
        let group = try XCTUnwrap(NotificationPlanner.plan(for: [first, second], now: now, calendar: calendar, options: options)
            .notifications.first { $0.kind == .followUp })
        let content = NotificationService.content(for: group)

        XCTAssertEqual(userInfo(content)["notificationKind"], "followUp")
        XCTAssertEqual(NotificationIdentifiers.slotDate(in: content.userInfo), at(10, 8))
        XCTAssertEqual(Set(NotificationIdentifiers.memberScheduleIDs(in: content.userInfo)),
                       [first.schedules[0].id, second.schedules[0].id], "what the widget checks before withdrawing it")
        XCTAssertEqual(content.categoryIdentifier, "", "a group has no single dose to log")
        XCTAssertEqual(content.threadIdentifier, "meds.dose")
        XCTAssertEqual(content.interruptionLevel, .timeSensitive, "it rings like the dose reminder it follows")

        let single = try XCTUnwrap(NotificationPlanner.plan(for: [first], now: now, calendar: calendar, options: options)
            .notifications.first { $0.kind == .followUp })
        let singleContent = NotificationService.content(for: single)
        XCTAssertEqual(singleContent.categoryIdentifier, MedicationNotificationAction.doseCategoryIdentifier)
        XCTAssertEqual(userInfo(singleContent)["scheduleID"], first.schedules[0].id.uuidString)
        XCTAssertEqual(NotificationIdentifiers.memberScheduleIDs(in: singleContent.userInfo), [first.schedules[0].id])
    }

    func testACountCheckIsAPlanAheadNoticeThatOpensToday() throws {
        let id = UUID()
        let counted = MedicationNotificationPlan(
            medicationID: id, displayName: "Counted", form: .tablet, isAsNeeded: false, isArchived: false,
            doseRemindersEnabled: true, refillRemindersEnabled: true, detailedNotifications: false, refillLeadDays: 7,
            refillsRemaining: nil, depletionDate: nil, schedules: [],
            countCheck: CountCheckPolicy.Candidate(medicationID: id, displayName: "Counted", isEligible: true, daysRemaining: 10,
                                                   needsCount: false, lastCountDate: at(1, 15))
        )
        let check = try XCTUnwrap(NotificationPlanner.plan(for: [counted], now: now, calendar: calendar)
            .notifications.first { $0.kind == .countCheck })
        let content = NotificationService.content(for: check)

        XCTAssertEqual(userInfo(content)["notificationKind"], "countCheck")
        XCTAssertEqual(MedicationNotificationRoute.destination(for: content.userInfo), .today)
        XCTAssertNil(NotificationIdentifiers.slotDate(in: content.userInfo))
        XCTAssertEqual(content.categoryIdentifier, "")
        XCTAssertEqual(content.threadIdentifier, "meds.refill")
        XCTAssertEqual(content.interruptionLevel, .active)
    }

    func testARepeatingReminderNamesNoSlot() throws {
        let ongoing = plan(name: "Ongoing", schedules: [schedule(8 * 60)])
        let reminder = try XCTUnwrap(NotificationPlanner.plan(for: [ongoing], now: now, calendar: calendar).notifications.first)
        XCTAssertEqual(reminder.identifier, "meds.group.dose.daily.0800")
        let content = NotificationService.content(for: reminder)
        XCTAssertNil(NotificationIdentifiers.slotDate(in: content.userInfo), "its day is the day it rings")
        XCTAssertEqual(content.categoryIdentifier, MedicationNotificationAction.doseCategoryIdentifier)
    }

    // MARK: - Helpers

    private func schedule(_ minutes: Int, start: Date = .distantPast, end: Date? = nil) -> ScheduleNotificationPlan {
        ScheduleNotificationPlan(id: UUID(), minutesAfterMidnight: minutes, doseQuantity: 1, weekdayMask: 0b1111111,
                                 startDate: start, endDate: end)
    }

    private func plan(name: String, schedules: [ScheduleNotificationPlan]) -> MedicationNotificationPlan {
        MedicationNotificationPlan(
            medicationID: UUID(), displayName: name, form: .tablet, isAsNeeded: false, isArchived: false,
            doseRemindersEnabled: true, refillRemindersEnabled: false, detailedNotifications: false, refillLeadDays: 7,
            refillsRemaining: nil, depletionDate: nil, schedules: schedules
        )
    }
}
