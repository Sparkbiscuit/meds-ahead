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
    /// archived, and not set aside. A course whose supply was not enough to
    /// see it through by its last morning ran out first: it ended with doses
    /// missing, not finished, and a card offering to archive it would read
    /// as a clean finish. Nothing is offered for it.
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
                      !setAside.contains(key(medicationID: medication.id, end: end, calendar: calendar)) else { return nil }
                let lastMorning = ForecastEngine.forecast(
                    medication: medication,
                    schedules: schedules,
                    inventoryEvents: inventoryEvents,
                    doseEvents: doseEvents,
                    now: calendar.startOfDay(for: end),
                    calendar: calendar
                )
                guard lastMorning.courseCovered else { return nil }
                return Item(medicationID: medication.id, displayName: medication.displayName, end: end)
            }
            .sorted { $0.end == $1.end ? $0.displayName < $1.displayName : $0.end > $1.end }
    }

    /// "Amoxicillin's course finished on Sep 20."
    static func title(for item: Item, calendar: Calendar = .autoupdatingCurrent) -> String {
        "\(item.displayName)'s course finished on \(ForecastEngine.dayText(item.end, calendar: calendar))."
    }

    /// Set aside for one course, not for the medication: a course taken up
    /// again that finishes later is offered again.
    static func key(medicationID: UUID, end: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: end)
        return "\(medicationID.uuidString)@\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
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
