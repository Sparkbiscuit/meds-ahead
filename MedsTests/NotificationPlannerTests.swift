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

    /// No refills left means a prescriber has to be reached before a pharmacy can do
    /// anything, so the warning comes earlier and says which call to make.
    func testLastRefillWarnsEarlierAndNamesTheRealTask() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        let depletion = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 8)))
        let plan = makePlan(
            doseRemindersEnabled: false,
            detailedNotifications: true,
            refillLeadDays: 7,
            refillsRemaining: 0,
            depletionDate: depletion
        )
        let refill = try XCTUnwrap(NotificationPlanner.notifications(for: plan, now: now, calendar: calendar).first)

        guard case let .date(date) = refill.trigger else {
            return XCTFail("Expected a calendar date trigger")
        }
        XCTAssertEqual(calendar.component(.day, from: date), 10, "ten days of lead, not the seven a refillable one gets")
        XCTAssertTrue(refill.title.contains("Renew"))
        XCTAssertTrue(refill.body.contains("no refills".lowercased()) || refill.body.contains("No refills"))
    }

    func testAChosenLeadTimeLongerThanThePrescriberDefaultIsKept() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        let depletion = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: 8)))
        let plan = makePlan(
            doseRemindersEnabled: false,
            refillLeadDays: 21,
            refillsRemaining: 0,
            depletionDate: depletion
        )
        let refill = try XCTUnwrap(NotificationPlanner.notifications(for: plan, now: now, calendar: calendar).first)

        guard case let .date(date) = refill.trigger else {
            return XCTFail("Expected a calendar date trigger")
        }
        XCTAssertEqual(calendar.component(.day, from: date), 9)
    }

    func testRefillsRemainingStaysQuietWhenItWasNeverEntered() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        let depletion = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 8)))
        let plan = makePlan(
            doseRemindersEnabled: false,
            detailedNotifications: true,
            refillLeadDays: 7,
            refillsRemaining: nil,
            depletionDate: depletion
        )
        let refill = try XCTUnwrap(NotificationPlanner.notifications(for: plan, now: now, calendar: calendar).first)

        guard case let .date(date) = refill.trigger else {
            return XCTFail("Expected a calendar date trigger")
        }
        XCTAssertEqual(calendar.component(.day, from: date), 13)
        XCTAssertTrue(refill.title.contains("Plan a refill"))
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

    /// A refill already requested or ready is the answer to the warning, so the
    /// warning stops; the forecast itself does not change. What remains is the
    /// one question for the morning the refill stops answering for the supply.
    func testARefillInProgressSilencesTheLowSupplyWarning() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        let depletion = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 8)))
        let warned = makePlan(doseRemindersEnabled: false, refillLeadDays: 7, depletionDate: depletion)
        XCTAssertEqual(NotificationPlanner.notifications(for: warned, now: now, calendar: calendar).count, 1)

        let requested = makePlan(doseRemindersEnabled: false, refillLeadDays: 7, depletionDate: depletion, refillInProgress: true)
        let notifications = NotificationPlanner.notifications(for: requested, now: now, calendar: calendar)
        XCTAssertTrue(notifications.filter { $0.kind == .refill }.isEmpty)
        XCTAssertEqual(notifications.map(\.kind), [.refillCheck], "two days before it runs out, with no date to go on")
    }

    /// Requested on the 10th, and not in hand: the morning of the 12th asks, and
    /// from then on the warning is back. A refill check whose morning has gone
    /// is not asked again.
    func testALateRefillIsCheckedOnTheMorningThePauseEnds() throws {
        let requestedOn = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12)))
        let depletion = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: 8)))
        let plan = makePlan(displayName: "Furosemide", doseRemindersEnabled: false, detailedNotifications: false, refillLeadDays: 7,
                            depletionDate: depletion, refillInProgress: true, refillStatusDate: requestedOn)

        let dayAfter = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 12)))
        let lapse = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 9)))
        let check = try XCTUnwrap(NotificationPlanner.notifications(for: plan, now: dayAfter, calendar: calendar).first { $0.kind == .refillCheck })
        XCTAssertEqual(check.trigger, .date(lapse))
        XCTAssertEqual(check.identifier, "meds.AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.refillcheck.20260812")
        XCTAssertEqual(check.title, "Is the refill in hand?")
        XCTAssertFalse(check.title.contains("Furosemide") || check.body.contains("Furosemide"), "private copy names nothing")

        let named = makePlan(displayName: "Furosemide", doseRemindersEnabled: false, detailedNotifications: true, refillLeadDays: 7,
                             depletionDate: depletion, refillInProgress: true, refillStatusDate: requestedOn)
        let detailed = try XCTUnwrap(NotificationPlanner.notifications(for: named, now: dayAfter, calendar: calendar).first { $0.kind == .refillCheck })
        XCTAssertTrue(detailed.title.contains("Furosemide"))
        XCTAssertTrue(detailed.body.contains("Aug 30"), detailed.body)

        let threeDaysLate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 12)))
        let outcome = NotificationPlanner.plan(for: [plan], now: threeDaysLate, calendar: calendar)
        XCTAssertFalse(outcome.notifications.contains { $0.kind == .refillCheck }, "its morning has passed")
        XCTAssertTrue(outcome.retains(check.identifier), "the question stands until the refill is added")
        XCTAssertEqual(outcome.notifications.filter { $0.kind == .refill }.count, 1,
                       "the pause has ended, so the low-supply warning on the 23rd is planned again")
    }

    /// A refill requested well before supply runs low used to cancel the one
    /// warning for good, even if it never came.
    func testARefillThatNeverComesDoesNotCancelTheWarning() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        let depletion = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: 8)))
        let plan = makePlan(doseRemindersEnabled: false, refillLeadDays: 7, depletionDate: depletion, refillInProgress: true, refillStatusDate: now)
        let leadMorning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 23, hour: 9)))
        let notifications = NotificationPlanner.notifications(for: plan, now: now, calendar: calendar)

        XCTAssertEqual(notifications.map(\.kind), [.refillCheck, .refill])
        XCTAssertEqual(notifications.last?.trigger, .date(leadMorning))
    }

    func testARefillCheckAndAWarningOnTheSameMorningAreOneAlert() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        let depletion = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 8)))
        let plan = makePlan(doseRemindersEnabled: false, refillLeadDays: 2, depletionDate: depletion, refillInProgress: true)

        XCTAssertEqual(NotificationPlanner.notifications(for: plan, now: now, calendar: calendar).map(\.kind), [.refillCheck])
    }

    /// Expected on the 20th, with the supply gone on the 10th: however punctual
    /// the pharmacy, that is days without medication, so the warning is not
    /// held back for it.
    func testARefillDueAfterTheSupplyRunsOutDoesNotQuietTheWarning() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        let depletion = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 8)))
        let expected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20)))
        let leadMorning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 9)))
        let checkMorning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 9)))
        let plan = makePlan(doseRemindersEnabled: false, refillLeadDays: 7, depletionDate: depletion, refillInProgress: true, refillStatusDate: expected)
        let notifications = NotificationPlanner.notifications(for: plan, now: now, calendar: calendar)

        XCTAssertEqual(notifications.map(\.kind), [.refill, .refillCheck])
        XCTAssertEqual(notifications.map(\.trigger), [.date(leadMorning), .date(checkMorning)])
    }

    // MARK: - What a replan leaves in Notification Center

    func testAPassedRefillAlertStaysOnlyWhileItIsStillTrue() throws {
        let before = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        let after = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 12)))
        let depletion = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 8)))
        let plan = makePlan(refillLeadDays: 7, depletionDate: depletion)
        let delivered = try XCTUnwrap(NotificationPlanner.notifications(for: plan, now: before, calendar: calendar).first { $0.kind == .refill }).identifier

        func removed(_ plans: [MedicationNotificationPlan]) -> [String] {
            let outcome = NotificationPlanner.plan(for: plans, now: after, calendar: calendar)
            XCTAssertFalse(outcome.retains("meds.group.dose.daily.0830"), "dose reminders are never retained")
            return NotificationService.deliveredIdentifiersToRemove(delivered: [delivered], outcome: outcome)
        }

        XCTAssertEqual(removed([plan]), [], "same run-out day, still low: the only warning stays")

        let refilled = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 8)))
        XCTAssertEqual(removed([makePlan(refillLeadDays: 7, depletionDate: refilled)]), [delivered], "a refill moved the run-out day")
        XCTAssertEqual(removed([makePlan(isArchived: true, refillLeadDays: 7, depletionDate: depletion)]), [delivered])
        XCTAssertEqual(removed([makePlan(refillRemindersEnabled: false, refillLeadDays: 7, depletionDate: depletion)]), [delivered])
        XCTAssertEqual(removed([makePlan(refillLeadDays: 7, depletionDate: depletion, refillInProgress: true, refillStatusDate: after)]), [delivered],
                       "a refill on its way answers the warning")
    }

    func testAPassedExpirationAlertStaysWhileThePackageIsTheSame() throws {
        let before = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        let after = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 12)))
        let expiration = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 30)))
        let delivered = try XCTUnwrap(NotificationPlanner.notifications(for: makePlan(doseRemindersEnabled: false, expirationDate: expiration), now: before, calendar: calendar).first).identifier

        let same = NotificationPlanner.plan(for: [makePlan(doseRemindersEnabled: false, expirationDate: expiration)], now: after, calendar: calendar)
        XCTAssertTrue(same.retains(delivered))

        let newPackage = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 8, day: 30)))
        let replaced = NotificationPlanner.plan(for: [makePlan(doseRemindersEnabled: false, expirationDate: newPackage)], now: after, calendar: calendar)
        XCTAssertEqual(NotificationService.deliveredIdentifiersToRemove(delivered: [delivered], outcome: replaced), [delivered])
    }

    func testRequestsNoLongerPlannedAreStillCancelledAndOldDoseRemindersCleared() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        let outcome = NotificationPlanner.plan(for: [makePlan(refillRemindersEnabled: false)], now: now, calendar: calendar)
        let planned = Set(outcome.notifications.map(\.identifier))
        XCTAssertEqual(planned, ["meds.group.dose.daily.0830"])

        let moved = "meds.group.dose.daily.0700"
        XCTAssertEqual(NotificationService.pendingIdentifiersToRemove(pending: [moved, "meds.group.dose.daily.0830", "other.app"], planned: planned), [moved])
        XCTAssertEqual(NotificationService.deliveredIdentifiersToRemove(delivered: [moved, "meds.group.dose.daily.0830"], outcome: outcome), [moved])
    }

    /// The run-out day in a refill alert's identifier moves a day after a
    /// Skip, and every day once nothing is left. A Skip on the Lock Screen, or
    /// a replan the day after running out, used to take the only warning out
    /// of Notification Center. While the morning dose is due and not yet
    /// logged the day holds still, so opening the app from the dose reminder
    /// keeps the very identifier that was delivered.
    @MainActor
    func testADeliveredWarningOutlivesTheRunOutDayMoving() throws {
        func at(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute))!
        }
        let medication = Medication(name: "Furosemide", refillLeadDays: 7)
        let schedule = DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, startDate: at(1, 0))
        let counted = [InventoryEvent(medicationID: medication.id, date: at(1, 0), delta: 10, reason: .openingCount)]
        func logged(through last: Int, _ status: DoseEventStatus = .taken) -> [DoseEvent] {
            (1...last).map {
                DoseEvent(medicationID: medication.id, scheduleID: schedule.id, scheduledAt: at($0, 8), recordedAt: at($0, 8),
                          doseQuantity: 1, status: $0 == last ? status : .taken)
            }
        }
        func plan(at now: Date, doses: [DoseEvent], inventory: [InventoryEvent] = counted) -> MedicationNotificationPlan {
            NotificationPlanBuilder.make(medication: medication, schedules: [schedule], inventoryEvents: inventory,
                                         doseEvents: doses, now: now, calendar: calendar)
        }
        func outcome(at now: Date, doses: [DoseEvent], inventory: [InventoryEvent] = counted) -> NotificationPlanOutcome {
            NotificationPlanner.plan(for: [plan(at: now, doses: doses, inventory: inventory)], now: now, calendar: calendar)
        }
        let delivered = try XCTUnwrap(outcome(at: at(1), doses: logged(through: 1)).notifications.first { $0.kind == .refill }).identifier
        let deliveredRunOut = try XCTUnwrap(plan(at: at(1), doses: logged(through: 1)).depletionDate)

        XCTAssertEqual(plan(at: at(6, 8, 5), doses: logged(through: 5)).depletionDate, deliveredRunOut,
                       "the run-out day holds still while the morning dose is due and not yet logged")
        XCTAssertTrue(outcome(at: at(6, 8, 5), doses: logged(through: 5)).retains(delivered),
                      "opened from the dose reminder before logging it, the identifier is unchanged and kept")

        let skipped = (at: at(6, 8, 5), doses: logged(through: 6, .skipped))
        XCTAssertNotEqual(plan(at: skipped.at, doses: skipped.doses).depletionDate, deliveredRunOut, "a skip moves the run-out day")
        XCTAssertEqual(NotificationService.deliveredIdentifiersToRemove(delivered: [delivered], outcome: outcome(at: skipped.at, doses: skipped.doses)), [],
                       "skipped on the Lock Screen")
        XCTAssertNotEqual(plan(at: at(11), doses: logged(through: 10)).depletionDate, deliveredRunOut, "at zero the run-out day is every day")
        XCTAssertEqual(NotificationService.deliveredIdentifiersToRemove(delivered: [delivered], outcome: outcome(at: at(11), doses: logged(through: 10))), [],
                       "the day after it ran out, the warning is truer than ever")

        let refilled = counted + [InventoryEvent(medicationID: medication.id, date: at(6, 9), delta: 30, reason: .refill)]
        XCTAssertEqual(NotificationService.deliveredIdentifiersToRemove(delivered: [delivered], outcome: outcome(at: at(6, 9, 5), doses: logged(through: 6), inventory: refilled)),
                       [delivered], "a refill added answers it")
    }

    /// A refill check asks until the refill is added or cleared, whichever
    /// morning it was asked for; it is not a refill alert, nor one a refill
    /// alert keeps.
    func testADeliveredRefillCheckStaysUntilTheRefillIsAddedOrCleared() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 12)))
        let depletion = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 8)))
        let requestedOn = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        let check = "meds.AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.refillcheck.20260811"
        let inProgress = NotificationPlanner.plan(for: [makePlan(doseRemindersEnabled: false, refillLeadDays: 7, depletionDate: depletion,
                                                                 refillInProgress: true, refillStatusDate: requestedOn)], now: now, calendar: calendar)
        XCTAssertEqual(NotificationService.deliveredIdentifiersToRemove(delivered: [check], outcome: inProgress), [],
                       "asked for a morning the check no longer falls on, and still unanswered")

        let cleared = NotificationPlanner.plan(for: [makePlan(doseRemindersEnabled: false, refillLeadDays: 7, depletionDate: depletion)], now: now, calendar: calendar)
        XCTAssertTrue(cleared.retainedPrefixes.contains("meds.AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.refill."), "still low, so a refill alert would stay")
        XCTAssertEqual(NotificationService.deliveredIdentifiersToRemove(delivered: [check], outcome: cleared), [check],
                       "but the question went with the refill")
    }

    /// A count needed carries today as its run-out date, where the assumed
    /// doses ran out. No refill alert or refill check is written from it, and
    /// none quotes it; one already delivered stays, since the supply still
    /// needs someone to act.
    @MainActor
    func testACountNeededWritesNoRefillCopyAndKeepsTheWarningGiven() throws {
        func at(_ day: Int, _ hour: Int = 12) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
        }
        let medication = Medication(name: "Furosemide", refillLeadDays: 7, detailedNotifications: true, createdAt: at(1, 7),
                                    refillStatus: .requested, refillStatusDate: at(8))
        let schedules = [8, 20].map { DoseSchedule(medicationID: medication.id, minutesAfterMidnight: $0 * 60, startDate: at(1, 7)) }
        let counted = [InventoryEvent(medicationID: medication.id, date: at(1, 7), delta: 6, reason: .openingCount)]
        let plan = NotificationPlanBuilder.make(medication: medication, schedules: schedules, inventoryEvents: counted,
                                                doseEvents: [], now: at(6, 7), calendar: calendar)
        XCTAssertTrue(plan.needsCount)

        let outcome = NotificationPlanner.plan(for: [plan], now: at(6, 7), calendar: calendar)
        XCTAssertFalse(outcome.notifications.contains { $0.kind == .refill || $0.kind == .refillCheck }, "\(outcome.notifications.map(\.kind))")
        // What it does get is the weekly question, the morning its count is
        // a week old.
        let check = try XCTUnwrap(outcome.notifications.first { $0.kind == .countCheck })
        XCTAssertEqual(check.trigger, .date(at(8, 10)))
        XCTAssertTrue(outcome.retains("meds.\(medication.id.uuidString).refill.08012026"), "a warning already given stays")
        XCTAssertTrue(outcome.retains("meds.\(medication.id.uuidString).refillcheck.20260810"), "and so does a question already asked")

        // However the forecast's date falls, nothing is built from it.
        let ahead = makePlan(doseRemindersEnabled: false, detailedNotifications: true, refillLeadDays: 7, depletionDate: at(30, 8),
                             refillInProgress: true, refillStatusDate: at(8), needsCount: true)
        let planned = NotificationPlanner.plan(for: [ahead], now: at(6, 7), calendar: calendar)
        XCTAssertTrue(planned.notifications.isEmpty, "\(planned.notifications.map(\.body))")
        XCTAssertTrue(planned.retainedPrefixes.contains("meds.AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.refill."))
    }

    func testAPackageExpirationIsAnnouncedAWeekAhead() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        let expiration = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 30)))
        let plan = makePlan(doseRemindersEnabled: false, expirationDate: expiration)
        let reminder = try XCTUnwrap(NotificationPlanner.notifications(for: plan, now: now, calendar: calendar).first)

        XCTAssertEqual(reminder.kind, .expiration)
        guard case let .date(date) = reminder.trigger else { return XCTFail("Expected a date trigger") }
        XCTAssertEqual(calendar.component(.day, from: date), 23)
        XCTAssertEqual(calendar.component(.hour, from: date), 9)
        XCTAssertEqual(reminder.title, "Package expiring soon")
        XCTAssertFalse(reminder.body.contains("Example"), "private copy names nothing")

        let detailed = makePlan(displayName: "Tacrolimus", doseRemindersEnabled: false, detailedNotifications: true, expirationDate: expiration)
        let named = try XCTUnwrap(NotificationPlanner.notifications(for: detailed, now: now, calendar: calendar).first)
        XCTAssertEqual(named.title, "Tacrolimus expires soon")
        XCTAssertTrue(named.body.contains("Aug 30"), named.body)

        let soon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 5)))
        XCTAssertTrue(NotificationPlanner.notifications(for: makePlan(doseRemindersEnabled: false, expirationDate: soon), now: now, calendar: calendar).isEmpty,
                      "the lead moment has passed; the detail screen already says expired or expiring")
        XCTAssertTrue(NotificationPlanner.notifications(for: makePlan(doseRemindersEnabled: false, refillRemindersEnabled: false, expirationDate: expiration), now: now, calendar: calendar).isEmpty,
                      "under the refill toggle")
    }

    func testTheRefillBodyNamesThePharmacyAndTheRxNumber() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        let depletion = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 8)))
        let detailed = makePlan(doseRemindersEnabled: false, detailedNotifications: true, depletionDate: depletion,
                                pharmacyName: "Walgreens #04821", rxNumber: "8842197")
        let refill = try XCTUnwrap(NotificationPlanner.notifications(for: detailed, now: now, calendar: calendar).first)
        XCTAssertTrue(refill.body.contains("Call Walgreens #04821 with Rx 8842197."), refill.body)

        let renewal = makePlan(doseRemindersEnabled: false, detailedNotifications: true, refillsRemaining: 0, depletionDate: depletion,
                               pharmacyName: "Walgreens #04821", rxNumber: "8842197")
        let renew = try XCTUnwrap(NotificationPlanner.notifications(for: renewal, now: now, calendar: calendar).first)
        XCTAssertFalse(renew.body.contains("Call Walgreens"), "no refills left means the prescriber, not the pharmacy")

        let quiet = makePlan(doseRemindersEnabled: false, depletionDate: depletion, pharmacyName: "Walgreens #04821", rxNumber: "8842197")
        let private_ = try XCTUnwrap(NotificationPlanner.notifications(for: quiet, now: now, calendar: calendar).first)
        XCTAssertFalse(private_.body.contains("Walgreens"))
        XCTAssertFalse(private_.body.contains("8842197"))
    }

    func testUnknownForecastDoesNotCreateRefillNotification() {
        let plan = makePlan(doseRemindersEnabled: false, depletionDate: nil)
        XCTAssertTrue(NotificationPlanner.notifications(for: plan, calendar: calendar).isEmpty)
    }

    func testArchivedMedicationCreatesNoNotifications() {
        let plan = makePlan(isArchived: true)
        XCTAssertTrue(NotificationPlanner.notifications(for: plan, calendar: calendar).isEmpty)
    }

    func testDoseRemindersOutrankRefillAlertsUnderThePendingRequestCap() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        // 58 distinct Monday-only slots, plus refill alerts for six medications
        // with staggered depletion dates: 64 wanted requests against a cap of 60.
        var nearestRefillIDs: [UUID] = []
        var plans: [MedicationNotificationPlan] = []
        for index in 0..<58 {
            let medicationID = UUID()
            let hasRefill = index < 6
            if hasRefill, index < 2 { nearestRefillIDs.append(medicationID) }
            plans.append(makePlan(
                medicationID: medicationID,
                scheduleID: UUID(),
                refillRemindersEnabled: hasRefill,
                refillLeadDays: 1,
                depletionDate: hasRefill ? calendar.date(byAdding: .day, value: 10 + index, to: now) : nil,
                weekdayMask: 1 << 1,
                minutesAfterMidnight: 6 * 60 + index
            ))
        }

        let notifications = NotificationPlanner.notifications(for: plans, now: now, calendar: calendar)

        XCTAssertEqual(notifications.count, NotificationPlanner.maximumScheduledRequests)
        XCTAssertEqual(notifications.filter { $0.kind == .dose }.count, 58)
        let keptRefills = notifications.filter { $0.kind == .refill }
        XCTAssertEqual(keptRefills.count, 2)
        XCTAssertEqual(Set(keptRefills.compactMap(\.medicationID)), Set(nearestRefillIDs))
    }

    func testDoseRemindersPastTheCapAreReportedNotDroppedQuietly() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        // Eleven times, each Monday to Saturday: no time is the same on all seven
        // weekdays, so none collapses into a daily request, and 66 weekly
        // requests are wanted against a cap of 60.
        let plans = (0..<11).map { index in
            makePlan(
                medicationID: UUID(),
                scheduleID: UUID(),
                refillRemindersEnabled: false,
                depletionDate: nil,
                weekdayMask: 0b1111110,
                minutesAfterMidnight: 6 * 60 + index * 30
            )
        }

        let outcome = NotificationPlanner.plan(for: plans, now: now, calendar: calendar)

        XCTAssertEqual(outcome.notifications.count, NotificationPlanner.maximumScheduledRequests)
        XCTAssertTrue(outcome.notifications.allSatisfy { $0.kind == .dose })
        XCTAssertEqual(outcome.droppedDoseReminders, 6)
        XCTAssertEqual(NotificationPlanner.plan(for: Array(plans.prefix(8)), now: now, calendar: calendar).droppedDoseReminders, 0)
    }

    func testTypicalRegimenIsNotTrimmedByTheCap() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        let depletion = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 20)))
        let plans = (0..<8).map { index in
            makePlan(
                medicationID: UUID(),
                scheduleID: UUID(),
                depletionDate: depletion,
                minutesAfterMidnight: 7 * 60 + index * 90
            )
        }

        let notifications = NotificationPlanner.notifications(for: plans, now: now, calendar: calendar)

        XCTAssertEqual(notifications.filter { $0.kind == .dose }.count, 8)
        XCTAssertEqual(notifications.filter { $0.kind == .refill }.count, 8)
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
        refillsRemaining: Int? = nil,
        depletionDate: Date? = nil,
        weekdayMask: Int = 0b1111111,
        minutesAfterMidnight: Int = 8 * 60 + 30,
        refillInProgress: Bool = false,
        expirationDate: Date? = nil,
        pharmacyName: String = "",
        rxNumber: String = "",
        refillStatusDate: Date? = nil,
        onHand: Bool = true,
        needsCount: Bool = false
    ) -> MedicationNotificationPlan {
        MedicationNotificationPlan(
            medicationID: medicationID,
            displayName: displayName,
            form: .tablet,
            isAsNeeded: false,
            isArchived: isArchived,
            doseRemindersEnabled: doseRemindersEnabled,
            refillRemindersEnabled: refillRemindersEnabled,
            detailedNotifications: detailedNotifications,
            refillLeadDays: refillLeadDays,
            refillsRemaining: refillsRemaining,
            depletionDate: depletionDate,
            schedules: [
                ScheduleNotificationPlan(
                    id: scheduleID,
                    minutesAfterMidnight: minutesAfterMidnight,
                    doseQuantity: 1,
                    weekdayMask: weekdayMask
                )
            ],
            refillInProgress: refillInProgress,
            expirationDate: expirationDate,
            pharmacyName: pharmacyName,
            rxNumber: rxNumber,
            refillStatusDate: refillStatusDate,
            onHand: onHand,
            needsCount: needsCount
        )
    }
}
