import SwiftData
import UIKit
import UserNotifications

final class MedsAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var modelContainer: ModelContainer?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        MedicationNotificationAction.registerCategories(with: center)
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            let destination = MedicationNotificationRoute.destination(
                for: response.notification.request.content.userInfo
            )
            await MainActor.run {
                MedicationNotificationRouter.shared.route(to: destination)
            }
            return
        }

        guard let status = MedicationNotificationAction.status(for: response.actionIdentifier),
              let modelContainer,
              let medicationIDString = response.notification.request.content.userInfo["medicationID"] as? String,
              let scheduleIDString = response.notification.request.content.userInfo["scheduleID"] as? String,
              let medicationID = UUID(uuidString: medicationIDString),
              let scheduleID = UUID(uuidString: scheduleIDString) else {
            return
        }

        let context = modelContainer.mainContext
        do {
            let result = try NotificationDoseRecorder.record(
                status: status,
                medicationID: medicationID,
                scheduleID: scheduleID,
                notificationDate: response.notification.date,
                in: context
            )
            guard result == .recorded else { return }
            let plan = try notificationPlan(for: medicationID, in: context)
            await NotificationService.shared.replaceNotifications(for: plan)
        } catch {
            context.rollback()
        }
    }

    @MainActor
    private func notificationPlan(
        for medicationID: UUID,
        in context: ModelContext
    ) throws -> MedicationNotificationPlan {
        guard let medication = try context.fetch(FetchDescriptor<Medication>())
            .first(where: { $0.id == medicationID }) else {
            throw NotificationActionError.medicationUnavailable
        }

        let schedules = try context.fetch(FetchDescriptor<DoseSchedule>())
            .filter { $0.medicationID == medicationID }
        let inventoryEvents = try context.fetch(FetchDescriptor<InventoryEvent>())
            .filter { $0.medicationID == medicationID }
        let doseEvents = try context.fetch(FetchDescriptor<DoseEvent>())
            .filter { $0.medicationID == medicationID }
        return NotificationPlanBuilder.make(
            medication: medication,
            schedules: schedules,
            inventoryEvents: inventoryEvents,
            doseEvents: doseEvents
        )
    }
}

private enum NotificationActionError: Error {
    case medicationUnavailable
}
