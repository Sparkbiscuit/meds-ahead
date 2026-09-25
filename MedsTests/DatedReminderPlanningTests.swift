import XCTest
@testable import Meds

/// Reminders for schedules with a first or last day inside the coming week:
/// a course that ends, a medication that starts later. Everything is planned
/// on Thursday 10 September 2026 at 07:00, in GMT.
final class DatedReminderPlanningTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { at(10, 7) }

    private let ongoingID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private let courseID = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    private func dose(_ outcome: NotificationPlanOutcome) -> [PlannedNotification] {
        outcome.notifications.filter { $0.kind == .dose }
    }

    // MARK: - Steady, dated, ended

    func testACourseEndingInsideTheWeekIsDatedWhileTheOngoingOneKeepsRepeating() throws {
        let ongoing = plan(ongoingID, name: "Ongoing", schedules: [schedule(8 * 60), schedule(20 * 60)])
        let course = plan(courseID, name: "Course", schedules: [schedule(8 * 60, start: at(1), end: at(12))])
        let outcome = NotificationPlanner.plan(for: [ongoing, course], now: now, calendar: calendar)
        let doses = dose(outcome)

        let morning = try XCTUnwrap(doses.first { $0.identifier == "meds.group.dose.daily.0800" })
        XCTAssertEqual(morning.trigger, .daily(hour: 8, minute: 0))
        XCTAssertEqual(morning.groupedDoseCount, 1, "the course is not in the repeating request")
        XCTAssertEqual(morning.medicationID, ongoingID)

        let dated = doses.filter { $0.identifier.hasPrefix("meds.group.dose.date.") }
        XCTAssertEqual(dated.map(\.identifier), [
            "meds.group.dose.date.20260910.0800",
            "meds.group.dose.date.20260911.0800",
            "meds.group.dose.date.20260912.0800"
        ], "today through its last day, and nothing after it")
        XCTAssertEqual(dated.map(\.trigger), [.date(at(10, 8)), .date(at(11, 8)), .date(at(12, 8))])
        XCTAssertTrue(dated.allSatisfy { $0.medicationID == courseID && $0.groupedDoseCount == 1 })
        XCTAssertEqual(dated.map(\.slotDate), [at(10, 8), at(11, 8), at(12, 8)])
        XCTAssertEqual(doses.count, 5, "two repeating for the ongoing medication, three dated for the course")
        XCTAssertNil(outcome.plannedThrough, "nothing dated is wanted after the week")
    }

    func testATimeOnlyTheOngoingMedicationUsesStaysOneRepeatingRequest() {
        let ongoing = plan(ongoingID, name: "Ongoing", schedules: [schedule(8 * 60), schedule(20 * 60)])
        let course = plan(courseID, name: "Course", schedules: [schedule(8 * 60, start: at(1), end: at(12))])
        let evening = dose(NotificationPlanner.plan(for: [ongoing, course], now: now, calendar: calendar))
            .filter { $0.identifier.hasSuffix("2000") }
        XCTAssertEqual(evening.map(\.identifier), ["meds.group.dose.daily.2000"])
        XCTAssertEqual(evening.first?.trigger, .daily(hour: 20, minute: 0))
    }

    /// A day and time a steady schedule and a dated one share rings twice:
    /// the repeating request cannot be left out on the course's days.
    func testASharedTimeRingsForBothOnTheCoursesDays() {
        let ongoing = plan(ongoingID, name: "Ongoing", schedules: [schedule(8 * 60)])
        let course = plan(courseID, name: "Course", schedules: [schedule(8 * 60, start: at(1), end: at(10))])
        let doses = dose(NotificationPlanner.plan(for: [ongoing, course], now: now, calendar: calendar))
        XCTAssertEqual(Set(doses.map(\.identifier)), ["meds.group.dose.daily.0800", "meds.group.dose.date.20260910.0800"])
    }

    func testAnEndedScheduleIsPlannedNothing() {
        let ended = plan(courseID, name: "Course", schedules: [schedule(8 * 60, start: at(1), end: at(9, 20))])
        let outcome = NotificationPlanner.plan(for: [ended], now: now, calendar: calendar)
        XCTAssertTrue(outcome.notifications.isEmpty, "\(outcome.notifications.map(\.identifier))")
        XCTAssertNil(outcome.plannedThrough)
    }

    func testAScheduleEndingAWeekOrMoreAwayRepeats() {
        let long = plan(courseID, name: "Course", schedules: [schedule(8 * 60, start: at(1), end: at(17))])
        XCTAssertEqual(dose(NotificationPlanner.plan(for: [long], now: now, calendar: calendar)).map(\.trigger), [.daily(hour: 8, minute: 0)],
                       "past its end only if the app is not opened for a week: ringing too long, never going quiet")
        let shorter = plan(courseID, name: "Course", schedules: [schedule(8 * 60, start: at(1), end: at(16))])
        XCTAssertEqual(dose(NotificationPlanner.plan(for: [shorter], now: now, calendar: calendar)).count, 7)
    }

    func testAScheduleStartingInFiveDaysIsDatedFromItsFirstDay() throws {
        let later = plan(courseID, name: "Later", schedules: [schedule(8 * 60, start: at(15))])
        let outcome = NotificationPlanner.plan(for: [later], now: now, calendar: calendar)
        XCTAssertEqual(dose(outcome).map(\.identifier), ["meds.group.dose.date.20260915.0800", "meds.group.dose.date.20260916.0800"])
        XCTAssertEqual(outcome.plannedThrough, at(16), "it goes on after the week, so the plan ends with the week")

        // Saved on the 15th after its 08:00 had passed: that morning is no dose.
        let savedLate = plan(courseID, name: "Later", schedules: [schedule(8 * 60, start: at(15, 9))])
        XCTAssertEqual(dose(NotificationPlanner.plan(for: [savedLate], now: now, calendar: calendar)).map(\.identifier),
                       ["meds.group.dose.date.20260916.0800"])

        // Once it has begun it repeats.
        let begun = NotificationPlanner.plan(for: [later], now: at(15, 7), calendar: calendar)
        XCTAssertEqual(dose(begun).map(\.trigger), [.daily(hour: 8, minute: 0)])
        XCTAssertNil(begun.plannedThrough)
    }

    func testAScheduleStartingAfterTheWeekIsNotPlannedYet() {
        let outcome = NotificationPlanner.plan(for: [plan(courseID, name: "Later", schedules: [schedule(8 * 60, start: at(20))])],
                                               now: now, calendar: calendar)
        XCTAssertTrue(outcome.notifications.isEmpty)
        XCTAssertEqual(outcome.plannedThrough, at(16))
    }

    func testDatedMembersAtTheSameMomentShareOneRequest() throws {
        let first = plan(ongoingID, name: "First", schedules: [schedule(9 * 60, start: at(1), end: at(11))])
        let second = plan(courseID, name: "Second", schedules: [schedule(9 * 60, start: at(11))])
        let doses = dose(NotificationPlanner.plan(for: [first, second], now: now, calendar: calendar))
        let shared = try XCTUnwrap(doses.first { $0.identifier == "meds.group.dose.date.20260911.0900" })
        XCTAssertEqual(shared.groupedDoseCount, 2)
        XCTAssertFalse(shared.supportsDoseQuickActions)
        XCTAssertNil(shared.medicationID)
        XCTAssertEqual(shared.slotDate, at(11, 9))
        XCTAssertEqual(doses.filter { $0.identifier.hasSuffix(".0900") }.count, 7, "the 10th for the first, 11th together, 12th to 16th for the second")
    }

    func testASingleDatedMemberKeepsQuickActionsAndItsSlot() throws {
        let course = plan(courseID, name: "Course", detailed: true, schedules: [schedule(8 * 60, start: at(1), end: at(10))])
        let reminder = try XCTUnwrap(dose(NotificationPlanner.plan(for: [course], now: now, calendar: calendar)).first)
        XCTAssertTrue(reminder.supportsDoseQuickActions)
        XCTAssertEqual(reminder.medicationID, courseID)
        XCTAssertEqual(reminder.scheduleID, course.schedules[0].id)
        XCTAssertEqual(reminder.slotDate, at(10, 8))
        XCTAssertEqual(reminder.title, "Time for Course")
    }

    func testARemovedDayOfTheWeekIsRespected() {
        // Thursday the 10th to Wednesday the 16th; Mondays and Wednesdays only.
        let course = plan(courseID, name: "Course", schedules: [schedule(8 * 60, mask: (1 << 1) | (1 << 3), start: at(1), end: at(16))])
        XCTAssertEqual(dose(NotificationPlanner.plan(for: [course], now: now, calendar: calendar)).map(\.identifier),
                       ["meds.group.dose.date.20260914.0800", "meds.group.dose.date.20260916.0800"])
    }

    // MARK: - The cap

    func testRepeatingRequestsComeFirstThenDatedOnesByDate() throws {
        // 57 Monday-only times leave room for three dated requests.
        var plans = (0..<57).map { index in
            plan(UUID(), name: "Weekly \(index)", schedules: [schedule(6 * 60 + index, mask: 1 << 1)])
        }
        plans.append(plan(UUID(), name: "Morning course", schedules: [schedule(9 * 60, start: at(1), end: at(16))]))
        plans.append(plan(UUID(), name: "Evening course", schedules: [schedule(21 * 60, start: at(1), end: at(16))]))
        plans.append(MedicationNotificationPlan(
            medicationID: UUID(), displayName: "Refill", form: .tablet, isAsNeeded: false, isArchived: false,
            doseRemindersEnabled: true, refillRemindersEnabled: true, detailedNotifications: false, refillLeadDays: 7,
            refillsRemaining: nil, depletionDate: at(20), schedules: []
        ))

        let outcome = NotificationPlanner.plan(for: plans, now: now, calendar: calendar)
        XCTAssertEqual(outcome.notifications.count, NotificationPlanner.maximumScheduledRequests)
        XCTAssertTrue(outcome.notifications.prefix(57).allSatisfy {
            if case .weekly = $0.trigger { return true } else { return false }
        })
        XCTAssertEqual(outcome.notifications.suffix(3).map(\.trigger), [.date(at(10, 9)), .date(at(10, 21)), .date(at(11, 9))])
        XCTAssertFalse(outcome.notifications.contains { $0.kind == .refill }, "a refill alert yields to every dose request")
        XCTAssertEqual(outcome.droppedDoseReminders, 1, "the 11th at 21:00 is inside two days; the 12th at 09:00 is not")
        XCTAssertEqual(outcome.plannedThrough, at(10), "the 11th is only partly planned")
    }

    func testEverythingFittingPlansNoLimit() {
        let plans = (0..<4).map { index in
            plan(UUID(), name: "Course \(index)", schedules: [schedule(8 * 60 + index * 60, start: at(1), end: at(14))])
        }
        let outcome = NotificationPlanner.plan(for: plans, now: now, calendar: calendar)
        XCTAssertEqual(outcome.notifications.count, 20)
        XCTAssertEqual(outcome.droppedDoseReminders, 0)
        XCTAssertNil(outcome.plannedThrough)
    }

    // MARK: - What a replan leaves in Notification Center

    func testADatedReminderThatRangStaysWhileItsDoseIsUnlogged() {
        let course = plan(courseID, name: "Course", schedules: [schedule(8 * 60, start: at(1), end: at(12))])
        let rang = NotificationPlanner.plan(for: [course], now: at(10, 8, 10), calendar: calendar)
        XCTAssertFalse(rang.notifications.contains { $0.identifier == "meds.group.dose.date.20260910.0800" }, "its moment has passed")
        XCTAssertEqual(NotificationService.deliveredIdentifiersToRemove(delivered: ["meds.group.dose.date.20260910.0800"], outcome: rang), [],
                       "a Taken on another reminder replans, and must not sweep this one away")

        let logged = plan(courseID, name: "Course", schedules: [schedule(8 * 60, start: at(1), end: at(12), logged: [at(10)])])
        let answered = NotificationPlanner.plan(for: [logged], now: at(10, 8, 10), calendar: calendar)
        XCTAssertEqual(NotificationService.deliveredIdentifiersToRemove(delivered: ["meds.group.dose.date.20260910.0800"], outcome: answered),
                       ["meds.group.dose.date.20260910.0800"])

        let dayLater = NotificationPlanner.plan(for: [course], now: at(11, 8, 10), calendar: calendar)
        XCTAssertEqual(NotificationService.deliveredIdentifiersToRemove(delivered: ["meds.group.dose.date.20260910.0800"], outcome: dayLater),
                       ["meds.group.dose.date.20260910.0800"], "Today and the missed-dose list ask about it after a day")
    }

    /// The morning a course's end comes within the week, its reminder rings
    /// under the repeating name planned the day before. A replan that
    /// afternoon (a Taken on another reminder's lock-screen button) plans the
    /// course dated, and must not take the rung reminder with it.
    func testAReminderThatRangBeforeItsScheduleTurnedDatedStaysWhileUnlogged() {
        let daily = "meds.group.dose.daily.1400"
        func course(end: Date?, mask: Int = 0b1111111, logged: Set<Date> = []) -> MedicationNotificationPlan {
            plan(courseID, name: "Course", schedules: [schedule(14 * 60, mask: mask, start: at(1), end: end, logged: logged)])
        }
        let dayBefore = NotificationPlanner.plan(for: [course(end: at(16))], now: at(9, 15), calendar: calendar)
        XCTAssertTrue(dayBefore.notifications.contains { $0.identifier == daily }, "steady the day before")

        let afternoon = NotificationPlanner.plan(for: [course(end: at(16))], now: at(10, 15), calendar: calendar)
        XCTAssertFalse(afternoon.notifications.contains { $0.identifier == daily }, "dated from this morning")
        XCTAssertEqual(NotificationService.deliveredIdentifiersToRemove(delivered: [daily], outcome: afternoon), [])

        let endSetAfterItRang = NotificationPlanner.plan(for: [course(end: at(10))], now: at(10, 15), calendar: calendar)
        XCTAssertEqual(NotificationService.deliveredIdentifiersToRemove(delivered: [daily], outcome: endSetAfterItRang), [],
                       "an end set today, after today's reminder rang")

        let answered = NotificationPlanner.plan(for: [course(end: at(16), logged: [at(10)])], now: at(10, 15), calendar: calendar)
        XCTAssertEqual(NotificationService.deliveredIdentifiersToRemove(delivered: [daily], outcome: answered), [daily])

        // Thursdays and Mondays: it rang as Thursday's weekly request.
        let weekly = NotificationPlanner.plan(for: [course(end: at(16), mask: (1 << 4) | (1 << 1))], now: at(10, 15), calendar: calendar)
        XCTAssertEqual(
            NotificationService.deliveredIdentifiersToRemove(
                delivered: ["meds.group.dose.weekly.5.1400", "meds.group.dose.weekly.2.1400"],
                outcome: weekly
            ),
            ["meds.group.dose.weekly.2.1400"],
            "Monday's is not a dose from yesterday or today"
        )
    }

    // MARK: - Today's notice

    func testTheNoticeNamesADayFromTodayThroughThreeDaysAhead() {
        XCTAssertEqual(NotificationHealth.noticeDay(plannedThrough: at(10), now: now, calendar: calendar), at(10))
        XCTAssertEqual(NotificationHealth.noticeDay(plannedThrough: at(13), now: now, calendar: calendar), at(13))
        XCTAssertNil(NotificationHealth.noticeDay(plannedThrough: at(14), now: now, calendar: calendar))
        XCTAssertNil(NotificationHealth.noticeDay(plannedThrough: at(9), now: now, calendar: calendar), "the banner already says reminders weren't set")
        XCTAssertNil(NotificationHealth.noticeDay(plannedThrough: nil, now: now, calendar: calendar))
    }

    // MARK: - From the store

    @MainActor
    func testTheBuilderCarriesDatesAndLoggedDays() throws {
        let medication = Medication(name: "Course", createdAt: at(1))
        let schedule = DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, startDate: at(1, 9), endDate: at(12))
        let taken = DoseEvent(medicationID: medication.id, scheduleID: schedule.id, scheduledAt: at(9, 8), recordedAt: at(9, 8, 5),
                              doseQuantity: 1, status: .taken)
        let other = DoseEvent(medicationID: UUID(), scheduleID: schedule.id, scheduledAt: at(10, 8), recordedAt: at(10, 8), doseQuantity: 1, status: .taken)
        let built = NotificationPlanBuilder.make(medication: medication, schedules: [schedule], inventoryEvents: [],
                                                 doseEvents: [taken, other], now: now, calendar: calendar)
        let copy = try XCTUnwrap(built.schedules.first)
        XCTAssertEqual(copy.startDate, at(1, 9))
        XCTAssertEqual(copy.endDate, at(12))
        XCTAssertEqual(copy.loggedDays, [at(9)], "yesterday's dose; another medication's log is not this one's")
    }

    // MARK: - Helpers

    private func schedule(
        _ minutes: Int,
        mask: Int = 0b1111111,
        start: Date = .distantPast,
        end: Date? = nil,
        logged: Set<Date> = []
    ) -> ScheduleNotificationPlan {
        ScheduleNotificationPlan(
            id: UUID(),
            minutesAfterMidnight: minutes,
            doseQuantity: 1,
            weekdayMask: mask,
            startDate: start,
            endDate: end,
            loggedDays: logged
        )
    }

    private func plan(
        _ id: UUID,
        name: String,
        detailed: Bool = false,
        schedules: [ScheduleNotificationPlan]
    ) -> MedicationNotificationPlan {
        MedicationNotificationPlan(
            medicationID: id,
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
