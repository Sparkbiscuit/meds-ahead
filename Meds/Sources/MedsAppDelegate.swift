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
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            Self.clearUITestingDefaults(in: .standard)
        }
#endif
        return true
    }

#if DEBUG
    /// UI tests check where the reminder choices start, and the simulator
    /// keeps UserDefaults between runs: a run stopped after turning one on
    /// must not start every later run, and plan every later test's
    /// reminders, from that choice. Today's set-aside cards and the tapped
    /// count check are cleared for the same reason: a card one run set aside
    /// must not hide it from the next.
    static let uiTestingDefaultsKeys = [
        NotificationPlanOptions.followUpRemindersKey,
        NotificationPlanOptions.weeklyCountCheckKey,
        CountCheckPolicy.plannedMomentKey,
        CountCheckPolicy.askedMomentKey,
        FinishedCourseNotice.setAsideKey,
        QuickCountPrompt.setAsideKey,
        QuickCountPrompt.tapKey
    ]

    static func clearUITestingDefaults(in defaults: UserDefaults) {
        for key in uiTestingDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
    }
#endif

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
            let destination = MedicationNotificationRoute.follow(
                response.notification.request.content.userInfo
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
            let answered = try NotificationDoseRecorder.respond(
                status: status,
                medicationID: medicationID,
                scheduleID: scheduleID,
                notificationDate: response.notification.date,
                slotDay: NotificationIdentifiers.slotDay(in: response.notification.request.content.userInfo, calendar: .autoupdatingCurrent),
                in: context
            )
            await NotificationService.shared.replaceAllNotifications(for: answered.plans)
        } catch {
            context.rollback()
        }
    }
}
