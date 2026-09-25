import Foundation
import SwiftData

struct ScheduleDefinition: Equatable {
    let minutesAfterMidnight: Int
    let doseQuantity: Double
    let weekdayMask: Int
}

@MainActor
enum ScheduleReconciler {
    static func reconcile(
        medicationID: UUID,
        definitions: [ScheduleDefinition],
        existing: [DoseSchedule],
        in context: ModelContext,
        startDate: Date = .now
    ) -> [DoseSchedule] {
        var available = existing
            .filter { $0.medicationID == medicationID }
            .sorted { $0.minutesAfterMidnight < $1.minutesAfterMidnight }
        var assignments = Array<DoseSchedule?>(repeating: nil, count: definitions.count)

        // Preserve exact time matches first so changing one time cannot steal the
        // identity of another schedule whose time did not change.
        for index in definitions.indices {
            guard let match = available.firstIndex(where: {
                $0.minutesAfterMidnight == definitions[index].minutesAfterMidnight
            }) else { continue }
            assignments[index] = available.remove(at: match)
        }

        // Reuse remaining schedules for changed times. Dose history references the
        // stable schedule identifier, and `ScheduleEngine.loggedEvent` matches a
        // log to its slot by day rather than by minute, so a simple edit does not
        // make a logged dose look pending again.
        for index in definitions.indices where assignments[index] == nil {
            if available.isEmpty {
                let definition = definitions[index]
                let schedule = DoseSchedule(
                    medicationID: medicationID,
                    minutesAfterMidnight: definition.minutesAfterMidnight,
                    doseQuantity: definition.doseQuantity,
                    weekdayMask: definition.weekdayMask,
                    startDate: startDate
                )
                context.insert(schedule)
                assignments[index] = schedule
            } else {
                assignments[index] = available.removeFirst()
            }
        }

        available.forEach(context.delete)

        for index in definitions.indices {
            guard let schedule = assignments[index] else { continue }
            let definition = definitions[index]
            schedule.minutesAfterMidnight = definition.minutesAfterMidnight
            schedule.doseQuantity = definition.doseQuantity
            schedule.weekdayMask = definition.weekdayMask
        }

        return assignments.compactMap { $0 }
    }

    /// What each schedule held before an edit, taken before `reconcile`
    /// rewrites the same records in place.
    static func snapshot(_ schedules: [DoseSchedule]) -> [UUID: ScheduleDefinition] {
        Dictionary(schedules.map {
            ($0.id, ScheduleDefinition(minutesAfterMidnight: $0.minutesAfterMidnight, doseQuantity: $0.doseQuantity, weekdayMask: $0.weekdayMask))
        }, uniquingKeysWith: { first, _ in first })
    }

    /// Whether an edit leaves only a count able to say what is on hand: the
    /// forecast was assuming unlogged doses were taken, and the edit changed
    /// what the days already past were scheduled to hold, a kept schedule's
    /// amount or weekdays or a schedule dropped. The records are rewritten or
    /// deleted rather than ended, so the forecast weighs every unlogged dose
    /// since the last count at the new schedule: a taper from 4 to 2 halves
    /// what it assumes was taken, and the run-out date moves past the day the
    /// bottle empties. A logged dose keeps its own amount, and a changed or
    /// added time leaves the past's amounts as they were.
    static func asksForCount(assumedDoses: Int, before: [UUID: ScheduleDefinition], after: [DoseSchedule]) -> Bool {
        guard assumedDoses > 0 else { return false }
        let kept = Dictionary(after.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return before.contains { id, old in
            guard let schedule = kept[id] else { return true }
            return schedule.doseQuantity != old.doseQuantity || schedule.weekdayMask != old.weekdayMask
        }
    }
}
