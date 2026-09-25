import AppIntents
import Foundation
import SwiftData
import WidgetKit

/// Logs the one dose the next-dose widget offers, from the widget itself.
///
/// The same duplicate safety as a reminder action: the dose is matched to its
/// slot by schedule and scheduled time through `ScheduleEngine`, and a slot
/// already logged — from Today, from a reminder, from Health — is left alone.
/// Notifications are replanned by the app the next time it comes forward, as
/// they are after a reminder action.
struct LogNextDoseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Dose as Taken"
    static let description = IntentDescription("Logs the next scheduled dose as taken in Meds Ahead.")
    static let isDiscoverable = false

    @Parameter(title: "Medication")
    var medicationID: String

    @Parameter(title: "Schedule")
    var scheduleID: String

    @Parameter(title: "Scheduled at")
    var scheduledAt: Date

    init() {}

    init(medicationID: UUID, scheduleID: UUID, scheduledAt: Date) {
        self.medicationID = medicationID.uuidString
        self.scheduleID = scheduleID.uuidString
        self.scheduledAt = scheduledAt
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        defer { WidgetCenter.shared.reloadAllTimelines() }
        guard let medicationID = UUID(uuidString: medicationID),
              let scheduleID = UUID(uuidString: scheduleID) else { return .result() }
        // The container must outlive every model read below.
        let container = try WidgetStore.container()
        let context = container.mainContext
        let medications = try context.fetch(FetchDescriptor<Medication>())
        let schedules = try context.fetch(FetchDescriptor<DoseSchedule>())
        let doseEvents = try context.fetch(FetchDescriptor<DoseEvent>())
        // The snapshot's time is only what the widget last drew. The engine is
        // asked again, as a reminder action does, so a slot it no longer
        // produces (a time edited since, an ended schedule, a first day that
        // began after it) is refused instead of logged.
        guard let medication = medications.first(where: { $0.id == medicationID }), !medication.isArchived,
              let schedule = schedules.first(where: { $0.id == scheduleID }), schedule.medicationID == medicationID,
              ScheduleEngine.hasSlot(schedule, at: scheduledAt) else {
            return .result()
        }
        let dose = ScheduledDose(medicationID: medicationID, scheduleID: scheduleID, date: scheduledAt, quantity: schedule.doseQuantity)
        guard ScheduleEngine.loggedStatus(for: dose, in: doseEvents) == nil else { return .result() }
        context.insert(DoseEvent(
            medicationID: medicationID,
            scheduleID: scheduleID,
            scheduledAt: scheduledAt,
            recordedAt: .now,
            doseQuantity: schedule.doseQuantity,
            status: .taken,
            note: DoseEventNote.widget
        ))
        try context.save()
        return .result()
    }
}
