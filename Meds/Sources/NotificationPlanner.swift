import Foundation

struct MedicationNotificationPlan: Sendable {
    let medicationID: UUID
    let displayName: String
    let form: MedicationForm
    let isAsNeeded: Bool
    let isArchived: Bool
    let doseRemindersEnabled: Bool
    let refillRemindersEnabled: Bool
    let detailedNotifications: Bool
    let refillLeadDays: Int
    let refillsRemaining: Int?
    let depletionDate: Date?
    let schedules: [ScheduleNotificationPlan]
    /// A refill already requested or ready quiets the low-supply warning for as
    /// long as `SupplyAttention` says it can still answer for the supply.
    var refillInProgress = false
    var expirationDate: Date? = nil
    var pharmacyName = ""
    var rxNumber = ""
    /// The refill's expected or pickup date.
    var refillStatusDate: Date? = nil
    var onHand = true
    /// The forecast's assumed doses used up the ledger, so `depletionDate` is
    /// where they ran out, not a day to plan a refill by.
    var needsCount = false
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
    /// A package expiring, a week ahead. Planned with the refill alerts, under
    /// the same toggle and the same cap.
    case expiration
    /// The morning a refill in progress stops standing in for the low-supply
    /// warning: asks whether it has arrived. Planned with the refill alerts too.
    case refillCheck
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

/// What a planning pass asks iOS for, and what it could not ask for.
struct NotificationPlanOutcome: Equatable, Sendable {
    let notifications: [PlannedNotification]
    /// Dose reminders that did not fit under the pending-request cap. They are
    /// reported rather than dropped quietly, so Today can say so.
    let droppedDoseReminders: Int
    /// Refill, expiration and refill-check alerts whose moment has passed but
    /// which still say something true. Their moments are never planned again,
    /// so a delivered one may be the only warning left in Notification Center,
    /// and replanning must not sweep it away. An expiration alert is kept by
    /// its exact identifier: its date is the package's own, and changes only
    /// when a new package is recorded.
    let retainedIdentifiers: Set<String>
    /// Refill alerts and refill checks are kept by medication instead, as
    /// identifier prefixes. The run-out day in their identifiers moves a day
    /// whenever a dose is skipped, and every day once nothing is left, while
    /// the warning already given is just as true.
    let retainedPrefixes: Set<String>

    func retains(_ identifier: String) -> Bool {
        retainedIdentifiers.contains(identifier) || retainedPrefixes.contains { identifier.hasPrefix($0) }
    }
}

enum NotificationPlanner {
    /// iOS silently keeps only the ~64 soonest pending requests per app and drops
    /// the rest without error. Staying under that with room to spare, and putting
    /// repeating dose reminders ahead of one-shot refill alerts, means a heavy
    /// regimen degrades by dropping the farthest-out refill alert first. Dose
    /// reminders alone can pass the cap when many times differ across weekdays;
    /// the ones that do not fit are counted in `NotificationPlanOutcome`.
    static let maximumScheduledRequests = 60

    /// How far ahead of a package's expiration date the one reminder comes.
    static let expirationLeadDays = 7

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
        plan(for: plans, now: now, calendar: calendar).notifications
    }

    static func plan(
        for plans: [MedicationNotificationPlan],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> NotificationPlanOutcome {
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
                    form: plan.form,
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
        var retainedIdentifiers: Set<String> = []
        var retainedPrefixes: Set<String> = []
        for plan in plans where !plan.isArchived && plan.refillRemindersEnabled {
            if let expirationDate = plan.expirationDate {
                let expirationDay = calendar.startOfDay(for: expirationDate)
                let leadDay = calendar.date(byAdding: .day, value: -expirationLeadDays, to: expirationDay) ?? expirationDay
                let reminderDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: leadDay) ?? leadDay
                let dateCode = expirationDay.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).locale(Locale(identifier: "en_US_POSIX")))
                    .filter(\.isNumber)
                let identifier = "meds.\(plan.medicationID.uuidString).expiration.\(dateCode)"
                if reminderDate > now {
                    let expires = dayText(expirationDay, calendar: calendar)
                    refillNotifications.append(
                        PlannedNotification(
                            identifier: identifier,
                            kind: .expiration,
                            title: plan.detailedNotifications ? "\(plan.displayName) expires soon" : "Package expiring soon",
                            body: plan.detailedNotifications
                                ? "The package on file expires \(expires). Check the date on the label and plan a replacement."
                                : "A medication's package expires in a week. Open Meds Ahead to see which.",
                            trigger: .date(reminderDate),
                            medicationID: plan.medicationID,
                            scheduleID: nil,
                            groupedDoseCount: 0
                        )
                    )
                } else {
                    // The same package is still the one on file.
                    retainedIdentifiers.insert(identifier)
                }
            }

            // The morning a refill in progress stops answering for the supply.
            // Planned while that morning is still ahead, even in the hours after
            // midnight when the pause has already lapsed: dropping it then would
            // cancel the one alert that says so.
            var refillCheckDay: Date?
            if plan.refillInProgress {
                // One already asked is still a fair question until the refill is
                // added or cleared, whichever morning it was asked for.
                retainedPrefixes.insert("meds.\(plan.medicationID.uuidString).refillcheck.")
            }
            // A count needed has no run-out day to warn ahead of or to quote:
            // the forecast's today is where its assumptions ran out. It needs
            // attention now, so a warning already delivered stays, and nothing
            // new is written from that date. Today and Supply ask for the count.
            if plan.needsCount {
                retainedPrefixes.insert("meds.\(plan.medicationID.uuidString).refill.")
                continue
            }
            if plan.refillInProgress,
               let checkDate = SupplyAttention.refillCheckMoment(
                   refillStatusDate: plan.refillStatusDate,
                   depletionDate: plan.depletionDate,
                   calendar: calendar
               ),
               checkDate > now {
                refillCheckDay = calendar.startOfDay(for: checkDate)
                refillNotifications.append(
                    PlannedNotification(
                        identifier: "meds.\(plan.medicationID.uuidString).refillcheck.\(dayCode(checkDate, calendar: calendar))",
                        kind: .refillCheck,
                        title: plan.detailedNotifications ? "Is the refill for \(plan.displayName) in hand?" : "Is the refill in hand?",
                        body: refillCheckBody(for: plan, calendar: calendar),
                        trigger: .date(checkDate),
                        medicationID: plan.medicationID,
                        scheduleID: nil,
                        groupedDoseCount: 0
                    )
                )
            }

            guard let depletionDate = plan.depletionDate else { continue }
            let depletionDay = calendar.startOfDay(for: depletionDate)
            // A prescription with no refills left needs a prescriber, not a pharmacy,
            // and that takes longer than picking up a bag. It is the situation with
            // the least slack in it and it used to get exactly the same warning as
            // every other, at exactly the same moment.
            let needsPrescriber = plan.refillsRemaining == 0
            let leadDays = SupplyAttention.leadDays(refillLeadDays: plan.refillLeadDays, refillsRemaining: plan.refillsRemaining)
            let leadDay = calendar.date(byAdding: .day, value: -max(1, leadDays), to: depletionDay) ?? depletionDay
            let reminderDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: leadDay) ?? leadDay
            let dateCode = depletionDay.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).locale(Locale(identifier: "en_US_POSIX")))
                .filter(\.isNumber)
            let identifier = "meds.\(plan.medicationID.uuidString).refill.\(dateCode)"
            // One already delivered stays for as long as the supply still needs
            // someone to act, whatever run-out day it was written for.
            if attention(for: plan, at: now, depletionDay: depletionDay, calendar: calendar).needsAttention {
                retainedPrefixes.insert("meds.\(plan.medicationID.uuidString).refill.")
            }
            // A lead moment that has already passed is never re-announced. Plans are
            // rebuilt whenever the app is open, so an immediate alert would only ever
            // interrupt someone already looking at the low-supply state on Today and
            // Supply, and would fire again on every launch once it was dismissed.
            guard reminderDate > now else { continue }
            // A refill in progress that will still answer for the supply when the
            // warning is due makes the warning unnecessary; the refill check comes
            // when it stops answering. On the same morning, the check says it.
            if attention(for: plan, at: reminderDate, depletionDay: depletionDay, calendar: calendar).refillPauseHolds
                || refillCheckDay == leadDay {
                continue
            }
            refillNotifications.append(
                PlannedNotification(
                    identifier: identifier,
                    kind: .refill,
                    title: refillTitle(for: plan, needsPrescriber: needsPrescriber),
                    body: refillBody(for: plan, needsPrescriber: needsPrescriber, depletionDay: depletionDay, calendar: calendar),
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
        return NotificationPlanOutcome(
            notifications: Array((notifications + refillNotifications).prefix(maximumScheduledRequests)),
            droppedDoseReminders: max(0, notifications.count - maximumScheduledRequests),
            retainedIdentifiers: retainedIdentifiers,
            retainedPrefixes: retainedPrefixes
        )
    }

    /// The attention rule as it will stand at `moment`, from the plan's forecast.
    private static func attention(
        for plan: MedicationNotificationPlan,
        at moment: Date,
        depletionDay: Date,
        calendar: Calendar
    ) -> SupplyAttention {
        SupplyAttention(
            daysRemaining: max(0, SupplyAttention.days(from: moment, to: depletionDay, calendar: calendar)),
            onHand: plan.onHand && depletionDay >= calendar.startOfDay(for: moment),
            needsCount: plan.needsCount,
            refillLeadDays: plan.refillLeadDays,
            refillsRemaining: plan.refillsRemaining,
            refillInProgress: plan.refillInProgress,
            daysSinceRefillDate: plan.refillStatusDate.map { SupplyAttention.days(from: $0, to: moment, calendar: calendar) }
        )
    }

    /// A day as yyyyMMdd in the plan's calendar, for an identifier.
    private static func dayCode(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func refillCheckBody(for plan: MedicationNotificationPlan, calendar: Calendar) -> String {
        guard plan.detailedNotifications else {
            return "Open Meds Ahead to add a refill that has arrived, or to check on one that hasn't."
        }
        var body = "If it has arrived, add it in Meds Ahead."
        if let depletionDate = plan.depletionDate {
            body += " If not, your confirmed supply may run out around \(dayText(calendar.startOfDay(for: depletionDate), calendar: calendar))."
        }
        if !plan.pharmacyName.isEmpty {
            body += " Call \(plan.pharmacyName)" + (plan.rxNumber.isEmpty ? "." : " with Rx \(plan.rxNumber).")
        }
        return body
    }

    private static func refillTitle(for plan: MedicationNotificationPlan, needsPrescriber: Bool) -> String {
        guard plan.detailedNotifications else {
            return needsPrescriber ? "Prescription reminder" : "Supply reminder"
        }
        return needsPrescriber
            ? "Renew \(plan.displayName)"
            : "Plan a refill for \(plan.displayName)"
    }

    /// A day, written in the calendar the plan was made with; the device's own
    /// zone would print a midnight elsewhere as the day before.
    private static func dayText(_ day: Date, calendar: Calendar) -> String {
        day.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, calendar: calendar, timeZone: calendar.timeZone))
    }

    private static func refillBody(
        for plan: MedicationNotificationPlan,
        needsPrescriber: Bool,
        depletionDay: Date,
        calendar: Calendar
    ) -> String {
        let runsOut = dayText(depletionDay, calendar: calendar)
        guard plan.detailedNotifications else {
            return needsPrescriber
                ? "Open Meds Ahead: a medication is running low and has no refills left."
                : "Open Meds Ahead to review a medication that may be running low."
        }
        var body = needsPrescriber
            ? "No refills remain, so this one needs a new prescription. Your confirmed supply may run out around \(runsOut)."
            : "Your confirmed supply may run out around \(runsOut)."
        // The call to make, with the number the pharmacy will ask for.
        if !needsPrescriber, !plan.pharmacyName.isEmpty {
            body += " Call \(plan.pharmacyName)" + (plan.rxNumber.isEmpty ? "." : " with Rx \(plan.rxNumber).")
        }
        return body
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
                ? "Touch and hold to log \(only.form.quantityText(only.quantity)), or open Meds Ahead to review."
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
        let form: MedicationForm
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
            form: medication.form,
            isAsNeeded: medication.isAsNeeded,
            isArchived: medication.isArchived,
            doseRemindersEnabled: medication.remindersEnabled,
            refillRemindersEnabled: medication.refillRemindersEnabled,
            detailedNotifications: medication.detailedNotifications,
            refillLeadDays: medication.refillLeadDays,
            refillsRemaining: medication.refillsRemaining,
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
                },
            refillInProgress: medication.refillStatus != .none,
            expirationDate: medication.expirationDate,
            pharmacyName: medication.pharmacyName,
            rxNumber: medication.rxNumber,
            refillStatusDate: medication.refillStatusDate,
            onHand: forecast.currentSupply > 0,
            needsCount: forecast.needsCount
        )
    }
}
