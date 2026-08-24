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
            let plans = try notificationPlans(in: context)
            await NotificationService.shared.replaceAllNotifications(for: plans)
        } catch {
            context.rollback()
        }
    }

    @MainActor
    private func notificationPlans(in context: ModelContext) throws -> [MedicationNotificationPlan] {
        let medications = try context.fetch(FetchDescriptor<Medication>())
        let schedules = try context.fetch(FetchDescriptor<DoseSchedule>())
        let inventoryEvents = try context.fetch(FetchDescriptor<InventoryEvent>())
        let doseEvents = try context.fetch(FetchDescriptor<DoseEvent>())
        return NotificationPlanBuilder.makeAll(
            medications: medications,
            schedules: schedules,
            inventoryEvents: inventoryEvents,
            doseEvents: doseEvents
        )
    }
}
