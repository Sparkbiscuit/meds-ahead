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

    var isKnown: Bool { depletionDate != nil }
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
        let consumed = doseEvents
            .filter { $0.medicationID == medicationID && $0.status == .taken }
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

        let horizon = calendar.date(byAdding: .year, value: 3, to: now) ?? now
        let future = ScheduleEngine.doses(
            schedules: schedules,
            medicationID: medication.id,
            from: now,
            through: horizon,
            calendar: calendar
        )

        var remaining = supply
        for dose in future {
            remaining -= dose.quantity
            if remaining <= 0.000_001 {
                return SupplyForecast(
                    currentSupply: supply,
                    depletionDate: dose.date,
                    daysRemaining: max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: dose.date)).day ?? 0),
                    confidence: .high,
                    explanation: "Based on the confirmed count and current schedule."
                )
            }
        }

        return SupplyForecast(
            currentSupply: supply,
            depletionDate: nil,
            daysRemaining: nil,
            confidence: .unknown,
            explanation: "The confirmed supply extends beyond the forecast window."
        )
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
