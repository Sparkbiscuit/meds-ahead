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
}

/// Which medications need a refill before a trip, from the forecasts that
/// already exist. Pure arithmetic: a supply that runs out before the return
/// date needs attention before leaving; one whose timing is unknown cannot be
/// vouched for; the rest are fine.
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
            if let depletion = forecast.depletionDate {
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
        let supply = currentSupply(
            medicationID: medication.id,
            inventoryEvents: inventoryEvents,
            doseEvents: doseEvents
        )

        guard supply > 0 else {
            return SupplyForecast(
                currentSupply: 0,
                depletionDate: now,
                daysRemaining: 0,
                confidence: .high,
                explanation: "No confirmed supply remains."
            )
        }

        if medication.isAsNeeded {
            return asNeededForecast(
                medication: medication,
                supply: supply,
                doseEvents: doseEvents,
                now: now,
                calendar: calendar
            )
        }

        guard schedules.contains(where: { $0.medicationID == medication.id }) else {
            return SupplyForecast(
                currentSupply: supply,
                depletionDate: nil,
                daysRemaining: nil,
                confidence: .unknown,
                explanation: "Add a schedule to estimate when this supply will run out."
            )
        }

        let assumed = assumedTaken(
            medication: medication,
            schedules: schedules,
            inventoryEvents: inventoryEvents,
            doseEvents: doseEvents,
            now: now,
            calendar: calendar
        )
        let unlogged = assumed.count == 1
            ? "the 1 scheduled dose since your last count that wasn't logged was taken"
            : "the \(assumed.count) scheduled doses since your last count that weren't logged were taken"

        var remaining = supply - assumed.quantity
        // The ledger still shows medication, but not once the doses nobody logged
        // are taken out of it. Nothing on record says how much is really left, so
        // the answer is a count, not a claim that the supply is gone.
        if assumed.count > 0, remaining <= 0.000_001 {
            return SupplyForecast(
                currentSupply: supply,
                depletionDate: now,
                daysRemaining: 0,
                confidence: .estimated,
                explanation: "If \(unlogged), none of the supply on record is left. Count what is left to update the forecast.",
                assumedDoses: assumed.count,
                needsCount: true
            )
        }

        let horizon = calendar.date(byAdding: .year, value: 3, to: now) ?? now
        let future = ScheduleEngine.doses(
            schedules: schedules,
            medicationID: medication.id,
            from: now,
            through: horizon,
            calendar: calendar
        )

        for dose in future {
            remaining -= dose.quantity
            if remaining <= 0.000_001 {
                return SupplyForecast(
                    currentSupply: supply,
                    depletionDate: dose.date,
                    daysRemaining: max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: dose.date)).day ?? 0),
                    confidence: assumed.count > 0 ? .estimated : .high,
                    explanation: assumed.count > 0 ? "Assumes \(unlogged)." : "Based on the confirmed count and current schedule.",
                    assumedDoses: assumed.count
                )
            }
        }

        return SupplyForecast(
            currentSupply: supply,
            depletionDate: nil,
            daysRemaining: nil,
            confidence: .unknown,
            explanation: "The confirmed supply extends beyond the forecast window.",
            assumedDoses: assumed.count
        )
    }

    /// How far back unlogged doses are assumed taken. A count older than this is
    /// forecast as if it had been taken this long ago: every scheduled dose of
    /// the last 400 days is still weighed, and a forecast that runs on every
    /// screen and in the widget does not walk years of slots to get there.
    static let assumedTakenLookbackDays = 400

    /// The scheduled doses since the last count that nobody logged, assumed
    /// taken. Counting only the doses still to come let every unlogged day push
    /// the run-out date one day later, so a family that stopped logging watched
    /// it slide forever and the refill alert keyed to that date never arrived.
    /// Only a count confirms what is on hand: a refill adds stock but says
    /// nothing about the doses before it, so it does not move the anchor. A
    /// logged dose, taken or skipped, is the person's answer and is never
    /// second-guessed. Nothing is written: the ledger stays what was recorded.
    private static func assumedTaken(
        medication: Medication,
        schedules: [DoseSchedule],
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent],
        now: Date,
        calendar: Calendar
    ) -> (count: Int, quantity: Double) {
        let anchor = inventoryEvents
            .filter { $0.medicationID == medication.id && ($0.reason == .openingCount || $0.reason == .correction) }
            .map(\.date)
            .max() ?? medication.createdAt
        let lookback = calendar.date(byAdding: .day, value: -assumedTakenLookbackDays, to: now) ?? now
        let start = max(anchor, lookback)
        // A slot joins the assumed set only once Today would call it overdue.
        let past = ScheduleEngine.doses(
            schedules: schedules,
            medicationID: medication.id,
            from: start,
            through: now.addingTimeInterval(-ScheduleEngine.dueWindow),
            calendar: calendar
        )
        guard !past.isEmpty else { return (0, 0) }

        // `loggedEvent` walks every log it is handed, once per slot, and a year of
        // slots against a year of logs is too slow for a widget. A log can only
        // account for a slot within a day or so of it, so each slot is handed the
        // logs its schedule has within two days either side, bucketed by absolute
        // day. The question is still asked of `loggedEvent` alone.
        let dayNumber = { (date: Date) in Int((date.timeIntervalSinceReferenceDate / 86_400).rounded(.down)) }
        var logs: [UUID: [Int: [DoseEvent]]] = [:]
        var unscheduled: [DoseEvent] = []
        for event in doseEvents where event.medicationID == medication.id {
            if let scheduleID = event.scheduleID {
                guard let scheduledAt = event.scheduledAt else { continue }
                logs[scheduleID, default: [:]][dayNumber(scheduledAt), default: []].append(event)
            } else if event.status == .taken, event.countsTowardSupply, event.recordedAt >= start, event.recordedAt <= now {
                // A dose logged outside any slot — Take Now with nothing due, or a
                // Health dose no slot was near — is still one of the day's doses.
                // One from before the count is already in that count, and history
                // imported with the medication was never taken from it.
                unscheduled.append(event)
            }
        }

        var unloggedByDay: [Date: [ScheduledDose]] = [:]
        for dose in past {
            let day = dayNumber(dose.date)
            let nearby = logs[dose.scheduleID].map { bySchedule in (day - 2...day + 2).flatMap { bySchedule[$0] ?? [] } } ?? []
            guard ScheduleEngine.loggedEvent(for: dose, in: nearby, now: now, calendar: calendar) == nil else { continue }
            unloggedByDay[calendar.startOfDay(for: dose.date), default: []].append(dose)
        }
        for event in unscheduled.sorted(by: { $0.recordedAt < $1.recordedAt }) {
            let day = calendar.startOfDay(for: event.recordedAt)
            guard var slots = unloggedByDay[day],
                  let nearest = slots.indices.min(by: {
                      abs(slots[$0].date.timeIntervalSince(event.recordedAt)) < abs(slots[$1].date.timeIntervalSince(event.recordedAt))
                  }) else { continue }
            slots.remove(at: nearest)
            unloggedByDay[day] = slots
        }
        let unlogged = unloggedByDay.values.joined()
        return (unlogged.count, unlogged.reduce(0) { $0 + $1.quantity })
    }

    private static func asNeededForecast(
        medication: Medication,
        supply: Double,
        doseEvents: [DoseEvent],
        now: Date,
        calendar: Calendar
    ) -> SupplyForecast {
        guard let start = calendar.date(byAdding: .day, value: -30, to: now) else {
            return unknownAsNeeded(supply: supply)
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
            return unknownAsNeeded(supply: supply)
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
        let dailyAverage = quantity / Double(window)
        let rawDays = supply / dailyAverage
        // The scheduled path stops looking three years out, and so does this one.
        // A count that lasts longer than that is a mistyped one, and `Int(_:)`
        // traps on a value it cannot hold: at launch, in the forecast, and again
        // in the widget, with no way in to correct the number.
        let horizon = calendar.date(byAdding: .year, value: 3, to: now) ?? now
        let horizonDays = Double(calendar.dateComponents([.day], from: now, to: horizon).day ?? 0)
        guard rawDays.isFinite, rawDays <= horizonDays else {
            return SupplyForecast(
                currentSupply: supply,
                depletionDate: nil,
                daysRemaining: nil,
                confidence: .unknown,
                explanation: "The confirmed supply extends beyond the forecast window."
            )
        }
        let days = max(1, Int(rawDays.rounded(.down)))
        let date = calendar.date(byAdding: .day, value: days, to: now)
        return SupplyForecast(
            currentSupply: supply,
            depletionDate: date,
            daysRemaining: days,
            confidence: .estimated,
            explanation: window == 1
                ? "Estimated from today's as-needed use."
                : "Estimated from the last \(window) days of as-needed use."
        )
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
