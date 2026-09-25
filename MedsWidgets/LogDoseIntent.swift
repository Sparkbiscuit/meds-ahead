import AppIntents
import Foundation
import SwiftData
import UserNotifications
import WidgetKit

/// Logs the one dose the next-dose widget offers, from the widget itself.
///
/// The same duplicate safety as a reminder action: the dose is matched to its
/// slot by schedule and scheduled time through `ScheduleEngine`, and a slot
/// already logged — from Today, from a reminder, from Health — is left alone.
/// Notifications are replanned by the app the next time it comes forward, as
/// they are after a reminder action; only a follow-up for this dose is
/// withdrawn here, since it would otherwise ask about a dose just logged.
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
        let event = DoseEvent(
            medicationID: medicationID,
            scheduleID: scheduleID,
            scheduledAt: scheduledAt,
            recordedAt: .now,
            doseQuantity: schedule.doseQuantity,
            status: .taken,
            note: DoseEventNote.widget
        )
        context.insert(event)
        try context.save()
        await withdrawFollowUp(at: scheduledAt, schedules: schedules, doseEvents: doseEvents + [event])
        return .result()
    }

    /// By the name the planner gave it, and only once every dose it asks
    /// about is logged: it may stand for other medications due at the same
    /// moment.
    @MainActor
    private func withdrawFollowUp(at slot: Date, schedules: [DoseSchedule], doseEvents: [DoseEvent]) async {
        let identifier = NotificationIdentifiers.followUp(at: slot, calendar: .autoupdatingCurrent)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().first { $0.identifier == identifier }
        let delivered = await center.deliveredNotifications().first { $0.request.identifier == identifier }?.request
        guard let request = pending ?? delivered,
              NotificationIdentifiers.followUpIsAnswered(
                  memberScheduleIDs: NotificationIdentifiers.memberScheduleIDs(in: request.content.userInfo),
                  slot: slot,
                  schedules: schedules,
                  doseEvents: doseEvents
              ) else { return }
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
