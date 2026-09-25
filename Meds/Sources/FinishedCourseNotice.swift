import Foundation
import SwiftData

/// Today's card for a course that has just finished, offering to archive it.
/// A finished course asks for nothing and warns about nothing, so without
/// the card it stays on Today and Supply until someone thinks to archive it.
enum FinishedCourseNotice {
    /// How many days after its last day a course is still offered.
    static let recentDays = 3

    /// Where the set-aside cards are remembered, one line per course.
    static let setAsideKey = "finishedCourseCardsSetAside"

    struct Item: Equatable, Identifiable {
        let medicationID: UUID
        let displayName: String
        let end: Date

        var id: UUID { medicationID }
    }

    /// The courses to offer: finished within the last `recentDays` days, not
    /// archived, and not set aside. A course whose supply ran out before it
    /// was through ended with doses missing, not finished, and a card
    /// offering to archive it would read as a clean finish. Nothing is
    /// offered for it.
    static func items(
        medications: [Medication],
        schedules: [DoseSchedule],
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent],
        setAside: Set<String>,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Item] {
        let today = calendar.startOfDay(for: now)
        return medications
            .filter { !$0.isArchived && !$0.isAsNeeded }
            .compactMap { medication -> Item? in
                guard ScheduleEngine.isCourseFinished(schedules: schedules, medicationID: medication.id, now: now, calendar: calendar),
                      let end = ScheduleEngine.courseEnd(schedules: schedules, medicationID: medication.id),
                      SupplyAttention.days(from: end, to: today, calendar: calendar) <= recentDays,
                      !setAside.contains(key(medicationID: medication.id, end: end)) else { return nil }
                guard !ranOutFirst(
                    medication: medication,
                    schedules: schedules,
                    inventoryEvents: inventoryEvents,
                    doseEvents: doseEvents,
                    end: end,
                    now: now,
                    calendar: calendar
                ) else { return nil }
                return Item(medicationID: medication.id, displayName: medication.displayName, end: end)
            }
            .sorted { $0.end == $1.end ? $0.displayName < $1.displayName : $0.end > $1.end }
    }

    /// Whether the course's supply ran out before the course was through,
    /// asked of the forecast at the moments that can tell.
    ///
    /// Its last morning, with every refill and count the course had: the
    /// supply must see the last day's doses through. A refill or count added
    /// after the last day did not, and would make a course that ran short
    /// read as one that finished, so it is left out.
    ///
    /// And the moment before each refill or count added while the course
    /// ran, since one added once the bottle was empty becomes the forecast's
    /// anchor, and the doses missed before it drop out of every later
    /// forecast: a refill picked up two days after running out, or on the
    /// last afternoon, would otherwise pass for a course seen through.
    static func ranOutFirst(
        medication: Medication,
        schedules: [DoseSchedule],
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent],
        end: Date,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        let lastMoment = ScheduleEngine.courseLastMoment(end, calendar: calendar)
        let inventory = inventoryEvents.filter { $0.medicationID == medication.id && $0.date <= lastMoment }
        let lastMorning = ForecastEngine.forecast(
            medication: medication,
            schedules: schedules,
            inventoryEvents: inventory,
            doseEvents: doseEvents,
            now: calendar.startOfDay(for: end),
            calendar: calendar
        )
        guard lastMorning.courseCovered else { return true }
        // Only this course's own days: a course taken up again is judged by
        // the supply it had, not by how the one before it ended.
        let courseStart = ScheduleReconciler.currentSchedules(schedules, medicationID: medication.id, now: now, calendar: calendar)
            .map(\.startDate)
            .min() ?? .distantPast
        return inventory.contains { event in
            event.date > courseStart && ranOut(
                before: event.date,
                medication: medication,
                schedules: schedules,
                inventoryEvents: inventory,
                doseEvents: doseEvents,
                calendar: calendar
            )
        }
    }

    /// The forecast as it stood just before `moment`, from the events on
    /// record by then. A count needed means the doses nobody logged used up
    /// everything on record, so it cannot vouch that none went short. An
    /// empty ledger vouches only when every dose due since it was last
    /// known, overdue by `moment`, was logged taken: a dose that went by
    /// unlogged or skipped with nothing left is one the family went without,
    /// as the forecast itself reads an empty bottle.
    private static func ranOut(
        before moment: Date,
        medication: Medication,
        schedules: [DoseSchedule],
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent],
        calendar: Calendar
    ) -> Bool {
        let inventory = inventoryEvents.filter { $0.date < moment }
        let doses = doseEvents.filter { $0.medicationID == medication.id && $0.recordedAt < moment }
        let forecast = ForecastEngine.forecast(
            medication: medication,
            schedules: schedules,
            inventoryEvents: inventory,
            doseEvents: doses,
            now: moment,
            calendar: calendar
        )
        if forecast.needsCount { return true }
        guard forecast.currentSupply <= 0, !forecast.courseCovered else { return false }
        let anchor = ForecastEngine.ledgerAnchor(medication: medication, inventoryEvents: inventory, doseEvents: doses)
        return !ScheduleEngine.unloggedDoses(
            schedules: schedules,
            medicationID: medication.id,
            from: anchor.date,
            through: moment.addingTimeInterval(-ScheduleEngine.dueWindow),
            doseEvents: doses.filter { $0.status == .taken },
            now: moment,
            calendar: calendar
        ).isEmpty
    }

    /// "Amoxicillin's course finished on Sep 20."
    static func title(for item: Item, calendar: Calendar = .autoupdatingCurrent) -> String {
        "\(item.displayName)'s course finished on \(ForecastEngine.dayText(item.end, calendar: calendar))."
    }

    /// Set aside for one course, not for the medication: a course taken up
    /// again that finishes later is offered again. Keyed by the stored end
    /// rather than the day it reads as: noon at home can read as the next
    /// day abroad, and a card set aside before a flight would come back.
    static func key(medicationID: UUID, end: Date) -> String {
        "\(medicationID.uuidString)@\(Int(end.timeIntervalSinceReferenceDate.rounded()))"
    }

    /// As the detail screen's Archive does it: the medication is marked
    /// archived and nothing is written to its ledger, so a restore brings
    /// back the same history.
    @MainActor
    static func archive(_ medication: Medication, in context: ModelContext, now: Date = .now) throws {
        medication.isArchived = true
        medication.updatedAt = now
        try context.save()
    }

    static func setAside(in stored: String) -> Set<String> {
        Set(stored.split(separator: "\n").map(String.init))
    }

    static func adding(_ key: String, to stored: String) -> String {
        (setAside(in: stored).union([key])).sorted().joined(separator: "\n")
    }
}
