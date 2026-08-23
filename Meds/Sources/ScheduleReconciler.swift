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
        // stable schedule identifier, so a simple edit does not make a logged dose
        // look pending again.
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
}
