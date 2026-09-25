import XCTest
@testable import Meds

/// The weekly count check, in GMT, in September 2026. The 1st is a Tuesday.
final class CountCheckPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func candidate(
        _ name: String,
        id: UUID = UUID(),
        eligible: Bool = true,
        days: Int? = 20,
        needsCount: Bool = false,
        counted: Date? = nil
    ) -> CountCheckPolicy.Candidate {
        CountCheckPolicy.Candidate(medicationID: id, displayName: name, isEligible: eligible, daysRemaining: days,
                                   needsCount: needsCount, lastCountDate: counted)
    }

    // MARK: - Which one

    func testACountNeededComesFirstThenTheSoonestToRunOut() {
        let now = at(20, 8)
        let old = at(1, 15)
        let candidates = [
            candidate("Long", days: 40, counted: old),
            candidate("Soon", days: 5, counted: old),
            candidate("Unknown", days: nil, counted: old),
            candidate("Needs", days: 0, needsCount: true, counted: old)
        ]
        XCTAssertEqual(CountCheckPolicy.target(from: candidates, now: now, calendar: calendar)?.displayName, "Needs")
        XCTAssertEqual(CountCheckPolicy.target(from: Array(candidates.prefix(3)), now: now, calendar: calendar)?.displayName, "Soon")
        XCTAssertEqual(CountCheckPolicy.target(from: [candidates[0], candidates[2]], now: now, calendar: calendar)?.displayName, "Long",
                       "a known date before an unknown one")
    }

    func testOnlyACountAWeekOldOrMoreIsAskedAbout() {
        let now = at(20, 8)
        let candidates = [
            candidate("Soonest but fresh", days: 2, counted: at(15, 9)),
            candidate("Ineligible", eligible: false, days: 1, counted: at(1)),
            candidate("Never counted", days: 1, counted: nil),
            candidate("Stale", days: 30, counted: at(13, 18))
        ]
        XCTAssertEqual(CountCheckPolicy.target(from: candidates, now: now, calendar: calendar)?.displayName, "Stale",
                       "the 13th is a week before the 20th by the calendar")
        XCTAssertNil(CountCheckPolicy.target(from: Array(candidates.prefix(3)), now: now, calendar: calendar))
        XCTAssertFalse(CountCheckPolicy.isDue(candidates[3], now: at(19, 23), calendar: calendar))
    }

    // MARK: - When

    func testTheQuestionComesWeeklyFromTheCountsDay() {
        let counted = candidate("Counted", counted: at(1, 15))
        XCTAssertEqual(CountCheckPolicy.moment(for: counted, after: at(8, 9), calendar: calendar), at(8, 10), "a week after the count, that morning")
        XCTAssertEqual(CountCheckPolicy.moment(for: counted, after: at(8, 10), calendar: calendar), at(15, 10), "once it has passed, a week later")
        XCTAssertEqual(CountCheckPolicy.moment(for: counted, after: at(9, 8), calendar: calendar), at(15, 10), "never the next day")
        XCTAssertEqual(CountCheckPolicy.moment(for: counted, after: at(14, 23), calendar: calendar), at(15, 10))
        XCTAssertEqual(CountCheckPolicy.moment(for: counted, after: at(22, 12), calendar: calendar), at(29, 10))
        XCTAssertEqual(CountCheckPolicy.moment(for: counted, after: at(3), calendar: calendar), at(8, 10))
        XCTAssertNil(CountCheckPolicy.moment(for: candidate("Never"), after: at(3), calendar: calendar))
    }

    /// A week after the last question about any medication, too, and still
    /// on a week from the count.
    func testTheQuestionWaitsAWeekAfterTheLastOneAsked() {
        let counted = candidate("Counted", counted: at(2, 9))
        XCTAssertEqual(CountCheckPolicy.moment(for: counted, after: at(9, 8), calendar: calendar), at(9, 10))
        XCTAssertEqual(CountCheckPolicy.moment(for: counted, after: at(9, 8), lastAsked: at(8, 10), calendar: calendar), at(16, 10),
                       "the 9th is the day after a question about another medication")
        XCTAssertEqual(CountCheckPolicy.moment(for: counted, after: at(9, 8), lastAsked: at(2, 10), calendar: calendar), at(9, 10),
                       "a week after the last one is soon enough")
        XCTAssertEqual(CountCheckPolicy.moment(for: counted, after: at(9, 8), lastAsked: at(9, 10), calendar: calendar), at(16, 10))
        XCTAssertEqual(CountCheckPolicy.moment(for: counted, after: at(20, 12), lastAsked: at(17, 10), calendar: calendar), at(30, 10),
                       "on or after the 24th, a week from the count")
    }

    /// A counted on the 1st and B on the 2nd. On the 8th only A is a week
    /// old, and it is asked about. On the 9th B is too, and runs out sooner:
    /// it waits for a week after the 8th, not for the morning of the 9th.
    func testTwoMedicationsCountedADayApartAreNotAskedAboutOnConsecutiveDays() throws {
        let aID = UUID(), bID = UUID()
        let plans = [
            plan(name: "A", id: aID, check: candidate("A", id: aID, days: 30, counted: at(1, 9))),
            plan(name: "B", id: bID, check: candidate("B", id: bID, days: 5, counted: at(2, 9)))
        ]
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CountCheckPolicyTests.\(UUID().uuidString)"))
        func check(at now: Date) -> PlannedNotification? {
            let outcome = NotificationPlanner.plan(for: plans, now: now, calendar: calendar, options: .stored(in: defaults, now: now))
            CountCheckPolicy.remember(planned: NotificationService.countCheckMoment(in: outcome.notifications), now: now, in: defaults)
            return outcome.notifications.first { $0.kind == .countCheck }
        }

        let first = try XCTUnwrap(check(at: at(8, 8)))
        XCTAssertEqual(first.medicationID, aID)
        XCTAssertEqual(first.trigger, .date(at(8, 10)))
        XCTAssertEqual(check(at: at(8, 9))?.trigger, .date(at(8, 10)), "planned again before it comes: still one question")

        let next = try XCTUnwrap(check(at: at(9, 8)))
        XCTAssertEqual(next.medicationID, bID)
        XCTAssertEqual(next.trigger, .date(at(16, 10)), "a week after A's, on B's own weekly day")
        XCTAssertEqual(CountCheckPolicy.lastAsked(in: defaults, now: at(9, 8)), at(8, 10))
    }

    func testTheLastQuestionIsOnlyAskedOnceItsMomentHasCome() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CountCheckPolicyTests.\(UUID().uuidString)"))
        XCTAssertNil(CountCheckPolicy.lastAsked(in: defaults, now: at(8)))
        XCTAssertNil(NotificationPlanOptions.stored(in: defaults, now: at(8)).lastCountCheck)

        CountCheckPolicy.remember(planned: at(8, 10), now: at(8, 8), in: defaults)
        XCTAssertNil(CountCheckPolicy.lastAsked(in: defaults, now: at(8, 9)), "not yet come, and may still be replaced")
        XCTAssertEqual(CountCheckPolicy.lastAsked(in: defaults, now: at(8, 11)), at(8, 10))
        XCTAssertEqual(NotificationPlanOptions.stored(in: defaults, now: at(8, 11)).lastCountCheck, at(8, 10))

        // Counted after it came: nothing planned now, and the question it asked stays asked.
        CountCheckPolicy.remember(planned: nil, now: at(8, 11), in: defaults)
        XCTAssertEqual(CountCheckPolicy.lastAsked(in: defaults, now: at(9)), at(8, 10))

        // One planned and then replaced before it came was never asked.
        CountCheckPolicy.remember(planned: at(15, 10), now: at(9), in: defaults)
        CountCheckPolicy.remember(planned: nil, now: at(15, 9), in: defaults)
        XCTAssertEqual(CountCheckPolicy.lastAsked(in: defaults, now: at(16)), at(8, 10))

        CountCheckPolicy.remember(planned: at(22, 10), now: at(16), in: defaults)
        XCTAssertEqual(CountCheckPolicy.lastAsked(in: defaults, now: at(22, 11)), at(22, 10), "the newest that has come")
    }

    // MARK: - The reminder

    func testOneCountCheckIsPlannedForTheTarget() throws {
        let soonID = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!
        let plans = [
            plan(name: "Soon", id: soonID, check: candidate("Soon", id: soonID, days: 4, counted: at(1, 15))),
            plan(name: "Later", check: candidate("Later", days: 30, counted: at(2, 9)))
        ]
        let outcome = NotificationPlanner.plan(for: plans, now: at(9, 8), calendar: calendar)
        let checks = outcome.notifications.filter { $0.kind == .countCheck }
        let check = try XCTUnwrap(checks.first)
        XCTAssertEqual(checks.count, 1, "one question a week, not one per medication")
        XCTAssertEqual(check.identifier, "meds.countcheck.CCCCCCCC-0000-0000-0000-000000000003.20260915")
        XCTAssertEqual(check.trigger, .date(at(15, 10)))
        XCTAssertEqual(check.medicationID, soonID)
        XCTAssertEqual(check.title, "Quick count")
        XCTAssertEqual(check.body, "A 20-second count keeps a run-out date honest. Open Meds Ahead to see which medication.")
        XCTAssertFalse(check.title.contains("Soon") || check.body.contains("Soon"), "private copy names nothing")
        XCTAssertFalse(check.supportsDoseQuickActions)

        let namedID = UUID()
        let named = NotificationPlanner.plan(for: [plan(name: "Tacrolimus", id: namedID, detailed: true, check: candidate("Tacrolimus", id: namedID, counted: at(1, 15)))],
                                             now: at(9, 8), calendar: calendar)
        XCTAssertEqual(named.notifications.first { $0.kind == .countCheck }?.title, "Quick count: Tacrolimus")

        let off = NotificationPlanner.plan(for: plans, now: at(9, 8), calendar: calendar,
                                           options: NotificationPlanOptions(weeklyCountCheck: false))
        XCTAssertFalse(off.notifications.contains { $0.kind == .countCheck })
    }

    func testTheSettingIsOnUntilTurnedOff() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CountCheckPolicyTests.\(UUID().uuidString)"))
        XCTAssertTrue(NotificationPlanOptions.stored(in: defaults).weeklyCountCheck)
        defaults.set(false, forKey: NotificationPlanOptions.weeklyCountCheckKey)
        XCTAssertFalse(NotificationPlanOptions.stored(in: defaults).weeklyCountCheck)
        XCTAssertTrue(NotificationPlanOptions().weeklyCountCheck)
    }

    func testACountCheckThatRangStaysUntilTheCount() {
        let id = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!
        let rang = "meds.countcheck.CCCCCCCC-0000-0000-0000-000000000003.20260908"
        func removed(counted: Date, options: NotificationPlanOptions = NotificationPlanOptions()) -> [String] {
            let outcome = NotificationPlanner.plan(for: [plan(name: "Soon", id: id, check: candidate("Soon", id: id, counted: counted))],
                                                   now: at(9, 12), calendar: calendar, options: options)
            return NotificationService.deliveredIdentifiersToRemove(delivered: [rang], outcome: outcome)
        }
        XCTAssertEqual(removed(counted: at(1, 15)), [], "still not counted")
        XCTAssertEqual(removed(counted: at(9, 11)), [rang], "counted this morning")
        XCTAssertEqual(removed(counted: at(1, 15), options: NotificationPlanOptions(weeklyCountCheck: false)), [rang], "turned off")
    }

    func testCountChecksOpenToday() {
        XCTAssertEqual(MedicationNotificationRoute.destination(for: ["notificationKind": "countCheck"]), .today)
        XCTAssertEqual(MedicationNotificationRoute.destination(for: ["notificationKind": "followUp"]), .today)
    }

    // MARK: - From the store

    @MainActor
    func testTheCandidateComesFromTheLedgerAndTheSchedules() {
        let medication = Medication(name: "Tacrolimus", createdAt: at(1))
        let schedule = DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, startDate: at(1))
        let ledger = [
            InventoryEvent(medicationID: medication.id, date: at(1, 9), delta: 60, reason: .openingCount),
            InventoryEvent(medicationID: medication.id, date: at(5, 9), delta: -1, reason: .correction),
            InventoryEvent(medicationID: medication.id, date: at(8, 9), delta: 30, reason: .refill),
            InventoryEvent(medicationID: UUID(), date: at(9, 9), delta: 3, reason: .correction)
        ]
        let forecast = ForecastEngine.forecast(medication: medication, schedules: [schedule], inventoryEvents: ledger, doseEvents: [],
                                               now: at(12, 12), calendar: calendar)
        let made = CountCheckPolicy.candidate(for: medication, schedules: [schedule], inventoryEvents: ledger, forecast: forecast,
                                              now: at(12, 12), calendar: calendar)
        XCTAssertEqual(made.lastCountDate, at(5, 9), "the latest count, not the refill or another medication's")
        XCTAssertTrue(made.isEligible)
        XCTAssertEqual(made.daysRemaining, forecast.daysRemaining)
        XCTAssertEqual(made.displayName, "Tacrolimus")

        func eligible(_ medication: Medication, _ schedules: [DoseSchedule]) -> Bool {
            CountCheckPolicy.candidate(for: medication, schedules: schedules, inventoryEvents: ledger, forecast: forecast,
                                       now: at(12, 12), calendar: calendar).isEligible
        }
        XCTAssertFalse(eligible(Medication(id: medication.id, name: "As needed", isAsNeeded: true), [schedule]))
        XCTAssertFalse(eligible(Medication(id: medication.id, name: "Archived", isArchived: true), [schedule]))
        XCTAssertFalse(eligible(Medication(id: medication.id, name: "Quiet", refillRemindersEnabled: false), [schedule]))
        XCTAssertFalse(eligible(medication, [DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 480, startDate: at(1), endDate: at(11))]),
                       "a course that has ended")
        XCTAssertFalse(eligible(medication, []), "nothing scheduled")

        let planned = NotificationPlanBuilder.make(medication: medication, schedules: [schedule], inventoryEvents: ledger, doseEvents: [],
                                                   now: at(12, 12), calendar: calendar)
        XCTAssertEqual(planned.countCheck, made)
    }

    // MARK: - Helpers

    private func plan(name: String, id: UUID = UUID(), detailed: Bool = false, check: CountCheckPolicy.Candidate) -> MedicationNotificationPlan {
        MedicationNotificationPlan(
            medicationID: id,
            displayName: name,
            form: .tablet,
            isAsNeeded: false,
            isArchived: false,
            doseRemindersEnabled: false,
            refillRemindersEnabled: true,
            detailedNotifications: detailed,
            refillLeadDays: 7,
            refillsRemaining: nil,
            depletionDate: nil,
            schedules: [],
            countCheck: check
        )
    }
}
