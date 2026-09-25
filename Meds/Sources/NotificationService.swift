import Foundation
import UserNotifications
import WidgetKit

actor NotificationService {
    static let shared = NotificationService()

    /// Requests still waiting to fire are replaced by the plan outright: one
    /// the plan no longer asks for must not fire.
    static func pendingIdentifiersToRemove(pending: [String], planned: Set<String>) -> [String] {
        pending.filter { $0.hasPrefix("meds.") && !planned.contains($0) }
    }

    /// Delivered alerts that no longer say something true. A refill or
    /// expiration alert is planned only until its moment, so once delivered it
    /// is never in the plan again; sweeping everything unplanned took the only
    /// low-supply warning out of Notification Center on the next launch, or the
    /// next Taken on the lock screen. Those the planner still vouches for stay.
    static func deliveredIdentifiersToRemove(
        delivered: [String],
        outcome: NotificationPlanOutcome
    ) -> [String] {
        let planned = Set(outcome.notifications.map(\.identifier))
        return delivered.filter { $0.hasPrefix("meds.") && !planned.contains($0) && !outcome.retains($0) }
    }

    /// What one planned request says and carries. Taken and Skip on a dated
    /// reminder or a follow-up find their dose from this userInfo, and the
    /// widget finds what a follow-up asks about, so it is built, and tested,
    /// on its own.
    static func content(
        for item: PlannedNotification,
        calendar: Calendar = .autoupdatingCurrent
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        let isDoseMoment = item.kind == .dose || item.kind == .followUp
        // Stack dose reminders together (and refill alerts together) in
        // Notification Center instead of interleaving with everything else.
        content.threadIdentifier = isDoseMoment ? "meds.dose" : "meds.refill"
        // Dose reminders may break through Focus modes (the entitlement in
        // Meds.entitlements grants this; the person still controls it per-app
        // in Settings). Refill alerts are plan-ahead notices, not moments.
        content.interruptionLevel = isDoseMoment ? .timeSensitive : .active
        var userInfo: [String: String] = [:]
        if let medicationID = item.medicationID {
            userInfo["medicationID"] = medicationID.uuidString
        }
        if let scheduleID = item.scheduleID {
            userInfo["scheduleID"] = scheduleID.uuidString
        }
        if let slotDate = item.slotDate {
            userInfo[NotificationIdentifiers.slotDayKey] = NotificationIdentifiers.slotDayValue(slotDate, calendar: calendar)
        }
        if !item.memberScheduleIDs.isEmpty {
            userInfo[NotificationIdentifiers.memberScheduleIDsKey] = NotificationIdentifiers.memberScheduleIDsValue(item.memberScheduleIDs)
        }
        userInfo["notificationKind"] = switch item.kind {
        case .dose: "dose"
        case .followUp: "followUp"
        case .countCheck: "countCheck"
        case .refill, .expiration, .refillCheck: "refill"
        }
        content.userInfo = userInfo
        if item.supportsDoseQuickActions {
            content.categoryIdentifier = MedicationNotificationAction.doseCategoryIdentifier
        }
        return content
    }

    func replaceAllNotifications(
        for plans: [MedicationNotificationPlan],
        requestAuthorization: Bool = false
    ) async {
        let center = UNUserNotificationCenter.current()
        let outcome = NotificationPlanner.plan(for: plans, options: .stored())
        let planned = outcome.notifications
        let plannedIdentifiers = Set(planned.map(\.identifier))
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let managedPending = pending.map(\.identifier).filter { $0.hasPrefix("meds.") }
        let managedDelivered = delivered.map { $0.request.identifier }.filter { $0.hasPrefix("meds.") }
        center.removePendingNotificationRequests(
            withIdentifiers: Self.pendingIdentifiersToRemove(pending: managedPending, planned: plannedIdentifiers)
        )
        center.removeDeliveredNotifications(
            withIdentifiers: Self.deliveredIdentifiersToRemove(delivered: managedDelivered, outcome: outcome)
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
                failed: 0,
                plannedThrough: outcome.plannedThrough
            )
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        var failed = 0
        let deliveredIdentifiers = Set(managedDelivered)
        for item in planned {
            if item.kind != .dose, deliveredIdentifiers.contains(item.identifier) {
                continue
            }
            let content = Self.content(for: item)

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

        // A dose reminder that did not fit under the cap is as absent as one
        // iOS refused, and is reported the same way.
        await NotificationHealth.shared.record(
            authorization: status,
            planned: planned.count,
            failed: failed + outcome.droppedDoseReminders,
            plannedThrough: outcome.plannedThrough
        )
        // Every change to the ledger ends here, so this is where the widgets
        // learn about it.
        WidgetCenter.shared.reloadAllTimelines()
    }
}
