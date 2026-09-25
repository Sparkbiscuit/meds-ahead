import Foundation

/// The weekly count check: which one medication to ask about, and when.
///
/// A run-out date is only as honest as the last count. A dose given and
/// logged on another phone, a tablet dropped, a dose logged twice: none of it
/// shows until someone counts. One question a week, about the medication it
/// would hurt most to be wrong about, keeps the dates honest without nagging.
/// Today's quick count and the reminder ask about the same one.
enum CountCheckPolicy {
    /// A count this many calendar days old, or older, is due another look.
    static let intervalDays = 7

    /// The hour the question comes: after the morning doses, before the day
    /// gets away.
    static let hour = 10

    struct Candidate: Equatable, Sendable {
        let medicationID: UUID
        let displayName: String
        /// Scheduled, running today, not archived, with refill reminders on:
        /// a count here feeds a warning someone is relying on.
        let isEligible: Bool
        let daysRemaining: Int?
        let needsCount: Bool
        /// The opening count or the latest correction. A refill adds to the
        /// count but nobody counted what was already there.
        let lastCountDate: Date?
    }

    /// Whether the last count is a week old or more by the calendar, so one
    /// made on Tuesday afternoon is due the next Tuesday morning.
    static func isDue(_ candidate: Candidate, now: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard candidate.isEligible, let lastCountDate = candidate.lastCountDate else { return false }
        return SupplyAttention.days(from: lastCountDate, to: now, calendar: calendar) >= intervalDays
    }

    /// The one medication to ask about now: of those due, a count needed
    /// first, then the soonest to run out.
    static func target(from candidates: [Candidate], now: Date, calendar: Calendar = .autoupdatingCurrent) -> Candidate? {
        candidates.filter { isDue($0, now: now, calendar: calendar) }.min(by: asksFirst)
    }

    /// 10:00 on the first day a whole number of weeks after the count's day
    /// whose 10:00 is still ahead, and a week or more after the last question
    /// about any medication. Weekly from the count, whenever the plan is made,
    /// so the question never comes two days running, even when the one to
    /// ask about changes.
    static func moment(
        for candidate: Candidate,
        after now: Date,
        lastAsked: Date? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        guard let lastCountDate = candidate.lastCountDate else { return nil }
        let countDay = calendar.startOfDay(for: lastCountDate)
        let notBefore = lastAsked.flatMap { calendar.date(byAdding: .day, value: intervalDays, to: calendar.startOfDay(for: $0)) }
        let from = max(now, notBefore ?? now)
        var weeks = max(1, SupplyAttention.days(from: countDay, to: from, calendar: calendar) / intervalDays)
        // At most two steps: the week `from` falls in can have passed 10:00,
        // or begun before the week after the last question.
        for _ in 0..<3 {
            guard let day = calendar.date(byAdding: .day, value: weeks * intervalDays, to: countDay),
                  let moment = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { return nil }
            if moment > now, notBefore.map({ day >= $0 }) ?? true { return moment }
            weeks += 1
        }
        return nil
    }

    // MARK: - The last question asked

    /// The count check planned, and the last one whose moment has come,
    /// remembered between planning passes. The week is the reminder's, not
    /// each medication's: two medications counted a day apart were otherwise
    /// asked about on two mornings running.
    static let plannedMomentKey = "countCheckPlannedMoment"
    static let askedMomentKey = "countCheckAskedMoment"

    /// The latest count check whose moment has come. One still ahead may be
    /// replaced by a question about another medication, so it is not asked
    /// until its moment passes.
    static func lastAsked(in defaults: UserDefaults, now: Date) -> Date? {
        [askedMomentKey, plannedMomentKey]
            .compactMap { defaults.object(forKey: $0) as? Date }
            .filter { $0 <= now }
            .max()
    }

    /// After every planning pass, with the moment it planned, if any.
    static func remember(planned moment: Date?, now: Date, in defaults: UserDefaults) {
        if let asked = lastAsked(in: defaults, now: now) {
            defaults.set(asked, forKey: askedMomentKey)
        }
        if let moment {
            defaults.set(moment, forKey: plannedMomentKey)
        } else {
            defaults.removeObject(forKey: plannedMomentKey)
        }
    }

    static func candidate(
        for medication: Medication,
        schedules: [DoseSchedule],
        inventoryEvents: [InventoryEvent],
        forecast: SupplyForecast,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Candidate {
        let today = calendar.startOfDay(for: now)
        let runningToday = schedules.contains { schedule in
            schedule.medicationID == medication.id
                && calendar.startOfDay(for: schedule.startDate) <= today
                && schedule.endDate.map { calendar.startOfDay(for: $0) >= today } ?? true
        }
        let lastCountDate = inventoryEvents
            .filter { $0.medicationID == medication.id && ($0.reason == .openingCount || $0.reason == .correction) }
            .map(\.date)
            .max()
        return Candidate(
            medicationID: medication.id,
            displayName: medication.displayName,
            isEligible: !medication.isArchived && !medication.isAsNeeded && medication.refillRemindersEnabled && runningToday,
            daysRemaining: forecast.daysRemaining,
            needsCount: forecast.needsCount,
            lastCountDate: lastCountDate
        )
    }

    private static func asksFirst(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.needsCount != rhs.needsCount { return lhs.needsCount }
        switch (lhs.daysRemaining, rhs.daysRemaining) {
        case let (left?, right?) where left != right: return left < right
        case (.some, nil): return true
        case (nil, .some): return false
        default: break
        }
        let byName = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if byName != .orderedSame { return byName == .orderedAscending }
        return lhs.medicationID.uuidString < rhs.medicationID.uuidString
    }
}
