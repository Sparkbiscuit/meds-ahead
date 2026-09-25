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

        let anchor = assumptionAnchor(medication: medication, inventoryEvents: inventoryEvents, doseEvents: doseEvents)
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
        let logs = ScheduleEngine.DoseLogIndex(
            doseEvents: doseEvents.filter {
                $0.medicationID == medication.id && ($0.scheduleID != nil
                    || ($0.status == .taken && $0.countsTowardSupply && $0.recordedAt >= anchor.date && $0.recordedAt <= now))
            },
            medicationID: medication.id,
            calendar: calendar
        )
        let assumed = ScheduleEngine.unloggedDoses(
            schedules: schedules,
            medicationID: medication.id,
            from: anchor.date,
            through: overdueBefore,
            logs: logs,
            now: now,
            calendar: calendar
        )
        let since = anchor.isRefill ? "since your last refill" : "since your last count"
        let unlogged = assumed.count == 1
            ? "the 1 scheduled dose \(since) that wasn't logged was taken"
            : "the \(assumed.count) scheduled doses \(since) that weren't logged were taken"

        var remaining = supply - assumed.reduce(0) { $0 + $1.quantity }
        // The ledger still shows medication, but not once the doses nobody logged
        // are taken out of it. Nothing on record says how much is really left, so
        // the answer is a count, not a claim that the supply is gone.
        if !assumed.isEmpty, remaining <= 0.000_001 {
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

        // The doses still to come start where the assumed ones stop, or at the
        // anchor when it is more recent, since a count already holds everything
        // taken before it. They are worked out a stretch at a time, each twice
        // the last, so a month's supply does not first lay out three years.
        let horizon = calendar.date(byAdding: .year, value: 3, to: now) ?? now
        var stretchStart = max(overdueBefore, min(anchor.date, now))
        var stretchDays = 31
        while stretchStart <= horizon {
            let stretchEnd = min(
                horizon,
                (calendar.date(byAdding: .day, value: stretchDays, to: calendar.startOfDay(for: stretchStart)) ?? horizon).addingTimeInterval(-1)
            )
            let upcoming = ScheduleEngine.unloggedDoses(
                schedules: schedules,
                medicationID: medication.id,
                from: stretchStart,
                through: stretchEnd,
                logs: logs,
                now: now,
                calendar: calendar
            )
            for dose in upcoming where dose.date > overdueBefore {
                remaining -= dose.quantity
                if remaining <= 0.000_001 {
                    return SupplyForecast(
                        currentSupply: supply,
                        depletionDate: dose.date,
                        daysRemaining: max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: dose.date)).day ?? 0),
                        confidence: assumed.isEmpty ? .high : .estimated,
                        explanation: assumed.isEmpty ? "Based on the confirmed count and current schedule." : "Assumes \(unlogged).",
                        assumedDoses: assumed.count
                    )
                }
            }
            guard stretchEnd < horizon else { break }
            stretchStart = stretchEnd.addingTimeInterval(1)
            stretchDays *= 2
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
    private static func assumptionAnchor(
        medication: Medication,
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent]
    ) -> (date: Date, isRefill: Bool) {
        let inventory = inventoryEvents
            .filter { $0.medicationID == medication.id }
            .sorted { $0.date < $1.date }
        let taken = doseEvents
            .compactMap { event -> (date: Date, quantity: Double)? in
                guard event.medicationID == medication.id, event.status == .taken, event.countsTowardSupply else { return nil }
                return (event.recordedAt, event.doseQuantity)
            }
            .sorted { $0.date < $1.date }
        var anchor: (date: Date, isRefill: Bool)?
        var balance = 0.0
        var nextDose = 0
        for event in inventory {
            while nextDose < taken.count, taken[nextDose].date < event.date {
                balance -= taken[nextDose].quantity
                nextDose += 1
            }
            if event.reason == .openingCount || event.reason == .correction {
                anchor = (event.date, false)
            } else if event.reason == .refill, event.delta > 0, balance <= 0.000_001 {
                anchor = (event.date, true)
            }
            balance += event.delta
        }
        return anchor ?? (medication.createdAt, false)
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
