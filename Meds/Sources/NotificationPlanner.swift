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
    /// What the weekly count check weighs about this medication.
    var countCheck: CountCheckPolicy.Candidate? = nil
}

struct ScheduleNotificationPlan: Sendable {
    let id: UUID
    let minutesAfterMidnight: Int
    let doseQuantity: Double
    let weekdayMask: Int
    /// A course that has ended must stop ringing, and a schedule that starts
    /// later must not ring before it does.
    var startDate: Date = .distantPast
    var endDate: Date? = nil
    /// The days, as start-of-day dates from yesterday through tomorrow, whose
    /// slot is already logged. A reminder that has rung stays in Notification
    /// Center only while its dose is still unlogged.
    var loggedDays: Set<Date> = []
}

enum PlannedNotificationKind: Equatable, Sendable {
    case dose
    /// A second reminder for a dose still unlogged 30 minutes after its time,
    /// when chosen in Settings. Rings like a dose reminder.
    case followUp
    case refill
    /// A package expiring, a week ahead. Planned with the refill alerts, under
    /// the same toggle and the same cap.
    case expiration
    /// The morning a refill in progress stops standing in for the low-supply
    /// warning: asks whether it has arrived. Planned with the refill alerts too.
    case refillCheck
    /// The weekly question about one medication's count. Planned with the
    /// refill alerts, whose warnings it keeps honest.
    case countCheck
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
    /// The scheduled moment a one-shot dose request stands for. A reminder
    /// action resolves its dose from this, not from when it was delivered.
    var slotDate: Date? = nil
    /// The schedules a follow-up asks about. The widget, which does not
    /// replan, withdraws a follow-up only once all of them are logged.
    var memberScheduleIDs: [UUID] = []

    var supportsDoseQuickActions: Bool {
        (kind == .dose || kind == .followUp) && groupedDoseCount == 1 && medicationID != nil && scheduleID != nil
    }
}

/// The reminder choices made once, for the whole app, in Settings.
struct NotificationPlanOptions: Equatable, Sendable {
    static let followUpRemindersKey = "followUpRemindersEnabled"
    static let weeklyCountCheckKey = "weeklyCountCheckEnabled"

    /// Off until chosen. With two caregivers, a dose given and logged on the
    /// other phone is unlogged on this one, and its follow-up still rings.
    var followUpReminders = false
    var weeklyCountCheck = true

    static func stored(in defaults: UserDefaults = .standard) -> NotificationPlanOptions {
        NotificationPlanOptions(
            followUpReminders: defaults.bool(forKey: followUpRemindersKey),
            // Never set means never turned off.
            weeklyCountCheck: defaults.object(forKey: weeklyCountCheckKey) as? Bool ?? true
        )
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
    /// The last day every dated reminder is planned for, when a dated one is
    /// still wanted after it: past the planning horizon, or cut by the cap.
    /// Nothing after it rings unless the app is opened and plans again.
    var plannedThrough: Date? = nil

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

    /// The days, from today, that dated dose reminders are planned for. A dated
    /// reminder is a one-shot request for one day and time, and they share the
    /// cap with everything else; a week covers several openings of the app,
    /// each of which plans the week again.
    static let datedHorizonDays = 7

    /// Dated reminders cut by the cap this soon are reported with the repeating
    /// ones that did not fit, so Today says some reminders weren't set.
    static let droppedDoseReportWindow: TimeInterval = 48 * 60 * 60

    /// How long after its moment a dose request that has rung is worth keeping
    /// in Notification Center while its dose is still unlogged.
    static let passedDoseRetention: TimeInterval = 24 * 60 * 60

    /// How far ahead follow-ups are planned. Every log and every opening of
    /// the app plans them again, so a day ahead is plenty, and it keeps them
    /// from crowding the cap.
    static let followUpLookahead: TimeInterval = 24 * 60 * 60

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
        calendar: Calendar = .autoupdatingCurrent,
        options: NotificationPlanOptions = NotificationPlanOptions()
    ) -> NotificationPlanOutcome {
        var notifications: [PlannedNotification] = []
        var doseSlots: [DoseSlot: Set<DoseMember>] = [:]
        var datedSlots: [Date: Set<DoseMember>] = [:]
        var followUpSlots: [Date: Set<DoseMember>] = [:]
        var retainedIdentifiers: Set<String> = []
        var retainedPrefixes: Set<String> = []
        var datedPastHorizon = false
        let today = calendar.startOfDay(for: now)
        let horizon = (0..<datedHorizonDays).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }

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
                let reach = reach(of: schedule, today: today, calendar: calendar)
                switch reach {
                case .ended:
                    break
                case .later:
                    datedPastHorizon = true
                case .steady:
                    for weekdayIndex in 0..<7 where schedule.weekdayMask & (1 << weekdayIndex) != 0 {
                        let slot = DoseSlot(
                            weekday: weekdayIndex + 1,
                            hour: hour,
                            minute: minute
                        )
                        doseSlots[slot, default: []].insert(member)
                    }
                case let .dated(continuesPastHorizon):
                    datedPastHorizon = datedPastHorizon || continuesPastHorizon
                    for day in horizon {
                        guard let slot = slotDate(of: schedule, on: day, calendar: calendar), slot > now else { continue }
                        datedSlots[slot, default: []].insert(member)
                    }
                }

                // The unlogged slots from yesterday through tomorrow. A dated
                // request that has rung is never planned again, so a replan (a
                // Taken on another reminder's lock-screen button is one) would
                // sweep it out of Notification Center; it stays while its dose
                // is unlogged, as a repeating one would, and so does a
                // follow-up. A follow-up still to come is planned for each.
                for offset in -1...1 {
                    guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                          let slot = slotDate(of: schedule, on: day, calendar: calendar),
                          !schedule.loggedDays.contains(calendar.startOfDay(for: slot)) else { continue }
                    let age = now.timeIntervalSince(slot)
                    if slot <= now, age < passedDoseRetention {
                        retainedIdentifiers.insert(NotificationIdentifiers.dose(at: slot, calendar: calendar))
                        // It may have rung under a repeating name while the
                        // schedule was steady: on the morning its end comes
                        // within the week, or when an end is set after it
                        // rang. That name is not planned once the schedule
                        // stops repeating, and must not take the reminder
                        // with it. A steady schedule's own is planned anyway.
                        if !reach.repeats {
                            let time = DoseTime(hour: hour, minute: minute)
                            retainedIdentifiers.insert(dailyIdentifier(time))
                            retainedIdentifiers.insert(weeklyIdentifier(weekday: calendar.component(.weekday, from: day), time))
                        }
                    }
                    guard options.followUpReminders else { continue }
                    if slot.addingTimeInterval(ScheduleEngine.dueWindow) > now {
                        if slot < now.addingTimeInterval(followUpLookahead) {
                            followUpSlots[slot, default: []].insert(member)
                        }
                    } else if age < passedDoseRetention {
                        retainedIdentifiers.insert(NotificationIdentifiers.followUp(at: slot, calendar: calendar))
                    }
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
                        identifier: dailyIdentifier(time),
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
                        identifier: weeklyIdentifier(weekday: slot.weekday, time),
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

        // One request per day and time across every dated schedule. A steady
        // schedule at the same time keeps its own repeating request, which
        // cannot be silenced on particular days, so that day and time rings
        // twice: two reminders are the price of never going quiet.
        let dated = datedSlots.keys.sorted().compactMap { slot -> PlannedNotification? in
            guard let members = datedSlots[slot], !members.isEmpty else { return nil }
            let time = calendar.dateComponents([.hour, .minute], from: slot)
            return doseNotification(
                identifier: NotificationIdentifiers.dose(at: slot, calendar: calendar),
                members: members,
                trigger: .date(slot),
                hour: time.hour ?? 0,
                minute: time.minute ?? 0,
                calendar: calendar,
                slotDate: slot
            )
        }

        let followUps = followUpSlots.keys.sorted().compactMap { slot -> PlannedNotification? in
            guard let members = followUpSlots[slot], !members.isEmpty else { return nil }
            return followUpNotification(slot: slot, members: members, calendar: calendar)
        }

        var refillNotifications: [PlannedNotification] = []
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

        if options.weeklyCountCheck {
            let candidates = plans.compactMap(\.countCheck)
            // One asked already stays until the medication is counted.
            for candidate in candidates where CountCheckPolicy.isDue(candidate, now: now, calendar: calendar) {
                retainedPrefixes.insert(NotificationIdentifiers.countCheckPrefix(medicationID: candidate.medicationID))
            }
            if let target = CountCheckPolicy.target(from: candidates, now: now, calendar: calendar),
               let moment = CountCheckPolicy.moment(for: target, after: now, calendar: calendar) {
                let detailed = plans.first { $0.medicationID == target.medicationID }?.detailedNotifications ?? false
                refillNotifications.append(
                    PlannedNotification(
                        identifier: NotificationIdentifiers.countCheck(medicationID: target.medicationID, on: moment, calendar: calendar),
                        kind: .countCheck,
                        title: detailed ? "Quick count: \(target.displayName)" : "Quick count",
                        body: detailed
                            ? "A 20-second count keeps its run-out date honest. Open Meds Ahead to add it."
                            : "A 20-second count keeps a run-out date honest. Open Meds Ahead to see which medication.",
                        trigger: .date(moment),
                        medicationID: target.medicationID,
                        scheduleID: nil,
                        groupedDoseCount: 0
                    )
                )
            }
        }

        // Nearest refill alerts matter most when trimming is unavoidable.
        refillNotifications.sort { lhs, rhs in
            guard case let .date(left) = lhs.trigger, case let .date(right) = rhs.trigger else { return false }
            return left < right
        }
        // Repeating dose requests first: they keep ringing whether or not the
        // app is opened again. Then the dated ones, soonest first, then the
        // follow-ups, which only ever repeat a question already asked.
        let doseRequests = notifications + dated + followUps
        let droppedDated = dated.dropFirst(max(0, maximumScheduledRequests - notifications.count))
        let reportBefore = now.addingTimeInterval(droppedDoseReportWindow)
        var plannedThrough = datedPastHorizon ? horizon.last : nil
        if let firstDropped = droppedDated.first?.slotDate,
           let lastWholeDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: firstDropped)) {
            plannedThrough = min(plannedThrough ?? lastWholeDay, lastWholeDay)
        }
        return NotificationPlanOutcome(
            notifications: Array((doseRequests + refillNotifications).prefix(maximumScheduledRequests)),
            droppedDoseReminders: max(0, notifications.count - maximumScheduledRequests)
                + droppedDated.filter { ($0.slotDate ?? .distantFuture) < reportBefore }.count,
            retainedIdentifiers: retainedIdentifiers,
            retainedPrefixes: retainedPrefixes,
            plannedThrough: plannedThrough
        )
    }

    /// How a schedule's first and last days bear on the week being planned.
    private enum Reach {
        /// Its last day has passed.
        case ended
        /// Running today and through the whole horizon: repeating requests say
        /// it exactly, and go on saying it if the app is not opened again. One
        /// that ends later would ring past its end in that case, which is the
        /// safe way to be wrong; it turns dated once its end comes in reach.
        case steady
        /// Starting or ending within the horizon: one-shot requests on the days
        /// it has a slot.
        case dated(continuesPastHorizon: Bool)
        /// Starting after the horizon: planned once the horizon reaches it.
        case later

        var repeats: Bool {
            if case .steady = self { true } else { false }
        }
    }

    private static func reach(of schedule: ScheduleNotificationPlan, today: Date, calendar: Calendar) -> Reach {
        let endDay = schedule.endDate.map { calendar.startOfDay(for: $0) }
        if let endDay, endDay < today { return .ended }
        let afterHorizon = calendar.date(byAdding: .day, value: datedHorizonDays, to: today) ?? today
        let continuesPastHorizon = endDay.map { $0 >= afterHorizon } ?? true
        let startDay = calendar.startOfDay(for: schedule.startDate)
        if startDay <= today, continuesPastHorizon { return .steady }
        return startDay < afterHorizon ? .dated(continuesPastHorizon: continuesPastHorizon) : .later
    }

    /// Which days a schedule has a dose is `ScheduleEngine`'s answer, never
    /// the planner's own.
    private static func slotDate(of schedule: ScheduleNotificationPlan, on day: Date, calendar: Calendar) -> Date? {
        ScheduleEngine.slotDate(
            minutesAfterMidnight: schedule.minutesAfterMidnight,
            weekdayMask: schedule.weekdayMask,
            startDate: schedule.startDate,
            endDate: schedule.endDate,
            on: day,
            calendar: calendar
        )
    }

    /// The repeating requests' names, spelled once: a rung one is kept by
    /// the same name it was planned under.
    private static func dailyIdentifier(_ time: DoseTime) -> String {
        "meds.group.dose.daily.\(time.code)"
    }

    private static func weeklyIdentifier(weekday: Int, _ time: DoseTime) -> String {
        "meds.group.dose.weekly.\(weekday).\(time.code)"
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
        calendar: Calendar,
        slotDate: Date? = nil
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
            groupedDoseCount: ordered.count,
            slotDate: slotDate
        )
    }

    /// Worded for a household with more than one person giving doses: this
    /// phone only knows what was logged on it, so the question is whether
    /// anyone has given it, not a prompt to give it.
    private static func followUpNotification(
        slot: Date,
        members: Set<DoseMember>,
        calendar: Calendar
    ) -> PlannedNotification {
        let ordered = members.sorted { lhs, rhs in
            if lhs.displayName != rhs.displayName { return lhs.displayName < rhs.displayName }
            return lhs.scheduleID.uuidString < rhs.scheduleID.uuidString
        }
        let parts = calendar.dateComponents([.hour, .minute], from: slot)
        let time = timeLabel(hour: parts.hour ?? 0, minute: parts.minute ?? 0, calendar: calendar)
        let only = ordered.count == 1 ? ordered[0] : nil
        let title: String
        let body: String
        if let only {
            title = only.detailedNotifications ? "\(only.displayName) not logged yet" : "\(time) dose not logged yet"
            body = (only.detailedNotifications ? "The \(time) dose isn't" : "It isn't")
                + " logged on this phone yet. Check before giving it, in case someone already did."
        } else {
            title = "\(time) doses not logged yet"
            body = "They aren't logged on this phone yet. Check before giving them, in case someone already did."
        }
        return PlannedNotification(
            identifier: NotificationIdentifiers.followUp(at: slot, calendar: calendar),
            kind: .followUp,
            title: title,
            body: body,
            trigger: .date(slot.addingTimeInterval(ScheduleEngine.dueWindow)),
            medicationID: only?.medicationID,
            scheduleID: only?.scheduleID,
            groupedDoseCount: ordered.count,
            slotDate: slot,
            memberScheduleIDs: ordered.map(\.scheduleID)
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
        let ownDoseEvents = doseEvents.filter { $0.medicationID == medication.id }
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
                        weekdayMask: $0.weekdayMask,
                        startDate: $0.startDate,
                        endDate: $0.endDate,
                        loggedDays: loggedDays(of: $0, doseEvents: ownDoseEvents, now: now, calendar: calendar)
                    )
                },
            refillInProgress: medication.refillStatus != .none,
            expirationDate: medication.expirationDate,
            pharmacyName: medication.pharmacyName,
            rxNumber: medication.rxNumber,
            refillStatusDate: medication.refillStatusDate,
            onHand: forecast.currentSupply > 0,
            needsCount: forecast.needsCount,
            countCheck: CountCheckPolicy.candidate(
                for: medication,
                schedules: schedules,
                inventoryEvents: inventoryEvents,
                forecast: forecast,
                now: now,
                calendar: calendar
            )
        )
    }

    /// The days from yesterday through tomorrow whose slot a log already
    /// accounts for, as `ScheduleEngine` judges it.
    private static func loggedDays(
        of schedule: DoseSchedule,
        doseEvents: [DoseEvent],
        now: Date,
        calendar: Calendar
    ) -> Set<Date> {
        let today = calendar.startOfDay(for: now)
        var logged: Set<Date> = []
        for offset in -1...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let slot = ScheduleEngine.scheduledDate(for: schedule, on: day, calendar: calendar) else { continue }
            let dose = ScheduledDose(medicationID: schedule.medicationID, scheduleID: schedule.id, date: slot, quantity: schedule.doseQuantity)
            if ScheduleEngine.loggedEvent(for: dose, in: doseEvents, now: now, calendar: calendar) != nil {
                logged.insert(calendar.startOfDay(for: slot))
            }
        }
        return logged
    }
}
