import Foundation
import SwiftData
import UserNotifications

enum MedicationNotificationAction {
    static let doseCategoryIdentifier = "MEDS_DOSE_REMINDER"
    static let markTakenIdentifier = "MEDS_MARK_TAKEN"
    static let markSkippedIdentifier = "MEDS_MARK_SKIPPED"

    static func registerCategories(with center: UNUserNotificationCenter = .current()) {
        let taken = UNNotificationAction(
            identifier: markTakenIdentifier,
            title: "Taken",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "checkmark.circle.fill")
        )
        let skipped = UNNotificationAction(
            identifier: markSkippedIdentifier,
            title: "Skip",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "forward.end.circle.fill")
        )
        let category = UNNotificationCategory(
            identifier: doseCategoryIdentifier,
            actions: [taken, skipped],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    static func status(for responseIdentifier: String) -> DoseEventStatus? {
        switch responseIdentifier {
        case markTakenIdentifier: .taken
        case markSkippedIdentifier: .skipped
        default: nil
        }
    }
}

enum MedicationNotificationRoute {
    static func destination(for userInfo: [AnyHashable: Any]) -> AppTab {
        userInfo["notificationKind"] as? String == "refill" ? .supply : .today
    }
}

extension Notification.Name {
    static let medicationNotificationRouteDidChange = Notification.Name(
        "medicationNotificationRouteDidChange"
    )
}

@MainActor
final class MedicationNotificationRouter {
    static let shared = MedicationNotificationRouter()

    private(set) var pendingDestination: AppTab?

    func route(to destination: AppTab) {
        pendingDestination = destination
        NotificationCenter.default.post(name: .medicationNotificationRouteDidChange, object: nil)
    }

    func consumeDestination() -> AppTab? {
        defer { pendingDestination = nil }
        return pendingDestination
    }
}

enum NotificationDoseRecordingResult: Equatable {
    case recorded
    case alreadyRecorded
    case missingContext
}

@MainActor
enum NotificationDoseRecorder {
    /// `slotDate` is the scheduled moment a dated reminder or a follow-up
    /// names. It decides the day when present: a follow-up for a 23:45 dose
    /// is delivered after midnight, and the delivery's day would be the next
    /// day's dose. The engine still says which dose that day is.
    static func record(
        status: DoseEventStatus,
        medicationID: UUID,
        scheduleID: UUID,
        notificationDate: Date,
        slotDate: Date? = nil,
        in context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> NotificationDoseRecordingResult {
        guard let medication = try context.fetch(FetchDescriptor<Medication>())
            .first(where: { $0.id == medicationID }),
              !medication.isArchived,
              let schedule = try context.fetch(FetchDescriptor<DoseSchedule>())
                .first(where: { $0.id == scheduleID }),
              schedule.medicationID == medicationID,
              let scheduledAt = ScheduleEngine.scheduledDate(
                for: schedule,
                on: slotDate ?? notificationDate,
                calendar: calendar
              ) else {
            return .missingContext
        }

        let dose = ScheduledDose(
            medicationID: medicationID,
            scheduleID: scheduleID,
            date: scheduledAt,
            quantity: schedule.doseQuantity
        )
        let events = try context.fetch(FetchDescriptor<DoseEvent>()).filter { $0.medicationID == medicationID }
        guard ScheduleEngine.loggedStatus(for: dose, in: events, calendar: calendar) == nil else {
            return .alreadyRecorded
        }

        context.insert(
            DoseEvent(
                medicationID: medicationID,
                scheduleID: scheduleID,
                scheduledAt: scheduledAt,
                recordedAt: .now,
                doseQuantity: schedule.doseQuantity,
                status: status,
                note: DoseEventNote.reminder
            )
        )
        try context.save()
        return .recorded
    }
}
