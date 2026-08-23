import Foundation

struct MedicationNotificationPlan: Sendable {
    let medicationID: UUID
    let displayName: String
    let unitName: String
    let isAsNeeded: Bool
    let isArchived: Bool
    let doseRemindersEnabled: Bool
    let refillRemindersEnabled: Bool
    let detailedNotifications: Bool
    let refillLeadDays: Int
    let depletionDate: Date?
    let schedules: [ScheduleNotificationPlan]
}

struct ScheduleNotificationPlan: Sendable {
    let id: UUID
    let minutesAfterMidnight: Int
    let doseQuantity: Double
    let weekdayMask: Int
}

enum PlannedNotificationKind: Equatable, Sendable {
    case dose
    case refill
}

enum PlannedNotificationTrigger: Equatable, Hashable, Sendable {
    case daily(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)
    case date(Date)
    case interval(TimeInterval)
}

struct PlannedNotification: Equatable, Sendable {
    let identifier: String
    let kind: PlannedNotificationKind
    let title: String
    let body: String
    let trigger: PlannedNotificationTrigger
    let medicationID: UUID
    let scheduleID: UUID?
}

enum NotificationPlanner {
    static func notifications(
        for plan: MedicationNotificationPlan,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [PlannedNotification] {
        guard !plan.isArchived else { return [] }
        var notifications: [PlannedNotification] = []

        if plan.doseRemindersEnabled, !plan.isAsNeeded {
            for schedule in plan.schedules {
                let hour = schedule.minutesAfterMidnight / 60
                let minute = schedule.minutesAfterMidnight % 60
                if schedule.weekdayMask == 0b1111111 {
                    notifications.append(
                        PlannedNotification(
                            identifier: "meds.\(plan.medicationID.uuidString).dose.\(schedule.id.uuidString).daily",
                            kind: .dose,
                            title: plan.detailedNotifications ? "Time for \(plan.displayName)" : "Medication reminder",
                            body: plan.detailedNotifications
                                ? "Touch and hold to log \(schedule.doseQuantity.medicationQuantityText) \(pluralized(plan.unitName, quantity: schedule.doseQuantity)), or open Meds to review."
                                : "Touch and hold to log this dose, or open Meds to review.",
                            trigger: .daily(hour: hour, minute: minute),
                            medicationID: plan.medicationID,
                            scheduleID: schedule.id
                        )
                    )
                } else {
                    for weekdayIndex in 0..<7 where schedule.weekdayMask & (1 << weekdayIndex) != 0 {
                        notifications.append(
                            PlannedNotification(
                                identifier: "meds.\(plan.medicationID.uuidString).dose.\(schedule.id.uuidString).\(weekdayIndex)",
                                kind: .dose,
                                title: plan.detailedNotifications ? "Time for \(plan.displayName)" : "Medication reminder",
                                body: plan.detailedNotifications
                                    ? "Touch and hold to log \(schedule.doseQuantity.medicationQuantityText) \(pluralized(plan.unitName, quantity: schedule.doseQuantity)), or open Meds to review."
                                    : "Touch and hold to log this dose, or open Meds to review.",
                                trigger: .weekly(
                                    weekday: weekdayIndex + 1,
                                    hour: hour,
                                    minute: minute
                                ),
                                medicationID: plan.medicationID,
                                scheduleID: schedule.id
                            )
                        )
                    }
                }
            }
        }

        if plan.refillRemindersEnabled, let depletionDate = plan.depletionDate {
            let depletionDay = calendar.startOfDay(for: depletionDate)
            let leadDay = calendar.date(byAdding: .day, value: -max(1, plan.refillLeadDays), to: depletionDay) ?? depletionDay
            let reminderDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: leadDay) ?? leadDay
            let dateCode = depletionDay.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).locale(Locale(identifier: "en_US_POSIX")))
                .filter(\.isNumber)
            let trigger: PlannedNotificationTrigger = reminderDate > now.addingTimeInterval(2)
                ? .date(reminderDate)
                : .interval(3)
            notifications.append(
                PlannedNotification(
                    identifier: "meds.\(plan.medicationID.uuidString).refill.\(dateCode)",
                    kind: .refill,
                    title: plan.detailedNotifications ? "Plan a refill for \(plan.displayName)" : "Supply reminder",
                    body: plan.detailedNotifications
                        ? "Your confirmed supply may run out around \(depletionDay.formatted(date: .abbreviated, time: .omitted))."
                        : "Open Meds to review a medication that may be running low.",
                    trigger: trigger,
                    medicationID: plan.medicationID,
                    scheduleID: nil
                )
            )
        }

        return notifications
    }

    private static func pluralized(_ unit: String, quantity: Double) -> String {
        quantity == 1 ? unit : unit + "s"
    }
}

@MainActor
enum NotificationPlanBuilder {
    static func make(
        medication: Medication,
        schedules: [DoseSchedule],
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> MedicationNotificationPlan {
        let forecast = ForecastEngine.forecast(
            medication: medication,
            schedules: schedules,
            inventoryEvents: inventoryEvents,
            doseEvents: doseEvents,
            now: now,
            calendar: calendar
        )
        return MedicationNotificationPlan(
            medicationID: medication.id,
            displayName: medication.displayName,
            unitName: medication.form.unitName,
            isAsNeeded: medication.isAsNeeded,
            isArchived: medication.isArchived,
            doseRemindersEnabled: medication.remindersEnabled,
            refillRemindersEnabled: medication.refillRemindersEnabled,
            detailedNotifications: medication.detailedNotifications,
            refillLeadDays: medication.refillLeadDays,
            depletionDate: forecast.depletionDate,
            schedules: schedules
                .filter { $0.medicationID == medication.id }
                .map {
                    ScheduleNotificationPlan(
                        id: $0.id,
                        minutesAfterMidnight: $0.minutesAfterMidnight,
                        doseQuantity: $0.doseQuantity,
                        weekdayMask: $0.weekdayMask
                    )
                }
        )
    }
}
