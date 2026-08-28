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
}

struct PlannedNotification: Equatable, Sendable {
    let identifier: String
    let kind: PlannedNotificationKind
    let title: String
    let body: String
    let trigger: PlannedNotificationTrigger
    let medicationID: UUID?
    let scheduleID: UUID?
    let groupedDoseCount: Int

    var supportsDoseQuickActions: Bool {
        kind == .dose && groupedDoseCount == 1 && medicationID != nil && scheduleID != nil
    }
}

enum NotificationPlanner {
    /// iOS silently keeps only the ~64 soonest pending requests per app and drops
    /// the rest without error. Staying under that with room to spare, and putting
    /// repeating dose reminders ahead of one-shot refill alerts, means a heavy
    /// regimen degrades by dropping the farthest-out refill alert — never a dose.
    static let maximumScheduledRequests = 60

    static func notifications(
        for plan: MedicationNotificationPlan,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [PlannedNotification] {
        notifications(for: [plan], now: now, calendar: calendar)
    }

    static func notifications(
        for plans: [MedicationNotificationPlan],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [PlannedNotification] {
        var notifications: [PlannedNotification] = []
        var doseSlots: [DoseSlot: Set<DoseMember>] = [:]

        for plan in plans where !plan.isArchived && plan.doseRemindersEnabled && !plan.isAsNeeded {
            for schedule in plan.schedules {
                let hour = schedule.minutesAfterMidnight / 60
                let minute = schedule.minutesAfterMidnight % 60
                let member = DoseMember(
                    medicationID: plan.medicationID,
                    scheduleID: schedule.id,
                    displayName: plan.displayName,
                    unitName: plan.unitName,
                    quantity: schedule.doseQuantity,
                    detailedNotifications: plan.detailedNotifications
                )
                for weekdayIndex in 0..<7 where schedule.weekdayMask & (1 << weekdayIndex) != 0 {
                    let slot = DoseSlot(
                        weekday: weekdayIndex + 1,
                        hour: hour,
                        minute: minute
                    )
                    doseSlots[slot, default: []].insert(member)
                }
            }
        }

        var uniqueTimes = Set<DoseTime>()
        for slot in doseSlots.keys {
            uniqueTimes.insert(DoseTime(hour: slot.hour, minute: slot.minute))
        }
        let times = uniqueTimes.sorted { lhs, rhs in
            lhs.hour == rhs.hour ? lhs.minute < rhs.minute : lhs.hour < rhs.hour
        }
        for time in times {
            let slots = (1...7).map {
                DoseSlot(weekday: $0, hour: time.hour, minute: time.minute)
            }
            let memberSets = slots.compactMap { doseSlots[$0] }
            if memberSets.count == 7,
               memberSets.dropFirst().allSatisfy({ $0 == memberSets[0] }) {
                notifications.append(
                    doseNotification(
                        identifier: "meds.group.dose.daily.\(time.code)",
                        members: memberSets[0],
                        trigger: .daily(hour: time.hour, minute: time.minute),
                        hour: time.hour,
                        minute: time.minute,
                        calendar: calendar
                    )
                )
                continue
            }

            for slot in slots {
                guard let members = doseSlots[slot], !members.isEmpty else { continue }
                notifications.append(
                    doseNotification(
                        identifier: "meds.group.dose.weekly.\(slot.weekday).\(time.code)",
                        members: members,
                        trigger: .weekly(
                            weekday: slot.weekday,
                            hour: time.hour,
                            minute: time.minute
                        ),
                        hour: time.hour,
                        minute: time.minute,
                        calendar: calendar
                    )
                )
            }
        }

        var refillNotifications: [PlannedNotification] = []
        for plan in plans where !plan.isArchived {
            guard plan.refillRemindersEnabled, let depletionDate = plan.depletionDate else { continue }
            let depletionDay = calendar.startOfDay(for: depletionDate)
            let leadDay = calendar.date(byAdding: .day, value: -max(1, plan.refillLeadDays), to: depletionDay) ?? depletionDay
            let reminderDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: leadDay) ?? leadDay
            let dateCode = depletionDay.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).locale(Locale(identifier: "en_US_POSIX")))
                .filter(\.isNumber)
            // A lead moment that has already passed is never re-announced. Plans are
            // rebuilt whenever the app is open, so an immediate alert would only ever
            // interrupt someone already looking at the low-supply state on Today and
            // Supply, and would fire again on every launch once it was dismissed.
            guard reminderDate > now else { continue }
            refillNotifications.append(
                PlannedNotification(
                    identifier: "meds.\(plan.medicationID.uuidString).refill.\(dateCode)",
                    kind: .refill,
                    title: plan.detailedNotifications ? "Plan a refill for \(plan.displayName)" : "Supply reminder",
                    body: plan.detailedNotifications
                        ? "Your confirmed supply may run out around \(depletionDay.formatted(date: .abbreviated, time: .omitted))."
                        : "Open Meds Ahead to review a medication that may be running low.",
                    trigger: .date(reminderDate),
                    medicationID: plan.medicationID,
                    scheduleID: nil,
                    groupedDoseCount: 0
                )
            )
        }

        // Nearest refill alerts matter most when trimming is unavoidable.
        refillNotifications.sort { lhs, rhs in
            guard case let .date(left) = lhs.trigger, case let .date(right) = rhs.trigger else { return false }
            return left < right
        }
        return Array((notifications + refillNotifications).prefix(maximumScheduledRequests))
    }

    private static func doseNotification(
        identifier: String,
        members: Set<DoseMember>,
        trigger: PlannedNotificationTrigger,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> PlannedNotification {
        let ordered = members.sorted { lhs, rhs in
            if lhs.displayName != rhs.displayName { return lhs.displayName < rhs.displayName }
            return lhs.scheduleID.uuidString < rhs.scheduleID.uuidString
        }
        let only = ordered.count == 1 ? ordered[0] : nil
        let title: String
        let body: String
        if let only {
            title = only.detailedNotifications ? "Time for \(only.displayName)" : "Medication reminder"
            body = only.detailedNotifications
                ? "Touch and hold to log \(only.quantity.medicationQuantityText) \(pluralized(only.unitName, quantity: only.quantity)), or open Meds Ahead to review."
                : "Touch and hold to log this dose, or open Meds Ahead to review."
        } else {
            title = "\(timeLabel(hour: hour, minute: minute, calendar: calendar)) meds are ready"
            body = "Open Meds Ahead to review and log \(ordered.count) scheduled doses."
        }

        return PlannedNotification(
            identifier: identifier,
            kind: .dose,
            title: title,
            body: body,
            trigger: trigger,
            medicationID: only?.medicationID,
            scheduleID: only?.scheduleID,
            groupedDoseCount: ordered.count
        )
    }

    private static func timeLabel(hour: Int, minute: Int, calendar: Calendar) -> String {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2001
        components.month = 1
        components.day = 1
        components.hour = hour
        components.minute = minute
        guard let date = calendar.date(from: components) else {
            return String(format: "%02d:%02d", hour, minute)
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func pluralized(_ unit: String, quantity: Double) -> String {
        quantity == 1 ? unit : unit + "s"
    }

    private struct DoseTime: Hashable {
        let hour: Int
        let minute: Int

        var code: String { String(format: "%02d%02d", hour, minute) }
    }

    private struct DoseSlot: Hashable {
        let weekday: Int
        let hour: Int
        let minute: Int
    }

    private struct DoseMember: Hashable {
        let medicationID: UUID
        let scheduleID: UUID
        let displayName: String
        let unitName: String
        let quantity: Double
        let detailedNotifications: Bool
    }
}

@MainActor
enum NotificationPlanBuilder {
    static func makeAll(
        medications: [Medication],
        schedules: [DoseSchedule],
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [MedicationNotificationPlan] {
        medications.map {
            make(
                medication: $0,
                schedules: schedules,
                inventoryEvents: inventoryEvents,
                doseEvents: doseEvents,
                now: now,
                calendar: calendar
            )
        }
    }

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
