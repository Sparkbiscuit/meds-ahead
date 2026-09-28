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
        let events = try doseEvents(for: dose.medicationID, in: context)
        return ScheduleEngine.loggedEvent(for: dose, in: events, now: now, calendar: calendar) != nil
    }

    /// The dose a Take Now tap claims, chosen from what the store holds. The
    /// widget logs the earliest dose still due, which is the one stale arrays
    /// would offer; a tap then belongs to the next one still due, as it would
    /// had the screen caught up, and not to nothing.
    static func actionableDose(
        schedules: [DoseSchedule],
        medicationID: UUID,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> ScheduledDose? {
        ScheduleEngine.actionableDose(
            schedules: schedules,
            medicationID: medicationID,
            doseEvents: try doseEvents(for: medicationID, in: context),
            now: now,
            calendar: calendar
        )
    }

    private static func doseEvents(for medicationID: UUID, in context: ModelContext) throws -> [DoseEvent] {
        try context.fetch(FetchDescriptor<DoseEvent>(predicate: #Predicate { $0.medicationID == medicationID }))
    }
}
