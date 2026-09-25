import SwiftData
import XCTest
@testable import Meds

/// "Remind again if not logged": one more reminder, 30 minutes after a dose
/// time, for doses this phone has no log of. Planned on Thursday
/// 10 September 2026 at 07:00, in GMT, unless a test says otherwise.
final class FollowUpReminderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { at(10, 7) }
    private let on = NotificationPlanOptions(followUpReminders: true)

    private func followUps(_ plans: [MedicationNotificationPlan], at moment: Date? = nil, options: NotificationPlanOptions? = nil) -> [PlannedNotification] {
        NotificationPlanner.plan(for: plans, now: moment ?? now, calendar: calendar, options: options ?? on)
            .notifications.filter { $0.kind == .followUp }
    }

    func testFollowUpsAreOffUnlessChosen() throws {
        let plans = [plan(name: "Ongoing", schedules: [schedule(8 * 60)])]
        XCTAssertTrue(followUps(plans, options: NotificationPlanOptions()).isEmpty)

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FollowUpReminderTests.\(UUID().uuidString)"))
        XCTAssertFalse(NotificationPlanOptions.stored(in: defaults).followUpReminders, "off until someone turns it on")
        defaults.set(true, forKey: NotificationPlanOptions.followUpRemindersKey)
        XCTAssertTrue(NotificationPlanOptions.stored(in: defaults).followUpReminders)
    }

    func testOneFollowUpPerUnloggedDoseTimeInTheNextDay() throws {
        let ongoing = plan(name: "Ongoing", schedules: [schedule(8 * 60), schedule(6 * 60)])
        let course = plan(name: "Course", schedules: [schedule(8 * 60, start: at(1), end: at(12))])
        let logged = plan(name: "Logged", schedules: [schedule(8 * 60, logged: [at(10)])])
        let evening = plan(name: "Evening", schedules: [schedule(20 * 60)])
        let planned = followUps([ongoing, course, logged, evening])

        XCTAssertEqual(planned.map(\.identifier), [
            "meds.group.followup.20260910.0800",
            "meds.group.followup.20260910.2000",
            "meds.group.followup.20260911.0600"
        ], "not today's 06:00, whose follow-up moment has passed, nor tomorrow's 08:00, a day away")
        let morning = try XCTUnwrap(planned.first)
        XCTAssertEqual(morning.identifier, NotificationIdentifiers.followUp(at: at(10, 8), calendar: calendar), "the name the widget withdraws it by")
        XCTAssertEqual(morning.trigger, .date(at(10, 8, 30)))
        XCTAssertEqual(morning.slotDate, at(10, 8))
        XCTAssertEqual(morning.groupedDoseCount, 2, "the steady and the dated medication together; the logged one is not asked about")
        XCTAssertEqual(Set(morning.memberScheduleIDs), [ongoing.schedules[0].id, course.schedules[0].id])
        XCTAssertFalse(morning.supportsDoseQuickActions)
        XCTAssertTrue(morning.title.hasSuffix("doses not logged yet"), morning.title)
        XCTAssertEqual(morning.body, "They aren't logged on this phone yet. Check before giving them, in case someone already did.")
    }

    func testAFollowUpForOneDoseKeepsItsQuickActions() throws {
        let quiet = plan(name: "Private Medicine", schedules: [schedule(20 * 60)])
        let single = try XCTUnwrap(followUps([quiet]).first)
        XCTAssertTrue(single.supportsDoseQuickActions)
        XCTAssertEqual(single.medicationID, quiet.medicationID)
        XCTAssertEqual(single.scheduleID, quiet.schedules[0].id)
        XCTAssertTrue(single.title.hasSuffix("dose not logged yet"), single.title)
        XCTAssertFalse(single.title.contains("Private Medicine") || single.body.contains("Private Medicine"))

        let named = try XCTUnwrap(followUps([plan(name: "Tacrolimus", detailed: true, schedules: [schedule(20 * 60)])]).first)
        XCTAssertEqual(named.title, "Tacrolimus not logged yet")
        XCTAssertTrue(named.body.hasSuffix("dose isn't logged on this phone yet. Check before giving it, in case someone already did."), named.body)
    }

    func testLoggingTheDoseDropsItsFollowUp() {
        let before = followUps([plan(name: "Ongoing", schedules: [schedule(8 * 60)])], at: at(10, 8, 5))
        XCTAssertEqual(before.map(\.identifier), ["meds.group.followup.20260910.0800", "meds.group.followup.20260911.0800"])
        let after = NotificationPlanner.plan(for: [plan(name: "Ongoing", schedules: [schedule(8 * 60, logged: [at(10)])])],
                                             now: at(10, 8, 5), calendar: calendar, options: on)
        XCTAssertEqual(after.notifications.filter { $0.kind == .followUp }.map(\.identifier), ["meds.group.followup.20260911.0800"])
        XCTAssertEqual(NotificationService.pendingIdentifiersToRemove(pending: before.map(\.identifier), planned: Set(after.notifications.map(\.identifier))),
                       ["meds.group.followup.20260910.0800"], "logging in the app replans, and the follow-up is cancelled")
    }

    func testAFollowUpThatRangStaysWhileItsDoseIsUnlogged() {
        let rang = "meds.group.followup.20260910.0800"
        let unlogged = NotificationPlanner.plan(for: [plan(name: "Ongoing", schedules: [schedule(8 * 60)])], now: at(10, 9), calendar: calendar, options: on)
        XCTAssertEqual(NotificationService.deliveredIdentifiersToRemove(delivered: [rang], outcome: unlogged), [])
        let logged = NotificationPlanner.plan(for: [plan(name: "Ongoing", schedules: [schedule(8 * 60, logged: [at(10)])])], now: at(10, 9), calendar: calendar, options: on)
        XCTAssertEqual(NotificationService.deliveredIdentifiersToRemove(delivered: [rang], outcome: logged), [rang])
        let turnedOff = NotificationPlanner.plan(for: [plan(name: "Ongoing", schedules: [schedule(8 * 60)])], now: at(10, 9), calendar: calendar)
        XCTAssertEqual(NotificationService.deliveredIdentifiersToRemove(delivered: [rang], outcome: turnedOff), [rang])
    }

    func testFollowUpsComeAfterDatedRemindersAndBeforeRefillAlerts() throws {
        func plans(weekly: Int) -> [MedicationNotificationPlan] {
            (0..<weekly).map { plan(name: "Weekly \($0)", schedules: [schedule(6 * 60 + $0, mask: 1 << 1)]) }
                + [plan(name: "Course", schedules: [schedule(9 * 60, start: at(1), end: at(16))])]
                + [MedicationNotificationPlan(
                    medicationID: UUID(), displayName: "Refill", form: .tablet, isAsNeeded: false, isArchived: false,
                    doseRemindersEnabled: true, refillRemindersEnabled: true, detailedNotifications: false, refillLeadDays: 7,
                    refillsRemaining: nil, depletionDate: at(20), schedules: []
                )]
        }
        let roomy = NotificationPlanner.plan(for: plans(weekly: 50), now: now, calendar: calendar, options: on).notifications
        XCTAssertEqual(roomy.count, 59)
        XCTAssertEqual(roomy.suffix(9).map(\.kind), [.dose, .dose, .dose, .dose, .dose, .dose, .dose, .followUp, .refill])

        let full = NotificationPlanner.plan(for: plans(weekly: 53), now: now, calendar: calendar, options: on)
        XCTAssertEqual(full.notifications.count, NotificationPlanner.maximumScheduledRequests)
        XCTAssertFalse(full.notifications.contains { $0.kind == .followUp || $0.kind == .refill })
        XCTAssertEqual(full.droppedDoseReminders, 0, "a follow-up repeats a question already asked")
    }

    // MARK: - When the clocks change

    /// When a one-shot request rings: the first moment after it was planned
    /// that the clock shows its time. Its trigger names no zone, so the time
    /// is all iOS has, and on the night the clocks go back it takes the first
    /// of the two.
    private func ringsAt(_ followUp: PlannedNotification, plannedAt now: Date, calendar: Calendar) throws -> Date {
        guard case let .date(moment) = followUp.trigger else { throw XCTSkip("not a one-shot") }
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: moment)
        return try XCTUnwrap(calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime, repeatedTimePolicy: .first))
    }

    func testAFollowUpOnTheNightTheClocksGoBackComesAfterItsDose() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let plannedAt = try XCTUnwrap(newYork.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0, minute: 10)))
        let night = plan(name: "Night", schedules: [schedule(60 + 30)])
        let followUp = try XCTUnwrap(NotificationPlanner.plan(for: [night], now: plannedAt, calendar: newYork, options: on)
            .notifications.first { $0.identifier == "meds.group.followup.20261101.0130" })
        let slot = try XCTUnwrap(followUp.slotDate)

        let rings = try ringsAt(followUp, plannedAt: plannedAt, calendar: newYork)
        XCTAssertGreaterThanOrEqual(rings, slot.addingTimeInterval(ScheduleEngine.dueWindow), "never before the dose it asks about")
        XCTAssertEqual(newYork.dateComponents([.hour, .minute], from: rings), DateComponents(hour: 2, minute: 0), "02:00 on the clock")
    }

    /// Every dose time through each kind of clock change: Lord Howe's
    /// half-hour one, and Santiago's at midnight. A follow-up rings at least
    /// half an hour after its dose, and within an hour and a half.
    func testEveryFollowUpOnADaylightSavingDayRingsAfterItsDose() throws {
        let days: [(String, Int, Int)] = [
            ("America/New_York", 3, 8), ("America/New_York", 11, 1),
            ("Europe/London", 3, 29), ("Europe/London", 10, 25),
            ("Australia/Lord_Howe", 4, 5), ("Australia/Lord_Howe", 10, 4),
            ("America/Santiago", 4, 5), ("America/Santiago", 9, 6)
        ]
        var checked = 0
        for (zone, month, day) in days {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
            let plannedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
            for minutes in stride(from: 0, to: 24 * 60, by: 5) {
                let outcome = NotificationPlanner.plan(for: [plan(name: "Dose", schedules: [schedule(minutes)])],
                                                       now: plannedAt, calendar: calendar, options: on)
                for followUp in outcome.notifications where followUp.kind == .followUp {
                    let slot = try XCTUnwrap(followUp.slotDate)
                    let rings = try ringsAt(followUp, plannedAt: plannedAt, calendar: calendar)
                    let label = "\(zone) \(month)/\(day) \(minutes / 60):\(minutes % 60)"
                    XCTAssertGreaterThanOrEqual(rings, slot.addingTimeInterval(ScheduleEngine.dueWindow), label)
                    XCTAssertLessThanOrEqual(rings, slot.addingTimeInterval(ScheduleEngine.dueWindow + 60 * 60), label)
                    checked += 1
                }
            }
        }
        XCTAssertGreaterThan(checked, 2_000)
    }

    // MARK: - The widget

    func testTheWidgetWithdrawsAFollowUpOnlyOnceEveryDoseInItIsLogged() {
        let medicationID = UUID()
        let first = DoseSchedule(medicationID: medicationID, minutesAfterMidnight: 8 * 60, startDate: at(1))
        let second = DoseSchedule(medicationID: UUID(), minutesAfterMidnight: 8 * 60, startDate: at(1))
        func log(_ schedule: DoseSchedule) -> DoseEvent {
            DoseEvent(medicationID: schedule.medicationID, scheduleID: schedule.id, scheduledAt: at(10, 8), recordedAt: at(10, 8, 40),
                      doseQuantity: 1, status: .taken)
        }
        func answered(_ members: [UUID], _ events: [DoseEvent]) -> Bool {
            NotificationIdentifiers.followUpIsAnswered(memberScheduleIDs: members, slot: at(10, 8), schedules: [first, second],
                                                       doseEvents: events, now: at(10, 8, 40), calendar: calendar)
        }
        XCTAssertFalse(answered([first.id, second.id], [log(first)]), "the other medication still needs asking about")
        XCTAssertTrue(answered([first.id, second.id], [log(first), log(second)]))
        XCTAssertTrue(answered([first.id], [log(first)]))
        XCTAssertFalse(answered([], [log(first)]), "one that does not say what it asks about keeps ringing")
        XCTAssertFalse(answered([UUID()], [log(first)]))

        let userInfo: [AnyHashable: Any] = [NotificationIdentifiers.memberScheduleIDsKey: NotificationIdentifiers.memberScheduleIDsValue([first.id, second.id])]
        XCTAssertEqual(NotificationIdentifiers.memberScheduleIDs(in: userInfo), [first.id, second.id])
        XCTAssertEqual(NotificationIdentifiers.memberScheduleIDs(in: [:]), [])
    }

    // MARK: - After midnight

    /// A follow-up for a 23:45 dose rings at 00:15. Its Taken logs the 23:45
    /// dose it asked about, not the one due at 23:45 on the day it rang.
    @MainActor
    func testALateEveningFollowUpLogsThePreviousDaysDose() throws {
        let schema = Schema([Medication.self, DoseSchedule.self, DoseEvent.self, InventoryEvent.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let medication = Medication(name: "Example", createdAt: at(1))
        let schedule = DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 23 * 60 + 45, startDate: at(1))
        context.insert(medication)
        context.insert(schedule)
        try context.save()

        let planned = NotificationPlanBuilder.make(medication: medication, schedules: [schedule], inventoryEvents: [], doseEvents: [],
                                                   now: at(11, 0, 5), calendar: calendar)
        let followUp = try XCTUnwrap(followUps([planned], at: at(11, 0, 5)).first)
        XCTAssertEqual(followUp.identifier, "meds.group.followup.20260910.2345")
        XCTAssertEqual(followUp.trigger, .date(at(11, 0, 15)))

        // Read back from the notification the service builds.
        let userInfo = NotificationService.content(for: followUp, calendar: calendar).userInfo
        let result = try NotificationDoseRecorder.record(
            status: .taken,
            medicationID: medication.id,
            scheduleID: schedule.id,
            notificationDate: at(11, 0, 15),
            slotDay: NotificationIdentifiers.slotDay(in: userInfo, calendar: calendar),
            in: context,
            calendar: calendar
        )
        XCTAssertEqual(result, .recorded)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DoseEvent>()).first?.scheduledAt, at(10, 23, 45))

        let replanned = NotificationPlanBuilder.make(medication: medication, schedules: [schedule], inventoryEvents: [],
                                                     doseEvents: try context.fetch(FetchDescriptor<DoseEvent>()), now: at(11, 0, 16), calendar: calendar)
        XCTAssertEqual(replanned.schedules.first?.loggedDays, [at(10)])
        XCTAssertEqual(followUps([replanned], at: at(11, 0, 16)).map(\.identifier), ["meds.group.followup.20260911.2345"],
                       "only that night's, still a day away")
    }

    // MARK: - Helpers

    private func schedule(
        _ minutes: Int,
        mask: Int = 0b1111111,
        start: Date = .distantPast,
        end: Date? = nil,
        logged: Set<Date> = []
    ) -> ScheduleNotificationPlan {
        ScheduleNotificationPlan(id: UUID(), minutesAfterMidnight: minutes, doseQuantity: 1, weekdayMask: mask,
                                 startDate: start, endDate: end, loggedDays: logged)
    }

    private func plan(name: String, detailed: Bool = false, schedules: [ScheduleNotificationPlan]) -> MedicationNotificationPlan {
        MedicationNotificationPlan(
            medicationID: UUID(),
            displayName: name,
            form: .tablet,
            isAsNeeded: false,
            isArchived: false,
            doseRemindersEnabled: true,
            refillRemindersEnabled: false,
            detailedNotifications: detailed,
            refillLeadDays: 7,
            refillsRemaining: nil,
            depletionDate: nil,
            schedules: schedules
        )
    }
}
