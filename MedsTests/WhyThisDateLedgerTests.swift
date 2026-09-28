import SwiftData
import XCTest
@testable import Meds

/// "Why this date?" reads as a ledger a caregiver can check against the
/// bottle: the amount first, the plural right, one full sentence for
/// VoiceOver, and the conclusion and alert the forecast and planner reached.
final class WhyThisDateLedgerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func day(_ date: Date) -> String { ForecastEngine.dayText(date, calendar: calendar) }

    private func moment(_ date: Date) -> String {
        "\(day(date)) at \(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, calendar: calendar, timeZone: calendar.timeZone)))"
    }

    private typealias Tally = ForecastBreakdown.Tally

    private func forecast(
        supply: Double,
        runsOut: Date? = nil,
        days: Int? = nil,
        explanation: String = "Based on the confirmed count and current schedule.",
        assumed: Int = 0,
        needsCount: Bool = false,
        sinceRefill: Bool = false,
        courseEnd: Date? = nil,
        covered: Bool = false,
        finished: Bool = false,
        leftover: Double? = nil
    ) -> SupplyForecast {
        SupplyForecast(
            currentSupply: supply,
            depletionDate: runsOut,
            daysRemaining: days,
            confidence: assumed > 0 ? .estimated : .high,
            explanation: explanation,
            assumedDoses: assumed,
            needsCount: needsCount,
            assumedSinceRefill: sinceRefill,
            courseEndDate: courseEnd,
            courseCovered: covered,
            courseFinished: finished,
            leftoverAtCourseEnd: leftover
        )
    }

    private func breakdown(
        form: MedicationForm = .tablet,
        start: ForecastBreakdown.Anchor.Kind = .count,
        startBalance: Double = 60,
        refills: Tally = Tally(count: 0, quantity: 0),
        adjustments: [ForecastBreakdown.Adjustment] = [],
        taken: Tally = Tally(count: 0, quantity: 0),
        fromHealth: Int = 0,
        ledger: Double,
        assumed: Tally = Tally(count: 0, quantity: 0),
        use: ForecastBreakdown.Use? = .daily(quantity: 2),
        forecast: SupplyForecast,
        alert: ForecastBreakdown.Alert? = nil
    ) -> ForecastBreakdown {
        ForecastBreakdown(
            form: form,
            anchor: ForecastBreakdown.Anchor(kind: start, date: date(9, 10, 7), balance: startBalance),
            refills: refills,
            adjustments: adjustments,
            taken: taken,
            takenFromHealth: fromHealth,
            ledgerBalance: ledger,
            assumed: assumed,
            use: use,
            courseEnd: forecast.courseEndDate,
            forecast: forecast,
            alert: alert
        )
    }

    private func lines(_ breakdown: ForecastBreakdown, isAsNeeded: Bool = false, isArchived: Bool = false) -> [WhyThisDateLedger.Line] {
        WhyThisDateLedger.lines(for: breakdown, isAsNeeded: isAsNeeded, isArchived: isArchived, calendar: calendar)
    }

    /// Counted 60, refilled 30, 24 logged (3 from Health), 4 not logged, two a
    /// day, no refills left: every line of the walk, and what it concludes.
    func testTheLedgerReadsAsTheBottleIsCounted() {
        let alertDate = date(10, 4, 9)
        let result = lines(breakdown(
            refills: Tally(count: 1, quantity: 30),
            taken: Tally(count: 24, quantity: 24),
            fromHealth: 3,
            ledger: 66,
            assumed: Tally(count: 4, quantity: 4),
            forecast: forecast(supply: 66, runsOut: date(10, 14, 8), days: 19, assumed: 4),
            alert: ForecastBreakdown.Alert(date: alertDate, leadDays: 10, chosenLeadDays: 7, needsPrescriber: true, state: .planned)
        ))

        XCTAssertEqual(result.map(\.text), [
            "Counted 60 tablets on \(day(date(9, 10)))",
            "+30 tablets from 1 refill",
            "−24 tablets from 24 logged doses (3 from Apple Health)",
            "= 66 tablets on record",
            "−4 tablets from 4 scheduled doses not logged, assumed taken",
            "= about 62 tablets left",
            "Uses 2 tablets a day",
            "Runs out around \(day(date(10, 14)))",
            "Low-supply alert on \(moment(alertDate))"
        ])
        XCTAssertEqual(result.map(\.kind), [.start, .change, .change, .total, .change, .total, .use, .conclusion, .alert])
        XCTAssertEqual(result.map(\.spoken), [
            "Counted 60 tablets on \(day(date(9, 10))).",
            "Plus 30 tablets from 1 refill since then.",
            "Minus 24 tablets for 24 doses logged as taken since then, 3 of them from Apple Health.",
            "That comes to 66 tablets on record.",
            "Minus 4 tablets for 4 scheduled doses since the last count that weren't logged, assumed taken.",
            "That leaves about 62 tablets.",
            "The schedule uses 2 tablets a day.",
            "Runs out around \(day(date(10, 14))).",
            "Low-supply alert on \(moment(alertDate)). No refills are left, so the warning comes 10 days before, to allow time for a new prescription."
        ])
        XCTAssertEqual(result.last?.detail, "No refills are left, so the warning comes 10 days before, to allow time for a new prescription.")
        XCTAssertFalse(result.contains(where: \.isWarning))
        XCTAssertTrue(result.allSatisfy { $0.spoken.hasSuffix(".") }, "each line is one full sentence")
    }

    func testOneOfEachSaysItInTheSingularAndEveryFormTakesItsOwnPlural() {
        let patches = lines(breakdown(
            form: .patch,
            start: .openingCount,
            startBalance: 1,
            refills: Tally(count: 2, quantity: 20),
            taken: Tally(count: 1, quantity: 1),
            fromHealth: 1,
            ledger: 20,
            assumed: Tally(count: 1, quantity: 1),
            use: .daily(quantity: 1),
            forecast: forecast(supply: 20, runsOut: date(10, 1, 8), days: 21, assumed: 1, sinceRefill: true)
        ))
        XCTAssertEqual(Array(patches.map(\.text).prefix(7)), [
            "Started with 1 patch on \(day(date(9, 10)))",
            "+20 patches from 2 refills",
            "−1 patch from 1 logged dose (1 from Apple Health)",
            "= 20 patches on record",
            "−1 patch from 1 scheduled dose not logged, assumed taken",
            "= about 19 patches left",
            "Uses 1 patch a day"
        ])
        XCTAssertEqual(patches[2].spoken, "Minus 1 patch for 1 dose logged as taken since then, from Apple Health.")
        XCTAssertEqual(patches[4].spoken, "Minus 1 patch for 1 scheduled dose since the last refill that wasn't logged, assumed taken.")

        let liquid = lines(breakdown(
            form: .liquid,
            startBalance: 200,
            taken: Tally(count: 10, quantity: 50),
            fromHealth: 10,
            ledger: 150,
            use: .daily(quantity: 10),
            forecast: forecast(supply: 150, runsOut: date(9, 25, 8), days: 15)
        ))
        XCTAssertEqual(liquid[1].text, "−50 mL from 10 logged doses (10 from Apple Health)")
        XCTAssertEqual(liquid[1].spoken, "Minus 50 mL for 10 doses logged as taken since then, all of them from Apple Health.")
        XCTAssertEqual(liquid[2].text, "= 150 mL on hand", "nothing assumed, so the number is what is on hand")
        XCTAssertEqual(liquid[3].text, "Uses 10 mL a day")

        let halves = lines(breakdown(
            taken: Tally(count: 3, quantity: 1.5),
            ledger: 58.5,
            use: .daily(quantity: 0.5),
            forecast: forecast(supply: 58.5, runsOut: date(1, 1, 8), days: 100)
        ))
        XCTAssertEqual(halves[1].text, "−1.5 tablets from 3 logged doses")
        XCTAssertEqual(halves[1].spoken, "Minus 1.5 tablets for 3 doses logged as taken since then.")
        XCTAssertEqual(halves[3].text, "Uses 0.5 tablets a day")
    }

    func testLossesAndNothingLoggedAreLinesOfTheirOwn() {
        let result = lines(breakdown(
            adjustments: [
                ForecastBreakdown.Adjustment(reason: .lost, count: 1, quantity: -2),
                ForecastBreakdown.Adjustment(reason: .discarded, count: 1, quantity: -1),
                ForecastBreakdown.Adjustment(reason: .returned, count: 2, quantity: -3)
            ],
            ledger: 54,
            forecast: forecast(supply: 54, runsOut: date(10, 7, 8), days: 27)
        ))
        XCTAssertEqual(Array(result.map(\.text)[1...5]), [
            "−2 tablets lost or damaged",
            "−1 tablet discarded",
            "−3 tablets returned",
            "No doses logged since then",
            "= 54 tablets on hand"
        ])
        XCTAssertEqual(result[1].spoken, "Minus 2 tablets lost or damaged since then.")
        XCTAssertEqual(result[4].spoken, "No doses logged as taken since then.")
    }

    /// More logged than was ever counted: the ledger is below nothing, and
    /// the forecast, and so this, reads it as none.
    func testALedgerBelowNothingReadsAsNone() {
        let result = lines(breakdown(
            startBalance: 10,
            taken: Tally(count: 13, quantity: 13),
            ledger: -3,
            forecast: forecast(supply: 0, runsOut: date(9, 20), days: 0, explanation: "No confirmed supply remains.")
        ))
        let total = result[2]
        XCTAssertEqual(total.kind, .total)
        XCTAssertEqual(total.text, "= none on record")
        XCTAssertEqual(total.detail, "More was logged as taken than was on record.")
        XCTAssertEqual(total.spoken, "That comes to none on record: more was logged as taken than was on record.")
        XCTAssertEqual(result.last?.text, "No confirmed supply remains")
        XCTAssertEqual(result.last?.isWarning, true)
    }

    func testTheWalkStartsWhereTheLedgerLastKnewWhatWasOnHand() {
        let started = lines(breakdown(start: .openingCount, startBalance: 28, ledger: 28, forecast: forecast(supply: 28, runsOut: date(9, 24), days: 14)))
        XCTAssertEqual(started.first?.text, "Started with 28 tablets on \(day(date(9, 10)))")

        let refilled = lines(breakdown(start: .refillOntoEmpty, startBalance: 30, ledger: 30, forecast: forecast(supply: 30, runsOut: date(9, 25), days: 15)))
        XCTAssertEqual(refilled.first?.text, "30 tablets after the refill on \(day(date(9, 10)))")
        XCTAssertEqual(refilled.first?.detail, "Nothing was on record before it.")
        XCTAssertEqual(refilled.first?.spoken, "30 tablets after the refill on \(day(date(9, 10))), when nothing was on record before it.")

        let never = lines(breakdown(start: .added, startBalance: 0, ledger: 0, use: nil, forecast: forecast(supply: 0, runsOut: date(9, 10), days: 0, explanation: "No confirmed supply remains.")))
        XCTAssertEqual(never.first?.text, "Nothing counted since it was added on \(day(date(9, 10)))")
        XCTAssertEqual(never.first?.kind, .start)
    }

    func testAsNeededUseIsTheHistoryThatExists() {
        let rate = ForecastBreakdown.AsNeededRate(doseCount: 6, quantity: 12, windowDays: 12)
        let weeks = lines(breakdown(ledger: 40, use: .asNeeded(rate), forecast: forecast(supply: 40, runsOut: date(10, 20), days: 40, explanation: "Estimated from the last 12 days of as-needed use.")), isAsNeeded: true)
        let use = weeks.first { $0.kind == .use }
        XCTAssertEqual(use?.text, "As needed: 12 tablets in 6 doses over the last 12 days, about 1 tablet a day")
        XCTAssertEqual(use?.spoken, "Taken as needed: 12 tablets in 6 doses over the last 12 days, about 1 tablet a day.")

        let today = lines(breakdown(ledger: 17, use: .asNeeded(ForecastBreakdown.AsNeededRate(doseCount: 3, quantity: 3, windowDays: 1)),
                                    forecast: forecast(supply: 17, runsOut: date(9, 15), days: 5, explanation: "Estimated from today's as-needed use.")), isAsNeeded: true)
        XCTAssertEqual(today.first { $0.kind == .use }?.text, "As needed: 3 tablets in 3 doses today")

        let thin = lines(breakdown(ledger: 18, use: nil, forecast: forecast(supply: 18, explanation: "Log at least three as-needed doses to create an estimate.")), isAsNeeded: true)
        XCTAssertNil(thin.first { $0.kind == .use })
        XCTAssertEqual(thin.last?.text, "Not enough history yet")
        XCTAssertEqual(thin.last?.detail, "Log at least three as-needed doses to create an estimate.")
        XCTAssertEqual(thin.last?.spoken, "Not enough history yet. Log at least three as-needed doses to create an estimate.")

        let unscheduled = lines(breakdown(ledger: 18, use: nil, forecast: forecast(supply: 18, explanation: "Add a schedule to estimate when this supply will run out.")))
        XCTAssertEqual(unscheduled.last?.text, "Timing unknown")
        XCTAssertEqual(unscheduled.last?.detail, "Add a schedule to estimate when this supply will run out.")

        let weekly = lines(breakdown(ledger: 60, use: .weekly(quantity: 10), forecast: forecast(supply: 60, runsOut: date(11, 1), days: 42)))
        XCTAssertEqual(weekly.first { $0.kind == .use }?.text, "Uses 10 tablets a week, about 1.43 tablets a day")
    }

    func testEachConclusionSaysWhatTheForecastConcluded() {
        let end = date(10, 3, 23)
        let covered = lines(breakdown(ledger: 30, forecast: forecast(supply: 30, courseEnd: end, covered: true, leftover: 6)))
        XCTAssertEqual(covered.suffix(2).map(\.text), [
            "Last day of the course: \(day(end))",
            "Enough to finish the course on \(day(end)), with 6 tablets left"
        ])
        XCTAssertEqual(covered[covered.count - 2].spoken, "The course's last day is \(day(end)).")

        let exactly = lines(breakdown(ledger: 24, forecast: forecast(supply: 24, courseEnd: end, covered: true, leftover: 0)))
        XCTAssertEqual(exactly.last?.text, "Just enough to finish the course on \(day(end))")

        let short = lines(breakdown(ledger: 10, forecast: forecast(supply: 10, runsOut: date(9, 15, 8), days: 5, courseEnd: end)))
        XCTAssertEqual(short.last?.text, "Runs out around \(day(date(9, 15)))")
        XCTAssertEqual(short.last?.detail, "Before the course's last day, \(day(end)).")
        XCTAssertEqual(short.last?.spoken, "Runs out around \(day(date(9, 15))), before the course's last day, \(day(end)).")

        let finished = lines(breakdown(ledger: 4, use: nil, forecast: forecast(supply: 4, explanation: "Course finished \(day(end)).", courseEnd: end, finished: true)))
        XCTAssertNil(finished.first { $0.kind == .courseEnd }, "the conclusion says the last day; a line apart it read as a second day")
        XCTAssertEqual(finished.last?.text, "Course finished \(day(end))")
        XCTAssertEqual(finished.last?.detail, "Nothing more is scheduled, so nothing needs a refill.")
        XCTAssertEqual(finished.last?.isWarning, false)

        let stale = lines(breakdown(
            startBalance: 10,
            ledger: 10,
            assumed: Tally(count: 7, quantity: 14),
            forecast: forecast(supply: 10, runsOut: date(9, 17), days: 0, explanation: "If the 7 scheduled doses …", assumed: 7, needsCount: true)
        ))
        XCTAssertEqual(stale.map(\.text).suffix(4), [
            "−14 tablets from 7 scheduled doses not logged, assumed taken",
            "= none left on record",
            "Uses 2 tablets a day",
            "Count needed"
        ])
        XCTAssertEqual(stale[stale.count - 3].spoken, "That leaves none of the supply on record.")
        XCTAssertEqual(stale.last?.detail, "The doses nobody logged use up what's on record, so only a count can say what's left.")
        XCTAssertEqual(stale.last?.spoken, "Count needed. The doses nobody logged use up what's on record, so only a count can say what's left.")
        XCTAssertEqual(stale.filter(\.isWarning).map(\.kind), [.total, .conclusion])
        XCTAssertFalse(stale.contains { $0.text.contains("Runs out") }, "a count needed has no run-out day, only where the assumptions ran out")

        let beyond = lines(breakdown(ledger: 5000, forecast: forecast(supply: 5000, explanation: "The confirmed supply extends beyond the forecast window.")))
        XCTAssertEqual(beyond.last?.text, "Timing unknown")
        XCTAssertEqual(beyond.last?.detail, "The confirmed supply extends beyond the forecast window.")
    }

    func testEachAlertStateSaysWhenOrWhyNot() {
        let alertDate = date(10, 7, 9)
        func alert(_ state: ForecastBreakdown.Alert.State, lead: Int = 7, chosen: Int = 7, prescriber: Bool = false, archived: Bool = false) -> WhyThisDateLedger.Line? {
            lines(breakdown(
                ledger: 60,
                forecast: forecast(supply: 60, runsOut: date(10, 14, 8), days: 30),
                alert: ForecastBreakdown.Alert(date: alertDate, leadDays: lead, chosenLeadDays: chosen, needsPrescriber: prescriber, state: state)
            ), isArchived: archived).last
        }

        let planned = alert(.planned)
        XCTAssertEqual(planned?.kind, .alert)
        XCTAssertEqual(planned?.text, "Low-supply alert on \(moment(alertDate))")
        XCTAssertEqual(planned?.detail, "7 days before it runs out.")
        XCTAssertEqual(planned?.spoken, "Low-supply alert on \(moment(alertDate)). 7 days before it runs out.")

        XCTAssertEqual(alert(.planned, lead: 1, chosen: 1)?.detail, "1 day before it runs out.")
        XCTAssertEqual(alert(.planned, lead: 14, chosen: 14, prescriber: true)?.detail, "14 days before it runs out.",
                       "a lead already past the prescriber's is not lengthened, so there is nothing to explain")
        XCTAssertEqual(alert(.planned, lead: 10, chosen: 7, prescriber: true)?.detail,
                       "No refills are left, so the warning comes 10 days before, to allow time for a new prescription.")

        let passed = alert(.passed)
        XCTAssertEqual(passed?.text, "Low-supply alert was due \(moment(alertDate))")
        XCTAssertEqual(passed?.detail, "Already passed. Alerts aren't sent late.")
        XCTAssertEqual(passed?.spoken, "Low-supply alert was due \(moment(alertDate)). Already passed. Alerts aren't sent late.")

        let check = date(10, 9, 9)
        let paused = alert(.pausedByRefill(checkAt: check))
        XCTAssertEqual(paused?.text, "Low-supply alert paused while the refill is on its way")
        XCTAssertEqual(paused?.detail, "Checked again on \(moment(check)).")
        XCTAssertEqual(paused?.spoken, "Low-supply alert paused while the refill is on its way. Checked again on \(moment(check)).")
        XCTAssertEqual(alert(.pausedByRefill(checkAt: nil))?.detail, "It comes back if the refill runs two days late or supply gets very low.")

        let off = alert(.off)
        XCTAssertEqual(off?.text, "Low-supply alert off")
        XCTAssertEqual(off?.detail, "Refill reminders are off for this medication.")
        XCTAssertEqual(alert(.off, archived: true)?.detail, "This medication is archived.")

        XCTAssertNil(lines(breakdown(ledger: 60, forecast: forecast(supply: 60, runsOut: date(10, 14), days: 30))).first { $0.kind == .alert },
                     "no alert, no line")
    }

    /// With notifications refused or never allowed, iOS delivers nothing the
    /// app plans, so the alert's time is not left standing as a promise.
    func testAnAlertThatCannotBeDeliveredSaysSo() {
        let alertDate = date(10, 7, 9)
        func alert(_ state: ForecastBreakdown.Alert.State, allowed: Bool) -> WhyThisDateLedger.Line? {
            WhyThisDateLedger.lines(
                for: breakdown(
                    ledger: 60,
                    forecast: forecast(supply: 60, runsOut: date(10, 14, 8), days: 30),
                    alert: ForecastBreakdown.Alert(date: alertDate, leadDays: 7, chosenLeadDays: 7, needsPrescriber: false, state: state)
                ),
                isAsNeeded: false,
                notificationsAllowed: allowed,
                calendar: calendar
            ).last
        }

        let blocked = alert(.planned, allowed: false)
        XCTAssertEqual(blocked?.text, "Low-supply alert on \(moment(alertDate))")
        XCTAssertEqual(blocked?.detail, "7 days before it runs out. It can't be sent until notifications are allowed for Meds Ahead.")
        XCTAssertEqual(blocked?.spoken, "Low-supply alert on \(moment(alertDate)). 7 days before it runs out. It can't be sent until notifications are allowed for Meds Ahead.")
        XCTAssertEqual(blocked?.isWarning, true)
        XCTAssertEqual(alert(.planned, allowed: true)?.isWarning, false)

        let check = date(10, 9, 9)
        XCTAssertEqual(alert(.pausedByRefill(checkAt: check), allowed: false)?.detail,
                       "Checked again on \(moment(check)). It can't be sent until notifications are allowed for Meds Ahead.")
        XCTAssertEqual(alert(.passed, allowed: false)?.detail, "Already passed. Alerts aren't sent late.", "nothing was going to be sent")
        XCTAssertEqual(alert(.off, allowed: false)?.detail, "Refill reminders are off for this medication.")
    }

    /// From the engine itself: the lines walk the same ledger and reach the
    /// same date the forecast shows.
    func testTheLinesComeFromTheForecastsOwnBreakdown() throws {
        let medication = Medication(name: "Mycophenolate", createdAt: date(9, 1, 7))
        let schedules = [8, 20].map { DoseSchedule(medicationID: medication.id, minutesAfterMidnight: $0 * 60, doseQuantity: 1, startDate: date(9, 1, 7)) }
        let inventory = [
            InventoryEvent(medicationID: medication.id, date: date(9, 1, 7), delta: 30, reason: .openingCount),
            InventoryEvent(medicationID: medication.id, date: date(9, 2, 12), delta: 30, reason: .refill)
        ]
        let doses = [
            DoseEvent(medicationID: medication.id, scheduleID: schedules[0].id, scheduledAt: date(9, 1, 8), recordedAt: date(9, 1, 8), doseQuantity: 1, status: .taken),
            DoseEvent(medicationID: medication.id, scheduleID: schedules[1].id, scheduledAt: date(9, 1, 20), recordedAt: date(9, 1, 20), doseQuantity: 1, status: .taken, healthSampleID: UUID())
        ]
        let now = date(9, 3, 7)
        let breakdown = ForecastEngine.breakdown(medication: medication, schedules: schedules, inventoryEvents: inventory, doseEvents: doses, now: now, calendar: calendar)
        let forecast = ForecastEngine.forecast(medication: medication, schedules: schedules, inventoryEvents: inventory, doseEvents: doses, now: now, calendar: calendar)
        let result = lines(breakdown)

        XCTAssertEqual(Array(result.map(\.text).prefix(6)), [
            "Started with 30 tablets on \(day(date(9, 1)))",
            "+30 tablets from 1 refill",
            "−2 tablets from 2 logged doses (1 from Apple Health)",
            "= 58 tablets on record",
            "−2 tablets from 2 scheduled doses not logged, assumed taken",
            "= about 56 tablets left"
        ])
        XCTAssertEqual(result.first { $0.kind == .conclusion }?.text, "Runs out around \(day(try XCTUnwrap(forecast.depletionDate)))")
        XCTAssertEqual(result.last?.kind, .alert)
    }

    /// A taper, as a discharge writes one: two a day through Sep 30, then one
    /// a day through Oct 14. The use line says today's amount and the step
    /// after it, so 28 left, less 10 and 14, checks against the 4 the
    /// conclusion leaves, where the two steps added together read as three a
    /// day nobody is given.
    func testATaperSaysTodaysAmountAndTheStepsAfterIt() throws {
        let medication = Medication(name: "Prednisone", createdAt: date(9, 20, 7))
        let schedules = [
            DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, doseQuantity: 2, startDate: date(9, 20, 7),
                         endDate: ScheduleEngine.normalizedEndDate(forDay: date(9, 30), calendar: calendar)),
            DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, doseQuantity: 1, startDate: date(10, 1, 0),
                         endDate: ScheduleEngine.normalizedEndDate(forDay: date(10, 14), calendar: calendar))
        ]
        let inventory = [InventoryEvent(medicationID: medication.id, date: date(9, 20, 7), delta: 40, reason: .openingCount)]
        func explained(at now: Date, _ inventory: [InventoryEvent] = inventory) -> ForecastBreakdown {
            ForecastEngine.breakdown(medication: medication, schedules: schedules, inventoryEvents: inventory, doseEvents: [], now: now, calendar: calendar)
        }

        let midway = explained(at: date(9, 25))
        XCTAssertEqual(midway.use, .daily(quantity: 2), "today's step alone")
        XCTAssertNil(midway.useStarts)
        XCTAssertEqual(midway.useChanges, [ForecastBreakdown.UseChange(date: calendar.startOfDay(for: date(10, 1)), use: .daily(quantity: 1))])
        let result = lines(midway)
        XCTAssertEqual(result.map(\.text), [
            "Started with 40 tablets on \(day(date(9, 20)))",
            "No doses logged since then",
            "= 40 tablets on record",
            "−12 tablets from 6 scheduled doses not logged, assumed taken",
            "= about 28 tablets left",
            "Uses 2 tablets a day now",
            "Last day of the course: \(day(date(10, 14)))",
            "Enough to finish the course on \(day(date(10, 14))), with 4 tablets left"
        ])
        let use = try XCTUnwrap(result.first { $0.kind == .use })
        XCTAssertEqual(use.detail, "Then 1 tablet a day from \(day(date(10, 1))).")
        XCTAssertEqual(use.spoken, "The schedule uses 2 tablets a day now, then 1 tablet a day from \(day(date(10, 1))).")

        // On the last step, nothing is left to change to.
        let last = explained(at: date(10, 5))
        XCTAssertEqual(last.use, .daily(quantity: 1))
        XCTAssertEqual(last.useChanges, [])
        XCTAssertEqual(lines(last).first { $0.kind == .use }?.text, "Uses 1 tablet a day")

        // Counted before the course starts: nothing today, so the first step
        // says when it begins.
        let early = [InventoryEvent(medicationID: medication.id, date: date(9, 18, 7), delta: 40, reason: .openingCount)]
        let before = explained(at: date(9, 18), early)
        XCTAssertEqual(before.use, .daily(quantity: 2))
        XCTAssertEqual(before.useStarts, calendar.startOfDay(for: date(9, 20)))
        let starting = try XCTUnwrap(lines(before).first { $0.kind == .use })
        XCTAssertEqual(starting.text, "Uses 2 tablets a day from \(day(date(9, 20)))")
        XCTAssertEqual(starting.detail, "Then 1 tablet a day from \(day(date(10, 1))).")
        XCTAssertEqual(starting.spoken, "The schedule uses 2 tablets a day from \(day(date(9, 20))), then 1 tablet a day from \(day(date(10, 1))).")
    }

    /// Several steps with a day off between two of them, said in order; a
    /// step after the supply runs out played no part in the date, so it is
    /// left out.
    func testEveryStepUpToTheDateIsSaidInOrder() throws {
        let medication = Medication(name: "Prednisone", createdAt: date(9, 20, 7))
        func step(_ quantity: Double, _ first: Int, _ last: Int) -> DoseSchedule {
            DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, doseQuantity: quantity, startDate: date(9, first, 0),
                         endDate: ScheduleEngine.normalizedEndDate(forDay: date(9, last), calendar: calendar))
        }
        let schedules = [step(3, 20, 22), step(2, 23, 25), step(1, 27, 30)]
        func explained(count: Double) -> ForecastBreakdown {
            ForecastEngine.breakdown(
                medication: medication,
                schedules: schedules,
                inventoryEvents: [InventoryEvent(medicationID: medication.id, date: date(9, 20, 7), delta: count, reason: .openingCount)],
                doseEvents: [],
                now: date(9, 20, 7),
                calendar: calendar
            )
        }

        let covered = explained(count: 30)
        XCTAssertEqual(covered.conclusion, .courseCovered(end: ScheduleEngine.normalizedEndDate(forDay: date(9, 30), calendar: calendar), leftover: 11))
        let use = try XCTUnwrap(lines(covered).first { $0.kind == .use })
        XCTAssertEqual(use.text, "Uses 3 tablets a day now")
        XCTAssertEqual(use.detail, "Then 2 tablets a day from \(day(date(9, 23))), nothing scheduled from \(day(date(9, 26))) and 1 tablet a day from \(day(date(9, 27))).")

        let short = explained(count: 8)
        guard case let .runsOut(runsOut, _) = short.conclusion else { return XCTFail("eight tablets run out on the 22nd") }
        XCTAssertEqual(calendar.startOfDay(for: runsOut), calendar.startOfDay(for: date(9, 22)))
        XCTAssertEqual(short.useChanges, [], "the steps after the 22nd played no part in the date")
        XCTAssertEqual(lines(short).first { $0.kind == .use }?.text, "Uses 3 tablets a day")
    }

    /// A count, from the detail screen, Today or "Why this date?", is the
    /// difference from the ledger in the store, or a zero correction when
    /// they agree, so a count always ends "Count needed". Every screen
    /// records it through `CountCorrection`, which reads the store rather
    /// than a screen's arrays: a dose the widget has just logged is there.
    @MainActor
    func testACountIsRecordedAgainstTheLedgerInTheStore() throws {
        let schema = Schema([Medication.self, DoseSchedule.self, DoseEvent.self, InventoryEvent.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let medication = Medication(name: "Tacrolimus")
        context.insert(medication)
        context.insert(InventoryEvent(medicationID: medication.id, date: date(9, 1), delta: 60, reason: .openingCount))
        context.insert(DoseEvent(medicationID: medication.id, recordedAt: date(9, 2), doseQuantity: 2, status: .taken))
        try context.save()

        let matching = try CountCorrection.record(actualCount: 58, note: "", for: medication, in: context)
        XCTAssertEqual(matching.reason, .correction)
        XCTAssertEqual(matching.delta, 0, "a count that agrees is still a count")

        let fewer = try CountCorrection.record(actualCount: 50.5, note: "Counted twice", for: medication, in: context)
        XCTAssertEqual(fewer.delta, -7.5)
        XCTAssertEqual(fewer.note, "Counted twice")
        let inventory = try context.fetch(FetchDescriptor<InventoryEvent>())
        let doses = try context.fetch(FetchDescriptor<DoseEvent>())
        XCTAssertEqual(inventory.count, 3, "each count is a new event; nothing earlier is rewritten")
        XCTAssertEqual(ForecastEngine.rawSupplyBalance(medicationID: medication.id, inventoryEvents: inventory, doseEvents: doses), 50.5)
    }

    func testCountNowOpensWithTheCorrectCountPrefill() {
        let medication = Medication(name: "Prednisone")
        XCTAssertEqual(CountCorrection.Request(medication: medication, forecast: forecast(supply: 27.125, runsOut: date(9, 20), days: 10)).initialValue, 27.125)
        XCTAssertNil(CountCorrection.Request(medication: medication, forecast: forecast(supply: 20, runsOut: date(9, 20), days: 10, assumed: 2)).initialValue,
                     "assumed doses: a prefilled count would record one nobody made")
        XCTAssertNil(CountCorrection.Request(medication: medication, forecast: forecast(supply: 4, runsOut: date(9, 10), days: 0, assumed: 6, needsCount: true)).initialValue)
    }
}
