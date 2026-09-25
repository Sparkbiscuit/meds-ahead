import Foundation

enum ForecastConfidence: String, Equatable {
    case high
    case estimated
    case unknown
}

struct SupplyForecast: Equatable {
    let currentSupply: Double
    let depletionDate: Date?
    let daysRemaining: Int?
    let confidence: ForecastConfidence
    let explanation: String
    /// Scheduled doses since the last count that nobody logged, which the run-out
    /// date assumes were taken. `currentSupply` stays the ledger's own number.
    var assumedDoses: Int = 0
    /// The assumed doses use up everything the ledger still shows. What is left is
    /// unknown rather than zero, so this reads "Count needed", never "Out of supply".
    var needsCount: Bool = false
    /// The assumed doses are counted from a refill onto an empty ledger rather
    /// than from a count, so a reason can name the right event.
    var assumedSinceRefill: Bool = false
    /// The last day of the course the medication is on, when every one of its
    /// schedules has one.
    var courseEndDate: Date? = nil
    /// The supply outlasts what the course still asks for, so nothing runs
    /// out and nothing needs a refill. `depletionDate` is nil.
    var courseCovered: Bool = false
    /// The course's last day has passed: nothing is due and nothing needs a
    /// refill, whatever is on hand. `depletionDate` is nil.
    var courseFinished: Bool = false
    /// What the supply leaves after the course's last dose, when it covers it.
    var leftoverAtCourseEnd: Double? = nil
}

/// Which medications need a refill before a trip, from the forecasts that
/// already exist. Pure arithmetic: a supply that runs out before the return
/// date needs attention before leaving; one whose timing is unknown, or that
/// needs a count, cannot be vouched for; the rest are fine, and so is a
/// course the supply covers or that is already over.
struct TripCheck: Equatable {
    struct Item: Equatable {
        let medicationID: UUID
        let displayName: String
        let forecast: SupplyForecast
    }

    let returnDate: Date
    let needsRefill: [Item]
    let uncertain: [Item]
    let fine: [Item]

    static func make(
        returnDate: Date,
        forecasts: [(medication: Medication, forecast: SupplyForecast)],
        calendar: Calendar = .autoupdatingCurrent
    ) -> TripCheck {
        let returnDay = calendar.startOfDay(for: returnDate)
        var needsRefill: [Item] = []
        var uncertain: [Item] = []
        var fine: [Item] = []
        for (medication, forecast) in forecasts where !medication.isArchived {
            let item = Item(medicationID: medication.id, displayName: medication.displayName, forecast: forecast)
            // A count needed carries today as its run-out date, but that is
            // where the assumptions ran out, not the supply: packing for the
            // trip starts with counting it.
            if forecast.needsCount {
                uncertain.append(item)
            } else if forecast.courseCovered || forecast.courseFinished {
                // Enough for every dose the course still asks for, whether it
                // ends before the return or after it.
                fine.append(item)
            } else if let depletion = forecast.depletionDate {
                // Running out on the day of return still means arriving home
                // without a dose in hand, so that day counts as before.
                if calendar.startOfDay(for: depletion) <= returnDay {
                    needsRefill.append(item)
                } else {
                    fine.append(item)
                }
            } else {
                uncertain.append(item)
            }
        }
        let byName: (Item, Item) -> Bool = { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return TripCheck(
            returnDate: returnDate,
            needsRefill: needsRefill.sorted { ($0.forecast.depletionDate ?? .distantFuture) < ($1.forecast.depletionDate ?? .distantFuture) },
            uncertain: uncertain.sorted(by: byName),
            fine: fine.sorted(by: byName)
        )
    }
}

enum ForecastEngine {
    static func rawSupplyBalance(
        medicationID: UUID,
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent]
    ) -> Double {
        let inventory = inventoryEvents
            .filter { $0.medicationID == medicationID }
            .reduce(0) { $0 + $1.delta }
        // A dose imported from Apple Health predates the count and was never taken
        // from it; it still counts for the as-needed rate below.
        let consumed = doseEvents
            .filter { $0.medicationID == medicationID && $0.status == .taken && $0.countsTowardSupply }
            .reduce(0) { $0 + $1.doseQuantity }
        return inventory - consumed
    }

    static func currentSupply(
        medicationID: UUID,
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent]
    ) -> Double {
        max(
            0,
            rawSupplyBalance(
                medicationID: medicationID,
                inventoryEvents: inventoryEvents,
                doseEvents: doseEvents
            )
        )
    }

    static func correctionDelta(
        medicationID: UUID,
        actualCount: Double,
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent]
    ) -> Double {
        actualCount - rawSupplyBalance(
            medicationID: medicationID,
            inventoryEvents: inventoryEvents,
            doseEvents: doseEvents
        )
    }

    static func forecast(
        medication: Medication,
        schedules: [DoseSchedule],
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> SupplyForecast {
        evaluation(
            medication: medication,
            schedules: schedules,
            inventoryEvents: inventoryEvents,
            doseEvents: doseEvents,
            now: now,
            calendar: calendar
        ).forecast
    }

    /// A forecast and what it was worked out from. `forecast` hands on only
    /// the answer; `breakdown` explains it from these same values, so "Why
    /// this date?" can never describe a second calculation that disagrees
    /// with the date beside it.
    struct Evaluation {
        let forecast: SupplyForecast
        /// The amount the assumed doses stand for; the forecast counts them.
        var assumedQuantity: Double = 0
        /// The as-needed rate the run-out date is divided out from.
        var asNeededRate: ForecastBreakdown.AsNeededRate? = nil
    }

    static func evaluation(
        medication: Medication,
        schedules: [DoseSchedule],
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent],
        now: Date,
        calendar: Calendar
    ) -> Evaluation {
        let supply = currentSupply(
            medicationID: medication.id,
            inventoryEvents: inventoryEvents,
            doseEvents: doseEvents
        )
        // A course is kept by schedules, and an as-needed medication has
        // none, whatever was left behind when it was made as-needed.
        let courseEnd = medication.isAsNeeded ? nil : ScheduleEngine.courseEnd(schedules: schedules, medicationID: medication.id)

        // Asked before the supply: an empty bottle is how a course dispensed
        // to the tablet ends, not a supply to warn about, and a few tablets
        // left over are not one to plan a refill around.
        if let courseEnd, ScheduleEngine.isCourseFinished(schedules: schedules, medicationID: medication.id, now: now, calendar: calendar) {
            return Evaluation(forecast: SupplyForecast(
                currentSupply: supply,
                depletionDate: nil,
                daysRemaining: nil,
                confidence: .high,
                explanation: "Course finished \(dayText(courseEnd, calendar: calendar)).",
                courseEndDate: courseEnd,
                courseFinished: true
            ))
        }

        guard supply > 0 || courseEnd != nil else {
            return Evaluation(forecast: noConfirmedSupply(now: now, courseEnd: nil))
        }

        if medication.isAsNeeded {
            return asNeededEvaluation(
                medication: medication,
                supply: supply,
                doseEvents: doseEvents,
                now: now,
                calendar: calendar
            )
        }

        guard schedules.contains(where: { $0.medicationID == medication.id }) else {
            return Evaluation(forecast: SupplyForecast(
                currentSupply: supply,
                depletionDate: nil,
                daysRemaining: nil,
                confidence: .unknown,
                explanation: "Add a schedule to estimate when this supply will run out."
            ))
        }

        return scheduledEvaluation(
            medication: medication,
            supply: supply,
            courseEnd: courseEnd,
            schedules: schedules,
            inventoryEvents: inventoryEvents,
            doseEvents: doseEvents,
            now: now,
            calendar: calendar
        )
    }

    private static func noConfirmedSupply(now: Date, courseEnd: Date?) -> SupplyForecast {
        SupplyForecast(
            currentSupply: 0,
            depletionDate: now,
            daysRemaining: 0,
            confidence: .high,
            explanation: "No confirmed supply remains.",
            courseEndDate: courseEnd
        )
    }

    private static func scheduledEvaluation(
        medication: Medication,
        supply: Double,
        courseEnd: Date?,
        schedules: [DoseSchedule],
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent],
        now: Date,
        calendar: Calendar
    ) -> Evaluation {
        let anchor = ledgerAnchor(medication: medication, inventoryEvents: inventoryEvents, doseEvents: doseEvents)
        // A dose becomes an assumed one when Today would call it overdue, and is
        // one of the doses still to come until then. Every unlogged dose since
        // the anchor is in exactly one of the two, so the date holds still while
        // a dose sits in its due window, and a dose logged early is not charged
        // twice.
        let overdueBefore = now.addingTimeInterval(-ScheduleEngine.dueWindow)
        // A log outside every slot stands for one of its doses only when it was
        // taken from this count: charged to the supply and made since the anchor.
        // History imported with the medication never came out of the count, and
        // a dose from before the anchor is already reflected in it.
        let accounting = doseEvents.filter {
            $0.medicationID == medication.id && ($0.scheduleID != nil
                || ($0.status == .taken && $0.countsTowardSupply && $0.recordedAt >= anchor.date && $0.recordedAt <= now))
        }
        let logs = ScheduleEngine.DoseLogIndex(doseEvents: accounting, medicationID: medication.id, calendar: calendar)
        func unlogged(from start: Date, through end: Date, logs: ScheduleEngine.DoseLogIndex = logs) -> [ScheduledDose] {
            ScheduleEngine.unloggedDoses(
                schedules: schedules,
                medicationID: medication.id,
                from: start,
                through: end,
                logs: logs,
                now: now,
                calendar: calendar
            )
        }
        // The doses still to come start where the assumed ones stop, or at the
        // anchor when it is more recent, since a count already holds everything
        // taken before it.
        let dosesToComeFrom = max(overdueBefore, min(anchor.date, now))
        let threeYears = calendar.date(byAdding: .year, value: 3, to: now) ?? now
        // A course's doses stop on its last day, so the doses to come stop
        // there too. One ending past the forecast window is weighed like any
        // other schedule.
        let courseLimit = courseEnd
            .map { ScheduleEngine.courseLastMoment($0, calendar: calendar) }
            .flatMap { $0 <= threeYears ? $0 : nil }

        guard supply > 0 else {
            // Nothing on record is how a course dispensed to the tablet ends,
            // but only once every dose it asked for since the anchor was
            // logged taken. A dose still to come is a gap, and so is one that
            // went by unlogged or skipped: with the bottle empty, that is most
            // likely a course that ran out early, and calling it enough would
            // clear the warning for a family still missing doses.
            if let courseEnd, let courseLimit,
               unlogged(
                   from: anchor.date,
                   through: courseLimit,
                   logs: ScheduleEngine.DoseLogIndex(doseEvents: accounting.filter { $0.status == .taken }, medicationID: medication.id, calendar: calendar)
               ).isEmpty {
                return Evaluation(forecast: SupplyForecast(
                    currentSupply: 0,
                    depletionDate: nil,
                    daysRemaining: nil,
                    confidence: .high,
                    explanation: courseCoveredText(courseEnd, leftover: 0, form: medication.form, calendar: calendar),
                    courseEndDate: courseEnd,
                    courseCovered: true,
                    leftoverAtCourseEnd: 0
                ))
            }
            return Evaluation(forecast: noConfirmedSupply(now: now, courseEnd: courseEnd))
        }

        let assumed = unlogged(from: anchor.date, through: overdueBefore)
        let assumedQuantity = assumed.reduce(0) { $0 + $1.quantity }
        let since = anchor.isRefill ? "since your last refill" : "since your last count"
        let unloggedText = assumed.count == 1
            ? "the 1 scheduled dose \(since) that wasn't logged was taken"
            : "the \(assumed.count) scheduled doses \(since) that weren't logged were taken"
        let assumedSinceRefill = !assumed.isEmpty && anchor.isRefill

        var remaining = supply - assumedQuantity
        // The assumed doses take a course's supply exactly to nothing and no
        // dose of it is left to come: its last dose went by unlogged, and the
        // course was dispensed to the tablet. That is the course seen through,
        // as it read while that dose was still in its due window.
        if let courseEnd, let courseLimit, !assumed.isEmpty, remaining <= 0.000_001, remaining >= -0.000_001,
           unlogged(from: dosesToComeFrom, through: courseLimit).filter({ $0.date > overdueBefore }).isEmpty {
            return Evaluation(forecast: SupplyForecast(
                currentSupply: supply,
                depletionDate: nil,
                daysRemaining: nil,
                confidence: .estimated,
                explanation: courseCoveredText(courseEnd, leftover: 0, form: medication.form, calendar: calendar) + " Assumes \(unloggedText).",
                assumedDoses: assumed.count,
                assumedSinceRefill: assumedSinceRefill,
                courseEndDate: courseEnd,
                courseCovered: true,
                leftoverAtCourseEnd: 0
            ), assumedQuantity: assumedQuantity)
        }
        // The ledger still shows medication, but not once the doses nobody logged
        // are taken out of it. Nothing on record says how much is really left, so
        // the answer is a count, not a claim that the supply is gone.
        if !assumed.isEmpty, remaining <= 0.000_001 {
            return Evaluation(forecast: SupplyForecast(
                currentSupply: supply,
                depletionDate: now,
                daysRemaining: 0,
                confidence: .estimated,
                explanation: "If \(unloggedText), none of the supply on record is left. Count what is left to update the forecast.",
                assumedDoses: assumed.count,
                needsCount: true,
                assumedSinceRefill: anchor.isRefill,
                courseEndDate: courseEnd
            ), assumedQuantity: assumedQuantity)
        }

        // The doses still to come are worked out a stretch at a time, each twice
        // the last, so a month's supply does not first lay out three years.
        let horizon = courseLimit ?? threeYears
        var stretchStart = dosesToComeFrom
        var stretchDays = 31
        stretching: while stretchStart <= horizon {
            let stretchEnd = min(
                horizon,
                (calendar.date(byAdding: .day, value: stretchDays, to: calendar.startOfDay(for: stretchStart)) ?? horizon).addingTimeInterval(-1)
            )
            let upcoming = unlogged(from: stretchStart, through: stretchEnd).filter { $0.date > overdueBefore }
            for (index, dose) in upcoming.enumerated() {
                remaining -= dose.quantity
                guard remaining <= 0.000_001 else { continue }
                // The dose that takes a course's supply exactly to nothing
                // finishes the course when no dose follows it: nothing runs
                // out before the course ends.
                if courseLimit != nil, remaining >= -0.000_001, index == upcoming.count - 1,
                   stretchEnd >= horizon || unlogged(from: stretchEnd.addingTimeInterval(1), through: horizon).isEmpty {
                    remaining = 0
                    break stretching
                }
                let basis = assumed.isEmpty ? "Based on the confirmed count and current schedule." : "Assumes \(unloggedText)."
                return Evaluation(forecast: SupplyForecast(
                    currentSupply: supply,
                    depletionDate: dose.date,
                    daysRemaining: max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: dose.date)).day ?? 0),
                    confidence: assumed.isEmpty ? .high : .estimated,
                    explanation: basis + (courseEnd.map { " Runs out before the course ends on \(dayText($0, calendar: calendar))." } ?? ""),
                    assumedDoses: assumed.count,
                    assumedSinceRefill: assumedSinceRefill,
                    courseEndDate: courseEnd
                ), assumedQuantity: assumedQuantity)
            }
            guard stretchEnd < horizon else { break }
            stretchStart = stretchEnd.addingTimeInterval(1)
            stretchDays *= 2
        }

        if let courseEnd, courseLimit != nil {
            return Evaluation(forecast: SupplyForecast(
                currentSupply: supply,
                depletionDate: nil,
                daysRemaining: nil,
                confidence: assumed.isEmpty ? .high : .estimated,
                explanation: courseCoveredText(courseEnd, leftover: remaining, form: medication.form, calendar: calendar)
                    + (assumed.isEmpty ? "" : " Assumes \(unloggedText)."),
                assumedDoses: assumed.count,
                assumedSinceRefill: assumedSinceRefill,
                courseEndDate: courseEnd,
                courseCovered: true,
                leftoverAtCourseEnd: remaining
            ), assumedQuantity: assumedQuantity)
        }

        return Evaluation(forecast: SupplyForecast(
            currentSupply: supply,
            depletionDate: nil,
            daysRemaining: nil,
            confidence: .unknown,
            explanation: "The confirmed supply extends beyond the forecast window.",
            assumedDoses: assumed.count,
            assumedSinceRefill: assumedSinceRefill,
            courseEndDate: courseEnd
        ), assumedQuantity: assumedQuantity)
    }

    private static func courseCoveredText(_ courseEnd: Date, leftover: Double, form: MedicationForm, calendar: Calendar) -> String {
        "Enough to finish the course on \(dayText(courseEnd, calendar: calendar)), with \(form.quantityText(leftover)) left."
    }

    /// A day as the forecast's own words write it, "Sep 30", in the calendar
    /// the forecast was made with, so a course's last day reads as the day
    /// that was chosen.
    static func dayText(_ date: Date, calendar: Calendar) -> String {
        date.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day())
    }

    /// Where the doses nobody logged start being assumed taken: the last moment
    /// the ledger's number was known to be what was on hand. Counting only the
    /// doses still to come let every unlogged day push the run-out date a day
    /// later, so a family that stopped logging watched it slide forever and the
    /// refill alert keyed to it never arrived. A count says what is on hand
    /// outright. So does a refill onto a ledger that showed nothing: no dose
    /// could come out of an empty supply, so what is on hand after it is the
    /// refill. A refill onto stock the ledger still showed confirms nothing
    /// about the doses before it. With neither, the medication's creation. The
    /// whole stretch since is weighed, however long: stopping at a fixed look-
    /// back dropped the oldest doses one a day and brought the slide back.
    struct LedgerAnchor {
        let date: Date
        let isRefill: Bool
        /// The medication's inventory events, oldest first.
        let inventory: [InventoryEvent]
        /// Where the anchor's event falls in `inventory`; nil when nothing was
        /// ever counted and the anchor is the medication's creation.
        let index: Int?
        /// The ledger's number right after the anchor's event: every event up
        /// to it, less the doses taken before it.
        let balance: Double
    }

    static func ledgerAnchor(
        medication: Medication,
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent]
    ) -> LedgerAnchor {
        let inventory = inventoryEvents
            .filter { $0.medicationID == medication.id }
            .sorted { $0.date < $1.date }
        let taken = doseEvents
            .compactMap { event -> (date: Date, quantity: Double)? in
                guard event.medicationID == medication.id, event.status == .taken, event.countsTowardSupply else { return nil }
                return (event.recordedAt, event.doseQuantity)
            }
            .sorted { $0.date < $1.date }
        var anchor: LedgerAnchor?
        var balance = 0.0
        var nextDose = 0
        for (index, event) in inventory.enumerated() {
            while nextDose < taken.count, taken[nextDose].date < event.date {
                balance -= taken[nextDose].quantity
                nextDose += 1
            }
            if event.reason == .openingCount || event.reason == .correction {
                anchor = LedgerAnchor(date: event.date, isRefill: false, inventory: inventory, index: index, balance: balance + event.delta)
            } else if event.reason == .refill, event.delta > 0, balance <= 0.000_001 {
                anchor = LedgerAnchor(date: event.date, isRefill: true, inventory: inventory, index: index, balance: balance + event.delta)
            }
            balance += event.delta
        }
        return anchor ?? LedgerAnchor(date: medication.createdAt, isRefill: false, inventory: inventory, index: nil, balance: 0)
    }

    private static func asNeededEvaluation(
        medication: Medication,
        supply: Double,
        doseEvents: [DoseEvent],
        now: Date,
        calendar: Calendar
    ) -> Evaluation {
        guard let start = calendar.date(byAdding: .day, value: -30, to: now) else {
            return Evaluation(forecast: unknownAsNeeded(supply: supply))
        }
        let recent = doseEvents.filter {
            $0.medicationID == medication.id &&
            $0.status == .taken &&
            $0.recordedAt >= start &&
            $0.recordedAt <= now
        }
        let quantity = recent.reduce(0) { $0 + $1.doseQuantity }
        guard recent.count >= 3, quantity > 0,
              let earliest = recent.map(\.recordedAt).min() else {
            return Evaluation(forecast: unknownAsNeeded(supply: supply))
        }
        // The rate is measured over the history that exists, not over a fixed thirty
        // days. Three doses taken this week divided by thirty reports four times the
        // runway a person actually has, and of the two directions this estimate can
        // be wrong in, telling someone their supply lasts longer than it does is the
        // one that leaves them without medication.
        let observed = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: earliest),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        let window = min(30, max(1, observed + 1))
        let rate = ForecastBreakdown.AsNeededRate(doseCount: recent.count, quantity: quantity, windowDays: window)
        let dailyAverage = quantity / Double(window)
        let rawDays = supply / dailyAverage
        // The scheduled path stops looking three years out, and so does this one.
        // A count that lasts longer than that is a mistyped one, and `Int(_:)`
        // traps on a value it cannot hold: at launch, in the forecast, and again
        // in the widget, with no way in to correct the number.
        let horizon = calendar.date(byAdding: .year, value: 3, to: now) ?? now
        let horizonDays = Double(calendar.dateComponents([.day], from: now, to: horizon).day ?? 0)
        guard rawDays.isFinite, rawDays <= horizonDays else {
            return Evaluation(forecast: SupplyForecast(
                currentSupply: supply,
                depletionDate: nil,
                daysRemaining: nil,
                confidence: .unknown,
                explanation: "The confirmed supply extends beyond the forecast window."
            ), asNeededRate: rate)
        }
        let days = max(1, Int(rawDays.rounded(.down)))
        let date = calendar.date(byAdding: .day, value: days, to: now)
        return Evaluation(forecast: SupplyForecast(
            currentSupply: supply,
            depletionDate: date,
            daysRemaining: days,
            confidence: .estimated,
            explanation: window == 1
                ? "Estimated from today's as-needed use."
                : "Estimated from the last \(window) days of as-needed use."
        ), asNeededRate: rate)
    }

    private static func unknownAsNeeded(supply: Double) -> SupplyForecast {
        SupplyForecast(
            currentSupply: supply,
            depletionDate: nil,
            daysRemaining: nil,
            confidence: .unknown,
            explanation: "Log at least three as-needed doses to create an estimate."
        )
    }
}
