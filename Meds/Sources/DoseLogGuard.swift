import Foundation
import SwiftData

/// Whether a scheduled dose is already logged, asked of the store rather than of
/// a screen's `@Query` arrays, just before a log is written.
///
/// The widget's Taken button saves from its own process. Nothing guarantees a
/// running app's queries have merged that write when the person next taps Taken
/// on Today or Take Now on a medication, and those arrays alone would call the
/// dose unlogged and spend the supply a second time. A fetch goes to the store
/// and sees what another process has committed. The reminder actions and the
/// widget already ask the store this way; this is the same question for the
/// app's own buttons. Slot identity stays with `ScheduleEngine`.
enum DoseLogGuard {
    static func isLogged(
        _ dose: ScheduledDose,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> Bool {
        let medicationID = dose.medicationID
        let events = try context.fetch(
            FetchDescriptor<DoseEvent>(predicate: #Predicate { $0.medicationID == medicationID })
        )
        return ScheduleEngine.loggedEvent(for: dose, in: events, now: now, calendar: calendar) != nil
    }
}
