import XCTest
@testable import Meds

/// Today's quick count asks about the medication the weekly count check
/// names, or the one a tapped reminder named, in words that say why, until
/// a count is made or Not Now sets it aside for three days; after a count,
/// it rests for the week. In GMT, in September 2026.
final class QuickCountPromptTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private struct Household {
        var medications: [Medication] = []
        var schedules: [DoseSchedule] = []
        var inventory: [InventoryEvent] = []
        var doses: [DoseEvent] = []
    }

    /// A tablet at 08:00 and at 20:00 from the 1st, counted at 07:00 on the 1st.
    @discardableResult
    private func add(_ name: String, count: Double, form: MedicationForm = .tablet, to household: inout Household,
                     configure: (Medication) -> Void = { _ in }) -> Medication {
        let medication = Medication(name: name, form: form, createdAt: at(1, 7))
        configure(medication)
        household.medications.append(medication)
        if !medication.isAsNeeded {
            household.schedules += [8, 20].map {
                DoseSchedule(medicationID: medication.id, minutesAfterMidnight: $0 * 60, doseQuantity: 1, startDate: at(1, 7))
            }
        }
        household.inventory.append(InventoryEvent(medicationID: medication.id, date: at(1, 7), delta: count, reason: .openingCount))
        return medication
    }

    private func prompt(_ household: Household, setAside: [UUID: Date] = [:], tapped: QuickCountPrompt.Tap? = nil, now: Date) -> QuickCountPrompt? {
        QuickCountPrompt.make(
            medications: household.medications,
            schedules: household.schedules,
            inventoryEvents: household.inventory,
            doseEvents: household.doses,
            setAside: setAside,
            tapped: tapped,
            now: now,
            calendar: calendar
        )
    }

    /// The count check the planner would schedule next, as it plans it.
    @MainActor
    private func plannedCountCheck(_ household: Household, now: Date) -> UUID? {
        let plans = NotificationPlanBuilder.makeAll(
            medications: household.medications,
            schedules: household.schedules,
            inventoryEvents: household.inventory,
            doseEvents: household.doses,
            now: now,
            calendar: calendar
        )
        return NotificationPlanner.plan(for: plans, now: now, calendar: calendar)
            .notifications.first { $0.kind == .countCheck }?.medicationID
    }

    @MainActor
    func testTheCardAsksAboutTheMedicationTheReminderNames() throws {
        var household = Household()
        let long = add("Amlodipine", count: 200, to: &household)
        let soon = add("Mycophenolate", count: 60, to: &household)
        add("Ondansetron", count: 30, to: &household) { $0.isAsNeeded = true }
        add("Archived", count: 20, to: &household) { $0.isArchived = true }
        add("Quiet", count: 24, to: &household) { $0.refillRemindersEnabled = false }
        let now = at(9, 7)

        let card = try XCTUnwrap(prompt(household, now: now))
        XCTAssertEqual(card.medicationID, soon.id, "the soonest to run out of those that can be asked about")
        XCTAssertEqual(plannedCountCheck(household, now: now), card.medicationID)
        XCTAssertNotEqual(card.medicationID, long.id)

        let stale = add("Valganciclovir", count: 10, to: &household)
        let first = try XCTUnwrap(prompt(household, now: now))
        XCTAssertEqual(first.medicationID, stale.id, "a count needed comes first")
        XCTAssertTrue(first.needsCount)
        XCTAssertEqual(plannedCountCheck(household, now: now), first.medicationID)
    }

    func testNothingIsAskedUntilTheCountIsAWeekOld() {
        var household = Household()
        add("Mycophenolate", count: 60, to: &household)
        XCTAssertNil(prompt(household, now: at(7, 23)), "six days after the count by the calendar")
        XCTAssertNotNil(prompt(household, now: at(8, 0, 30)))
    }

    /// A count ends the question, and the card rests for the week, as the
    /// reminder does, rather than asking about each medication due in turn.
    func testACountEndsTheQuestionForTheWeek() throws {
        var household = Household()
        let first = add("Mycophenolate", count: 30, to: &household)
        let second = add("Tacrolimus", count: 60, to: &household)
        XCTAssertEqual(try XCTUnwrap(prompt(household, now: at(9, 7))).medicationID, first.id)

        // More in the bottle than on record, so the second runs out sooner.
        household.inventory.append(InventoryEvent(medicationID: first.id, date: at(9, 7), delta: 100, reason: .correction))
        XCTAssertNil(prompt(household, now: at(9, 7, 1)), "the card goes rather than moving on to the next medication due")
        XCTAssertNil(prompt(household, now: at(15, 23)))
        XCTAssertEqual(prompt(household, now: at(16, 0, 30))?.medicationID, second.id, "a week after the count, it asks again")

        household.inventory.append(InventoryEvent(medicationID: second.id, date: at(16, 7), delta: 0, reason: .correction))
        XCTAssertNil(prompt(household, now: at(16, 7, 1)))
        XCTAssertNil(prompt(household, now: at(22, 23)))
        XCTAssertNotNil(prompt(household, now: at(23, 0, 30)))
    }

    /// A count needed is not rested: no low-supply alert can be planned for
    /// it until someone counts.
    func testACountNeededIsAskedEvenInTheWeekOfACount() throws {
        var household = Household()
        let first = add("Dimethyl fumarate", count: 12, to: &household)
        let second = add("Furosemide", count: 28, to: &household)
        let now = at(17, 9)
        XCTAssertEqual(try XCTUnwrap(prompt(household, now: now)).medicationID, first.id)

        household.inventory.append(InventoryEvent(medicationID: first.id, date: now, delta: 8, reason: .correction))
        let next = try XCTUnwrap(prompt(household, now: at(17, 9, 1)))
        XCTAssertEqual(next.medicationID, second.id)
        XCTAssertTrue(next.needsCount)
    }

    /// The count that rests the card is one the check could have asked for:
    /// a medication it asks about, counted once its last count was due.
    func testOnlyACountTheCheckCouldHaveAskedForRestsTheCard() {
        var household = Household()
        let scheduled = add("Mycophenolate", count: 60, to: &household)
        let asNeeded = add("Ondansetron", count: 30, to: &household) { $0.isAsNeeded = true }
        add("Tacrolimus", count: 60, to: &household)
        household.inventory += [
            InventoryEvent(medicationID: asNeeded.id, date: at(9, 7), delta: -2, reason: .correction),
            InventoryEvent(medicationID: scheduled.id, date: at(3, 7), delta: 0, reason: .correction),
            InventoryEvent(medicationID: scheduled.id, date: at(9, 7), delta: 0, reason: .correction)
        ]
        XCTAssertNotNil(prompt(household, now: at(9, 8)), "an as-needed count, and a recount six days after the last, answer nothing")
        let candidates = household.medications.map {
            CountCheckPolicy.candidate(
                for: $0,
                schedules: household.schedules,
                inventoryEvents: household.inventory,
                forecast: ForecastEngine.forecast(medication: $0, schedules: household.schedules, inventoryEvents: household.inventory, doseEvents: [], now: at(9, 8), calendar: calendar),
                now: at(9, 8),
                calendar: calendar
            )
        }
        XCTAssertNil(QuickCountPrompt.lastAnswer(candidates: candidates, inventoryEvents: household.inventory, calendar: calendar))
        household.inventory.append(InventoryEvent(medicationID: scheduled.id, date: at(10, 7), delta: 0, reason: .correction))
        XCTAssertNil(QuickCountPrompt.lastAnswer(candidates: candidates, inventoryEvents: household.inventory, calendar: calendar))
        household.inventory.append(InventoryEvent(medicationID: scheduled.id, date: at(17, 7), delta: 0, reason: .correction))
        XCTAssertEqual(QuickCountPrompt.lastAnswer(candidates: candidates, inventoryEvents: household.inventory, calendar: calendar), at(17, 7), "a week after the last count")
    }

    /// The planner picked one medication when it planned the reminder; by
    /// the time it is tapped the pick can differ. The card names the one the
    /// reminder named, until it is counted.
    func testATappedReminderNamesTheCard() throws {
        var household = Household()
        let first = add("Mycophenolate", count: 30, to: &household)
        let second = add("Tacrolimus", count: 60, to: &household)
        let tap = QuickCountPrompt.Tap(medicationID: second.id, date: at(9, 10))
        XCTAssertEqual(prompt(household, now: at(9, 10))?.medicationID, first.id, "the policy's pick")
        XCTAssertEqual(prompt(household, tapped: tap, now: at(9, 10, 1))?.medicationID, second.id)
        XCTAssertEqual(prompt(household, tapped: tap, now: at(11, 9))?.medicationID, second.id, "until it is counted")

        household.inventory.append(InventoryEvent(medicationID: second.id, date: at(11, 9, 5), delta: 0, reason: .correction))
        XCTAssertNil(prompt(household, tapped: tap, now: at(11, 9, 6)), "counted, the question is answered for the week")

        // A reminder for a medication that isn't due any more names nothing.
        let stale = QuickCountPrompt.Tap(medicationID: first.id, date: at(1, 6))
        XCTAssertNil(prompt(household, tapped: stale, now: at(11, 9, 6)))
    }

    func testTheWordsSayWhatIsAskedAndWhy() {
        let tablets = Medication(name: "Mycophenolate")
        let steady = SupplyForecast(currentSupply: 40, depletionDate: at(29), daysRemaining: 20, confidence: .high, explanation: "")
        let quick = QuickCountPrompt(medication: tablets, forecast: steady)
        XCTAssertEqual(quick.title, "Quick count: Mycophenolate")
        XCTAssertEqual(quick.message, "How many tablets are left? A few seconds of counting keeps the run-out date honest.")
        XCTAssertFalse(quick.needsCount)

        XCTAssertEqual(QuickCountPrompt(medication: Medication(name: "Valganciclovir", form: .capsule), forecast: steady).message,
                       "How many capsules are left? A few seconds of counting keeps the run-out date honest.")
        XCTAssertEqual(QuickCountPrompt(medication: Medication(name: "Nystatin", form: .liquid), forecast: steady).message,
                       "How many mL are left? A few seconds of counting keeps the run-out date honest.")

        let needed = SupplyForecast(currentSupply: 4, depletionDate: at(9), daysRemaining: 0, confidence: .estimated, explanation: "",
                                    assumedDoses: 32, needsCount: true)
        let count = QuickCountPrompt(medication: tablets, forecast: needed)
        XCTAssertEqual(count.title, "Count needed: Mycophenolate")
        XCTAssertEqual(count.message, "32 doses since the last count weren't logged, so only a count can say what's left.")
        XCTAssertTrue(count.needsCount)

        let one = SupplyForecast(currentSupply: 1, depletionDate: at(9), daysRemaining: 0, confidence: .estimated, explanation: "",
                                 assumedDoses: 1, needsCount: true, assumedSinceRefill: true)
        XCTAssertEqual(QuickCountPrompt(medication: tablets, forecast: one).message,
                       "1 dose since the last refill wasn't logged, so only a count can say what's left.")
    }

    func testNotNowSetsOneMedicationAsideForThreeDays() throws {
        var household = Household()
        let first = add("Mycophenolate", count: 30, to: &household)
        let second = add("Tacrolimus", count: 60, to: &household)
        let tapped = at(9, 7)
        let setAside = QuickCountPrompt.settingAside(first.id, at: tapped, in: [:], calendar: calendar)

        XCTAssertNil(prompt(household, setAside: setAside, now: at(9, 8)), "the card is hidden, not moved on to the next medication")
        XCTAssertNil(prompt(household, setAside: setAside, now: at(12, 6, 59)))
        XCTAssertEqual(prompt(household, setAside: setAside, now: at(12, 7))?.medicationID, first.id, "three days later it asks again")

        // Counted since, the question is answered: the card rests for the
        // week, then asks about the second, whatever was set aside for the
        // first.
        household.inventory.append(InventoryEvent(medicationID: first.id, date: at(10, 9), delta: 100, reason: .correction))
        XCTAssertNil(prompt(household, setAside: setAside, now: at(10, 10)))
        XCTAssertEqual(prompt(household, setAside: setAside, now: at(17, 0, 30))?.medicationID, second.id)
    }

    /// Only a tapped reminder brings a set-aside card back: one that was
    /// planned for later that morning, and perhaps never delivered, does not.
    func testOnlyATappedReminderBringsASetAsideCardBack() {
        var household = Household()
        let first = add("Mycophenolate", count: 30, to: &household)
        let second = add("Tacrolimus", count: 60, to: &household)
        let setAside = QuickCountPrompt.settingAside(first.id, at: at(8, 8, 5), in: [:], calendar: calendar)
        XCTAssertNil(prompt(household, setAside: setAside, now: at(8, 10, 1)), "the 10:00 check passing is not a tap")

        let before = QuickCountPrompt.Tap(medicationID: first.id, date: at(8, 8))
        XCTAssertNil(prompt(household, setAside: setAside, tapped: before, now: at(8, 10, 1)), "a tap before Not Now")
        let after = QuickCountPrompt.Tap(medicationID: first.id, date: at(8, 10))
        XCTAssertEqual(prompt(household, setAside: setAside, tapped: after, now: at(8, 10, 1))?.medicationID, first.id)

        let other = QuickCountPrompt.Tap(medicationID: second.id, date: at(8, 10))
        XCTAssertEqual(prompt(household, setAside: setAside, tapped: other, now: at(8, 10, 1))?.medicationID, second.id,
                       "a reminder about another medication asks about that one")
    }

    /// Tapping a count check keeps the medication it named for Today; any
    /// other reminder leaves it be.
    func testATappedCountCheckIsKeptForToday() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "QuickCountPromptTests"))
        defaults.removePersistentDomain(forName: "QuickCountPromptTests")
        defer { defaults.removePersistentDomain(forName: "QuickCountPromptTests") }
        let medicationID = UUID()

        XCTAssertEqual(MedicationNotificationRoute.follow(["notificationKind": "dose", "medicationID": medicationID.uuidString], at: at(9, 8), defaults: defaults), .today)
        XCTAssertNil(defaults.data(forKey: QuickCountPrompt.tapKey))
        XCTAssertEqual(MedicationNotificationRoute.follow(["notificationKind": "refill", "medicationID": medicationID.uuidString], at: at(9, 9), defaults: defaults), .supply)
        XCTAssertNil(defaults.data(forKey: QuickCountPrompt.tapKey))

        XCTAssertEqual(MedicationNotificationRoute.follow(["notificationKind": "countCheck", "medicationID": medicationID.uuidString], at: at(9, 10), defaults: defaults), .today)
        let stored = try XCTUnwrap(defaults.data(forKey: QuickCountPrompt.tapKey))
        XCTAssertEqual(QuickCountPrompt.decodeTap(stored), QuickCountPrompt.Tap(medicationID: medicationID, date: at(9, 10)))
        XCTAssertNil(QuickCountPrompt.decodeTap(Data()))
    }

    func testTheSetAsidesKeepOnlyWhatStillHolds() {
        let old = UUID()
        let recent = UUID()
        let new = UUID()
        let now = at(20, 12)
        let setAside = QuickCountPrompt.settingAside(new, at: now, in: [old: at(17, 12), recent: at(18, 9)], calendar: calendar)
        XCTAssertEqual(setAside, [recent: at(18, 9), new: now], "three days done, the first is dropped")

        XCTAssertEqual(QuickCountPrompt.decodeSetAside(QuickCountPrompt.encodeSetAside(setAside)), setAside)
        XCTAssertEqual(QuickCountPrompt.decodeSetAside(Data()), [:], "nothing stored is nothing set aside")
        XCTAssertEqual(QuickCountPrompt.decodeSetAside(Data("garbage".utf8)), [:])

        XCTAssertTrue(QuickCountPrompt.isSetAside(recent, in: setAside, tapped: nil, now: now, calendar: calendar))
        XCTAssertFalse(QuickCountPrompt.isSetAside(old, in: setAside, tapped: nil, now: now, calendar: calendar))
    }
}
