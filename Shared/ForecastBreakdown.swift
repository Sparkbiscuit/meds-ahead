import Foundation

/// "Why this date?": the steps from the ledger's last known number to the
/// forecast, as plain values a screen can phrase and localise. It is built
/// from the forecast's own evaluation, so the conclusion it explains is the
/// one every other surface shows, not a second calculation beside it.
struct ForecastBreakdown: Equatable {
    /// Where the walk starts: the last moment the number on record was known
    /// to be what was on hand, the same moment the forecast starts assuming
    /// unlogged doses from.
    struct Anchor: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            /// The count entered when the medication was added.
            case openingCount
            /// A count made since, recorded as a correction.
            case count
            /// A refill onto a ledger that showed nothing, which says what is
            /// on hand as a count does.
            case refillOntoEmpty
            /// Nothing counted yet: the walk starts from nothing on the day
            /// the medication was added.
            case added
        }

        let kind: Kind
        let date: Date
        /// The ledger's number right after the event.
        let balance: Double
    }

    /// How many events, and the quantity they add up to.
    struct Tally: Equatable, Sendable {
        let count: Int
        let quantity: Double
    }

    /// Changes since the anchor that are neither refills nor doses: lost,
    /// discarded, returned. `quantity` is their total as the ledger adds it,
    /// so a loss is negative.
    struct Adjustment: Equatable, Sendable {
        let reason: InventoryReason
        let count: Int
        let quantity: Double
    }

    /// The as-needed doses the run-out date is divided out from.
    struct AsNeededRate: Equatable, Sendable {
        let doseCount: Int
        let quantity: Double
        /// The days the rate is measured over: the history that exists, at
        /// most thirty.
        let windowDays: Int

        var perDay: Double { quantity / Double(windowDays) }
    }

    enum Use: Equatable, Sendable {
        /// Every day of the week holds the same amount.
        case daily(quantity: Double)
        /// The weekdays differ: the week's total.
        case weekly(quantity: Double)
        case asNeeded(AsNeededRate)

        var perDay: Double {
            switch self {
            case let .daily(quantity): quantity
            case let .weekly(quantity): quantity / 7
            case let .asNeeded(rate): rate.perDay
            }
        }
    }

    /// What the forecast concluded, read off the forecast itself.
    enum Conclusion: Equatable, Sendable {
        case runsOut(date: Date, daysRemaining: Int)
        case courseCovered(end: Date, leftover: Double)
        case courseFinished(end: Date)
        case countNeeded
        case outOfSupply
        /// No schedule, too little as-needed history, or a supply that
        /// outlasts the forecast window; the explanation says which.
        case unknown

        init(_ forecast: SupplyForecast) {
            if forecast.courseFinished, let end = forecast.courseEndDate {
                self = .courseFinished(end: end)
            } else if forecast.courseCovered, let end = forecast.courseEndDate {
                self = .courseCovered(end: end, leftover: forecast.leftoverAtCourseEnd ?? 0)
            } else if forecast.needsCount {
                self = .countNeeded
            } else if forecast.currentSupply <= 0 {
                self = .outOfSupply
            } else if let date = forecast.depletionDate, let days = forecast.daysRemaining {
                self = .runsOut(date: date, daysRemaining: days)
            } else {
                self = .unknown
            }
        }
    }

    /// The low-supply alert, as the notification planner writes it: 09:00,
    /// `leadDays` before the run-out day.
    struct Alert: Equatable, Sendable {
        enum State: Equatable, Sendable {
            /// Still ahead, and will be announced by this medication's rule.
            /// The planner's request cap, which only a regimen with dozens of
            /// dose times reaches, drops the farthest refill alerts first,
            /// and this cannot see that from one medication; Today and Supply
            /// still carry the warning from its moment on.
            case planned
            /// Its moment has passed. It is never announced late; Today and
            /// Supply carry the warning instead.
            case passed
            /// A refill in progress stands in for it, per `SupplyAttention`.
            /// The refill check asks whether it arrived at `checkAt`, when
            /// that is still ahead.
            case pausedByRefill(checkAt: Date?)
            /// Refill reminders are off for this medication, or it is archived.
            case off
        }

        let date: Date
        /// The days ahead of the run-out day it comes.
        let leadDays: Int
        /// The lead the person chose; shorter than `leadDays` when no refills
        /// are left and the prescriber's lead applies.
        let chosenLeadDays: Int
        /// No refills are left, so the alert asks for a new prescription.
        let needsPrescriber: Bool
        let state: State
    }

    /// One line of the breakdown, in the order it is read.
    enum Step: Equatable {
        case anchor(Anchor)
        case refills(Tally)
        case adjustment(Adjustment)
        /// Doses logged as taken since the anchor that came out of the supply,
        /// with how many of them Apple Health logged.
        case taken(Tally, fromHealth: Int)
        /// The ledger's number: the anchor, plus everything since. Negative
        /// when more was logged than was on record; the forecast reads that
        /// as none.
        case onRecord(Double)
        /// Scheduled doses nobody logged, which the forecast assumes were
        /// taken, and what that leaves.
        case assumed(Tally, sinceRefill: Bool, leaves: Double)
        case use(Use)
        case courseEnd(Date)
        case conclusion(Conclusion, explanation: String)
        case alert(Alert)
    }

    let form: MedicationForm
    let anchor: Anchor
    let refills: Tally
    let adjustments: [Adjustment]
    let taken: Tally
    let takenFromHealth: Int
    let ledgerBalance: Double
    let assumed: Tally
    let use: Use?
    let courseEnd: Date?
    /// The forecast this explains, exactly as `ForecastEngine.forecast`
    /// returns it for the same inputs.
    let forecast: SupplyForecast
    let alert: Alert?

    var conclusion: Conclusion { Conclusion(forecast) }

    var steps: [Step] {
        var steps: [Step] = [.anchor(anchor)]
        if refills.count > 0 { steps.append(.refills(refills)) }
        steps += adjustments.map(Step.adjustment)
        steps.append(.taken(taken, fromHealth: takenFromHealth))
        steps.append(.onRecord(ledgerBalance))
        if assumed.count > 0 {
            steps.append(.assumed(assumed, sinceRefill: forecast.assumedSinceRefill, leaves: forecast.currentSupply - assumed.quantity))
        }
        if let use { steps.append(.use(use)) }
        if let courseEnd { steps.append(.courseEnd(courseEnd)) }
        steps.append(.conclusion(conclusion, explanation: forecast.explanation))
        if let alert { steps.append(.alert(alert)) }
        return steps
    }

    /// The steps in plain English, one line each, for a screen that has not
    /// phrased them itself and for the tests.
    func lines(calendar: Calendar = .autoupdatingCurrent) -> [String] {
        steps.map { line(for: $0, calendar: calendar) }
    }

    private func line(for step: Step, calendar: Calendar) -> String {
        let day = { (date: Date) in ForecastEngine.dayText(date, calendar: calendar) }
        let moment = { (date: Date) in
            date.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day().hour().minute())
        }
        let amount = { (quantity: Double) in form.quantityText(quantity) }
        switch step {
        case let .anchor(anchor):
            switch anchor.kind {
            case .openingCount: return "Started with \(amount(anchor.balance)) on \(day(anchor.date))."
            case .count: return "Counted \(amount(anchor.balance)) on \(day(anchor.date))."
            case .refillOntoEmpty: return "Refilled on \(day(anchor.date)), when none was on record: \(amount(anchor.balance))."
            case .added: return "Nothing counted since this was added on \(day(anchor.date))."
            }
        case let .refills(tally):
            return "\(tally.count.counted("refill", plural: "refills")) since then: \(signed(tally.quantity))."
        case let .adjustment(adjustment):
            return "\(adjustment.reason.displayName) since then: \(signed(adjustment.quantity))."
        case let .taken(tally, fromHealth):
            guard tally.count > 0 else { return "No doses logged as taken since then." }
            let health = fromHealth > 0 ? ", \(fromHealth) of them from Apple Health" : ""
            return "\(tally.count.counted("dose", plural: "doses")) logged as taken since then\(health): \(signed(-tally.quantity))."
        case let .onRecord(balance):
            return balance < -0.000_001
                ? "On record: none. More was logged as taken than was on record."
                : "On record: \(amount(max(0, balance)))."
        case let .assumed(tally, sinceRefill, leaves):
            let since = sinceRefill ? "since the last refill" : "since the last count"
            let were = tally.count == 1 ? "wasn't logged" : "weren't logged"
            let taken = tally.count == 1 ? "If it was taken" : "If they were taken"
            let result = leaves > 0.000_001 ? "that leaves \(amount(leaves))" : "none of the supply on record is left"
            return "\(tally.count.counted("scheduled dose", plural: "scheduled doses")) \(since) \(were) (\(amount(tally.quantity))). \(taken), \(result)."
        case let .use(use):
            switch use {
            case let .daily(quantity):
                return "The schedule uses \(amount(quantity)) a day."
            case let .weekly(quantity):
                return "The schedule uses \(amount(quantity)) a week, about \(amount(use.perDay)) a day."
            case let .asNeeded(rate):
                return rate.windowDays == 1
                    ? "As-needed use today: \(amount(rate.quantity)) in \(rate.doseCount.counted("dose", plural: "doses"))."
                    : "As-needed use: \(amount(rate.quantity)) over the last \(rate.windowDays) days, about \(amount(rate.perDay)) a day."
            }
        case let .courseEnd(end):
            return "The course's last day is \(day(end))."
        case let .conclusion(conclusion, explanation):
            switch conclusion {
            case let .runsOut(date, _): return "Runs out around \(day(date)). \(explanation)"
            case .countNeeded: return "Count needed. \(explanation)"
            case .unknown: return "Timing unknown. \(explanation)"
            case .courseCovered, .courseFinished, .outOfSupply: return explanation
            }
        case let .alert(alert):
            let ahead = "\(alert.leadDays.dayCountText) before the run-out"
            let prescriber = !alert.needsPrescriber ? ""
                : alert.leadDays > alert.chosenLeadDays
                    ? " No refills are left, so it comes at least \(SupplyAttention.prescriberLeadDays) days ahead, for a new prescription."
                    : " No refills are left, so it asks for a new prescription."
            switch alert.state {
            case .planned:
                return "The low-supply alert comes \(moment(alert.date)), \(ahead).\(prescriber)"
            case .passed:
                return "The low-supply alert was due \(moment(alert.date)), \(ahead).\(prescriber)"
            case let .pausedByRefill(checkAt):
                let check = checkAt.map { " Meds Ahead asks whether it has arrived \(moment($0))." } ?? ""
                return "A refill in progress stands in for the low-supply alert due \(moment(alert.date)).\(check)"
            case .off:
                return "Refill reminders are off for this medication, so no low-supply alert is sent."
            }
        }
    }

    private func signed(_ quantity: Double) -> String {
        quantity < 0 ? "−\(form.quantityText(-quantity))" : "+\(form.quantityText(quantity))"
    }
}

extension ForecastEngine {
    /// "Why this date?" for one medication: the same inputs as `forecast`,
    /// and the same evaluation, laid out as the steps that reach it.
    static func breakdown(
        medication: Medication,
        schedules: [DoseSchedule],
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> ForecastBreakdown {
        let evaluation = evaluation(
            medication: medication,
            schedules: schedules,
            inventoryEvents: inventoryEvents,
            doseEvents: doseEvents,
            now: now,
            calendar: calendar
        )
        let forecast = evaluation.forecast
        let ledger = ledgerAnchor(medication: medication, inventoryEvents: inventoryEvents, doseEvents: doseEvents)

        // Everything up to the anchor is in its balance and everything after
        // it is listed, so the lines add up to the ledger's number exactly.
        let kind: ForecastBreakdown.Anchor.Kind
        let since: ArraySlice<InventoryEvent>
        if let index = ledger.index {
            switch ledger.inventory[index].reason {
            case .openingCount: kind = .openingCount
            case .refill: kind = .refillOntoEmpty
            default: kind = .count
            }
            since = ledger.inventory[(index + 1)...]
        } else {
            kind = .added
            since = ledger.inventory[...]
        }
        let refillEvents = since.filter { $0.reason == .refill }
        let adjustments = InventoryReason.allCases.filter { $0 != .refill }.compactMap { reason -> ForecastBreakdown.Adjustment? in
            let events = since.filter { $0.reason == reason }
            guard !events.isEmpty else { return nil }
            return ForecastBreakdown.Adjustment(reason: reason, count: events.count, quantity: events.reduce(0) { $0 + $1.delta })
        }
        let takenSince = doseEvents.filter {
            $0.medicationID == medication.id && $0.status == .taken && $0.countsTowardSupply
                && (ledger.index == nil || $0.recordedAt >= ledger.date)
        }

        return ForecastBreakdown(
            form: medication.form,
            anchor: ForecastBreakdown.Anchor(kind: kind, date: ledger.date, balance: ledger.balance),
            refills: ForecastBreakdown.Tally(count: refillEvents.count, quantity: refillEvents.reduce(0) { $0 + $1.delta }),
            adjustments: adjustments,
            taken: ForecastBreakdown.Tally(count: takenSince.count, quantity: takenSince.reduce(0) { $0 + $1.doseQuantity }),
            takenFromHealth: takenSince.filter { $0.healthSampleID != nil }.count,
            ledgerBalance: rawSupplyBalance(medicationID: medication.id, inventoryEvents: inventoryEvents, doseEvents: doseEvents),
            assumed: ForecastBreakdown.Tally(count: forecast.assumedDoses, quantity: evaluation.assumedQuantity),
            use: medication.isAsNeeded
                ? evaluation.asNeededRate.map(ForecastBreakdown.Use.asNeeded)
                : scheduleUse(schedules: schedules, medicationID: medication.id, now: now, calendar: calendar),
            courseEnd: forecast.courseEndDate,
            forecast: forecast,
            alert: lowSupplyAlert(medication: medication, forecast: forecast, now: now, calendar: calendar)
        )
    }

    /// What the schedule uses: one amount when every weekday holds the same,
    /// or the week's total when they differ. A schedule whose last day has
    /// passed uses nothing any more: counting it would overstate the use
    /// beside a date the forecast worked out without it, and a finished
    /// course would still read as using its old amount every day.
    private static func scheduleUse(schedules: [DoseSchedule], medicationID: UUID, now: Date, calendar: Calendar) -> ForecastBreakdown.Use? {
        let today = calendar.startOfDay(for: now)
        let own = schedules.filter {
            $0.medicationID == medicationID && ($0.endDate.map { calendar.startOfDay(for: $0) >= today } ?? true)
        }
        guard !own.isEmpty else { return nil }
        let byWeekday = (0..<7).map { weekday in
            own.filter { $0.weekdayMask & (1 << weekday) != 0 }.reduce(0) { $0 + $1.doseQuantity }
        }
        return byWeekday.allSatisfy({ $0 == byWeekday[0] })
            ? .daily(quantity: byWeekday[0])
            : .weekly(quantity: byWeekday.reduce(0, +))
    }

    /// The low-supply alert for this forecast, worked out as
    /// `NotificationPlanner` plans it: that planner is the app's alone and
    /// this file is the widget's too, so the rule is restated here over the
    /// same `SupplyAttention` values, and a test holds the two together.
    private static func lowSupplyAlert(
        medication: Medication,
        forecast: SupplyForecast,
        now: Date,
        calendar: Calendar
    ) -> ForecastBreakdown.Alert? {
        // A count needed has no run-out day to warn ahead of: its today is
        // where the assumptions ran out. Nothing on hand is its own warning,
        // and its run-out day, today, leaves no lead the planner could use.
        guard !forecast.needsCount, forecast.currentSupply > 0, let depletion = forecast.depletionDate else { return nil }
        let depletionDay = calendar.startOfDay(for: depletion)
        let leadDays = max(1, SupplyAttention.leadDays(refillLeadDays: medication.refillLeadDays, refillsRemaining: medication.refillsRemaining))
        let leadDay = calendar.date(byAdding: .day, value: -leadDays, to: depletionDay) ?? depletionDay
        let date = calendar.date(bySettingHour: SupplyAttention.alertHour, minute: 0, second: 0, of: leadDay) ?? leadDay

        let state: ForecastBreakdown.Alert.State
        if medication.isArchived || !medication.refillRemindersEnabled {
            state = .off
        } else if date <= now {
            state = .passed
        } else {
            let inProgress = medication.refillStatus != .none
            let check = inProgress
                ? SupplyAttention.refillCheckMoment(refillStatusDate: medication.refillStatusDate, depletionDate: depletion, calendar: calendar)
                    .flatMap { $0 > now ? $0 : nil }
                : nil
            let atAlert = SupplyAttention(
                daysRemaining: max(0, SupplyAttention.days(from: date, to: depletionDay, calendar: calendar)),
                onHand: forecast.currentSupply > 0 && depletionDay >= calendar.startOfDay(for: date),
                needsCount: false,
                refillLeadDays: medication.refillLeadDays,
                refillsRemaining: medication.refillsRemaining,
                refillInProgress: inProgress,
                daysSinceRefillDate: medication.refillStatusDate.map { SupplyAttention.days(from: $0, to: date, calendar: calendar) }
            )
            // On the morning the refill check comes, it says it instead.
            if atAlert.refillPauseHolds || check.map({ calendar.startOfDay(for: $0) == leadDay }) == true {
                state = .pausedByRefill(checkAt: check)
            } else {
                state = .planned
            }
        }
        return ForecastBreakdown.Alert(
            date: date,
            leadDays: leadDays,
            chosenLeadDays: medication.refillLeadDays,
            needsPrescriber: medication.refillsRemaining == 0,
            state: state
        )
    }
}
