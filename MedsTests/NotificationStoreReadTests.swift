import SwiftData
import XCTest
@testable import Meds

/// Launch, a return to the foreground and a reminder setting all replan from
/// the whole store. Each read used to fall back to an empty list, so a store
/// that returned the medications but not their schedules planned no dose
/// reminders, and replacing the pending requests with that plan withdrew
/// every one of them.
final class NotificationStoreReadTests: XCTestCase {
    private struct ReadFailed: Error {}

    /// The store, except that its schedules cannot be read.
    private struct SchedulesUnreadable: ModelFetching {
        let context: ModelContext

        func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
            if T.self == DoseSchedule.self { throw ReadFailed() }
            return try context.fetch(descriptor)
        }
    }

    @MainActor
    func testAStoreReadThatFailsPartwayYieldsNoPlans() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12)))
        let schema = Schema([Medication.self, DoseSchedule.self, DoseEvent.self, InventoryEvent.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let medication = Medication(name: "Example", createdAt: start)
        context.insert(medication)
        context.insert(DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, startDate: start, createdAt: start))
        try context.save()

        let whole = try NotificationPlanBuilder.makeAll(from: context, now: now, calendar: calendar)
        let pending = NotificationPlanner.plan(for: whole, now: now, calendar: calendar).notifications.map(\.identifier)
        XCTAssertTrue(pending.contains("meds.group.dose.daily.0800"), "a store read whole plans the reminder")

        XCTAssertThrowsError(
            try NotificationPlanBuilder.makeAll(from: SchedulesUnreadable(context: context), now: now, calendar: calendar),
            "plans from part of the store would withdraw the reminder"
        )
    }
}
