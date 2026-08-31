import Foundation
import UserNotifications

actor NotificationService {
    static let shared = NotificationService()

    func replaceAllNotifications(
        for plans: [MedicationNotificationPlan],
        requestAuthorization: Bool = false
    ) async {
        let center = UNUserNotificationCenter.current()
        let planned = NotificationPlanner.notifications(for: plans)
        let plannedIdentifiers = Set(planned.map(\.identifier))
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let managedPending = pending.map(\.identifier).filter { $0.hasPrefix("meds.") }
        let managedDelivered = delivered.map { $0.request.identifier }.filter { $0.hasPrefix("meds.") }
        center.removePendingNotificationRequests(
            withIdentifiers: managedPending.filter { !plannedIdentifiers.contains($0) }
        )
        center.removeDeliveredNotifications(
            withIdentifiers: managedDelivered.filter { !plannedIdentifiers.contains($0) }
        )

        // The status is read and reported even when nothing is planned, so Settings
        // and the Today banner describe the current permission rather than the one
        // that happened to apply the last time a medication existed.
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined, requestAuthorization, !planned.isEmpty {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        let authorized = status == .authorized || status == .provisional || status == .ephemeral

        guard authorized, !planned.isEmpty else {
            await NotificationHealth.shared.record(
                authorization: status,
                planned: planned.count,
                failed: 0
            )
            return
        }

        var failed = 0
        let deliveredIdentifiers = Set(managedDelivered)
        for item in planned {
            if item.kind == .refill, deliveredIdentifiers.contains(item.identifier) {
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            // Stack dose reminders together (and refill alerts together) in
            // Notification Center instead of interleaving with everything else.
            content.threadIdentifier = item.kind == .dose ? "meds.dose" : "meds.refill"
            // Dose reminders may break through Focus modes (the entitlement in
            // Meds.entitlements grants this; the person still controls it per-app
            // in Settings). Refill alerts are plan-ahead notices, not moments.
            content.interruptionLevel = item.kind == .dose ? .timeSensitive : .active
            var userInfo: [String: String] = [:]
            if let medicationID = item.medicationID {
                userInfo["medicationID"] = medicationID.uuidString
            }
            if let scheduleID = item.scheduleID {
                userInfo["scheduleID"] = scheduleID.uuidString
            }
            userInfo["notificationKind"] = item.kind == .dose ? "dose" : "refill"
            content.userInfo = userInfo
            if item.supportsDoseQuickActions {
                content.categoryIdentifier = MedicationNotificationAction.doseCategoryIdentifier
            }

            let trigger: UNNotificationTrigger
            switch item.trigger {
            case let .daily(hour, minute):
                var components = DateComponents()
                components.calendar = .autoupdatingCurrent
                components.timeZone = .autoupdatingCurrent
                components.hour = hour
                components.minute = minute
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            case let .weekly(weekday, hour, minute):
                var components = DateComponents()
                components.calendar = .autoupdatingCurrent
                components.timeZone = .autoupdatingCurrent
                components.weekday = weekday
                components.hour = hour
                components.minute = minute
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            case let .date(date):
                let components = Calendar.autoupdatingCurrent.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: date
                )
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            }
            // A refusal here is the difference between a reminder existing and not
            // existing, so it is counted rather than dropped on the floor.
            do {
                try await center.add(
                    UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)
                )
            } catch {
                failed += 1
            }
        }

        await NotificationHealth.shared.record(
            authorization: status,
            planned: planned.count,
            failed: failed
        )
    }
}
