import Foundation

/// What the next-dose widget shows, worked out over plain values so the
/// widget's decisions can be tested without WidgetKit.
struct NextDoseSnapshot: Equatable, Sendable {
    struct Item: Equatable, Sendable, Identifiable {
        let medicationID: UUID
        let scheduleID: UUID
        let displayName: String
        let quantityText: String
        let accentIndex: Int

        var id: UUID { medicationID }
    }

    enum State: Equatable, Sendable {
        case noMedications
        case nothingScheduled
        case allLogged(count: Int)
        /// The earliest unlogged dose time of the day and everything due at it,
        /// whether that time is still ahead or already behind.
        case next(time: Date, items: [Item])
    }

    let state: State
    let now: Date

    /// The one dose a single tap may log: exactly one medication at the next
    /// time, and that time due or overdue. Several medications at one time are
    /// never logged by one tap, for the same reason a grouped reminder offers
    /// no Taken action: one action cannot safely stand for several doses.
    var actionable: Item? {
        guard case let .next(time, items) = state, items.count == 1,
              ScheduleEngine.timingState(for: time, now: now) != .upcoming else { return nil }
        return items[0]
    }

    var isOverdue: Bool {
        guard case let .next(time, _) = state else { return false }
        return ScheduleEngine.timingState(for: time, now: now) == .overdue
    }

    static func make(
        medications: [Medication],
        schedules: [DoseSchedule],
        doseEvents: [DoseEvent],
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> NextDoseSnapshot {
        let active = medications.filter { !$0.isArchived }
        guard !active.isEmpty else { return NextDoseSnapshot(state: .noMedications, now: now) }
        var todays: [(Medication, ScheduledDose)] = []
        for medication in active {
            for dose in ScheduleEngine.doses(schedules: schedules, medicationID: medication.id, onDayOf: now, calendar: calendar) {
                todays.append((medication, dose))
            }
        }
        guard !todays.isEmpty else { return NextDoseSnapshot(state: .nothingScheduled, now: now) }
        let unlogged = todays.filter { ScheduleEngine.loggedStatus(for: $0.1, in: doseEvents) == nil }
        guard let first = unlogged.min(by: { $0.1.date < $1.1.date }) else {
            return NextDoseSnapshot(state: .allLogged(count: todays.count), now: now)
        }
        let time = first.1.date
        let items = unlogged
            .filter { abs($0.1.date.timeIntervalSince(time)) < 60 }
            .sorted { $0.0.displayName.localizedCaseInsensitiveCompare($1.0.displayName) == .orderedAscending }
            .map { medication, dose in
                Item(
                    medicationID: medication.id,
                    scheduleID: dose.scheduleID,
                    displayName: medication.displayName,
                    quantityText: "\(dose.quantity.medicationQuantityText) \(medication.form.unitName)\(dose.quantity == 1 ? "" : "s")",
                    accentIndex: medication.accentIndex
                )
            }
        return NextDoseSnapshot(state: .next(time: time, items: items), now: now)
    }

    /// The moments today at which the widget's answer changes on its own:
    /// each unlogged dose time still ahead, the edges of its due window, and
    /// midnight. Everything else changes because the app changed the ledger,
    /// which reloads the widgets directly.
    static func changeTimes(
        medications: [Medication],
        schedules: [DoseSchedule],
        doseEvents: [DoseEvent],
        now: Date,
        dueWindow: TimeInterval = ScheduleEngine.dueWindow,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Date] {
        var times: Set<Date> = []
        for medication in medications where !medication.isArchived {
            for dose in ScheduleEngine.doses(schedules: schedules, medicationID: medication.id, onDayOf: now, calendar: calendar)
                where ScheduleEngine.loggedStatus(for: dose, in: doseEvents) == nil {
                for moment in [dose.date.addingTimeInterval(-dueWindow), dose.date, dose.date.addingTimeInterval(dueWindow + 1)]
                    where moment > now {
                    times.insert(moment)
                }
            }
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            times.insert(tomorrow)
        }
        return times.sorted()
    }
}

/// What the runs-out-next widget shows: the medications in the order their
/// supply runs out, soonest first, with the ones nobody can forecast last.
struct RunsOutSnapshot: Equatable, Sendable {
    struct Item: Equatable, Sendable, Identifiable {
        let medicationID: UUID
        let displayName: String
        let daysRemaining: Int?
        let depletionDate: Date?
        let refillLeadDays: Int
        let refillsRemaining: Int?
        let refillInProgress: Bool
        /// Counted when the snapshot is made, as `daysRemaining` is.
        let daysSinceRefillDate: Int?
        let onHand: Bool
        /// The forecast's assumptions used up the ledger; see `SupplyForecast`.
        let needsCount: Bool
        let accentIndex: Int

        var id: UUID { medicationID }

        /// How urgent the widget shows a medication to be; the widget picks the
        /// colour for each.
        enum Tone: Equatable, Sendable {
            case unknown
            case steady
            case attention
            case out
        }

        var attention: SupplyAttention {
            SupplyAttention(
                daysRemaining: daysRemaining,
                onHand: onHand,
                needsCount: needsCount,
                refillLeadDays: refillLeadDays,
                refillsRemaining: refillsRemaining,
                refillInProgress: refillInProgress,
                daysSinceRefillDate: daysSinceRefillDate
            )
        }

        /// Low, and no refill in progress that can still answer for it.
        var needsAttention: Bool { attention.needsAttention }

        /// A count needed is never out: its zero days are where the assumed
        /// doses ran out, and the ledger still shows medication.
        private var isOut: Bool { !needsCount && (!onHand || (daysRemaining ?? 1) <= 0) }

        /// The day count the widget may print. None while a count is needed,
        /// for the same reason it is never out.
        var shownDaysRemaining: Int? { needsCount ? nil : daysRemaining }

        var tone: Tone {
            if isOut { return .out }
            if needsAttention { return .attention }
            return daysRemaining == nil ? .unknown : .steady
        }

        /// A refill on its way is said only while it can still answer for the
        /// supply; at zero, or once it runs late, the count speaks instead.
        var line: String {
            if needsCount { return "Count needed" }
            if isOut { return "Out of supply" }
            if attention.refillPauseHolds { return "Refill on its way" }
            guard let daysRemaining else { return "Timing unknown" }
            return daysRemaining == 1 ? "About 1 day left" : "About \(daysRemaining) days left"
        }
    }

    let items: [Item]
    let now: Date

    var soonest: Item? { items.first }

    static func make(
        medications: [Medication],
        schedules: [DoseSchedule],
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent],
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> RunsOutSnapshot {
        let items = medications
            .filter { !$0.isArchived }
            .map { medication -> Item in
                let forecast = ForecastEngine.forecast(
                    medication: medication,
                    schedules: schedules,
                    inventoryEvents: inventoryEvents,
                    doseEvents: doseEvents,
                    now: now,
                    calendar: calendar
                )
                let attention = SupplyAttention(medication: medication, forecast: forecast, now: now, calendar: calendar)
                return Item(
                    medicationID: medication.id,
                    displayName: medication.displayName,
                    daysRemaining: forecast.daysRemaining,
                    depletionDate: forecast.depletionDate,
                    refillLeadDays: medication.refillLeadDays,
                    refillsRemaining: medication.refillsRemaining,
                    refillInProgress: attention.refillInProgress,
                    daysSinceRefillDate: attention.daysSinceRefillDate,
                    onHand: attention.onHand,
                    needsCount: attention.needsCount,
                    accentIndex: medication.accentIndex
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.daysRemaining, rhs.daysRemaining) {
                case let (.some(a), .some(b)) where a != b: return a < b
                case (.some, .none): return true
                case (.none, .some): return false
                default: return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
            }
        return RunsOutSnapshot(items: items, now: now)
    }
}
