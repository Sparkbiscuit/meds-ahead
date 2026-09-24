import SwiftData
import XCTest
@testable import Meds

/// A dose the widget logs is saved from another process, and Today's arrays need
/// not show it when the next tap comes. Two containers on one store file stand in
/// for the app and the widget: each opens its own connection to the file, as the
/// two processes do, which an in-memory store cannot show.
final class DoseLogGuardTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("dose-log-guard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func openStore() throws -> ModelContainer {
        let schema = Schema([Medication.self, DoseSchedule.self, DoseEvent.self, InventoryEvent.self])
        let configuration = ModelConfiguration(
            schema: schema,
            url: root.appendingPathComponent("Meds.store"),
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    func testADoseSavedThroughAnotherConnectionIsNotLoggedAgain() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 24)))
        let now = day.addingTimeInterval((8 * 60 + 5) * 60)

        let app = try openStore()
        let medication = Medication(name: "Example")
        let morning = DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, doseQuantity: 1, startDate: day)
        let evening = DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 21 * 60, doseQuantity: 2, startDate: day)
        app.mainContext.insert(medication)
        app.mainContext.insert(morning)
        app.mainContext.insert(evening)
        try app.mainContext.save()
        let doses = ScheduleEngine.doses(schedules: [morning, evening], medicationID: medication.id, onDayOf: now, calendar: calendar)
        let morningDose = try XCTUnwrap(doses.first)
        let eveningDose = try XCTUnwrap(doses.last)
        // What Today's query holds: read before the widget's write, never refreshed.
        let appArray = try app.mainContext.fetch(FetchDescriptor<DoseEvent>())

        let widget = try openStore()
        widget.mainContext.insert(DoseEvent(
            medicationID: medication.id,
            scheduleID: morningDose.scheduleID,
            scheduledAt: morningDose.date,
            doseQuantity: morningDose.quantity,
            status: .taken,
            note: "Logged from widget"
        ))
        try widget.mainContext.save()

        XCTAssertNil(
            ScheduleEngine.loggedStatus(for: morningDose, in: appArray, now: now, calendar: calendar),
            "the app's own array would have offered the dose again"
        )
        XCTAssertTrue(
            try DoseLogGuard.isLogged(morningDose, in: app.mainContext, now: now, calendar: calendar),
            "the store has the widget's log, so a second one must not be written"
        )
        XCTAssertFalse(
            try DoseLogGuard.isLogged(eveningDose, in: app.mainContext, now: now, calendar: calendar),
            "the evening dose is still unlogged and must stay loggable"
        )
    }
}
