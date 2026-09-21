import XCTest
@testable import Meds

/// The rules that keep a Health dose from being logged twice or doubled, as
/// pure functions over plain values. HealthKit itself is checked by hand in the
/// simulator's Health app.
final class HealthDoseReconcilerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private let medicationID = UUID()
    private let otherMedicationID = UUID()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private var windowStart: Date { date(1, 0) }
    private var now: Date { date(12, 22) }

    /// Built once per test: a schedule's identity is its UUID, and a plan made
    /// against one set of schedules must be checked against the same set.
    private lazy var schedules: [DoseSchedule] = [
        DoseSchedule(medicationID: medicationID, minutesAfterMidnight: 8 * 60 + 30, doseQuantity: 1, startDate: date(1, 0)),
        DoseSchedule(medicationID: medicationID, minutesAfterMidnight: 20 * 60, doseQuantity: 2, startDate: date(1, 0))
    ]

    private func record(
        _ date: Date,
        scheduled: Date? = nil,
        quantity: Double? = nil,
        status: HealthDoseRecord.Status = .taken,
        id: UUID = UUID()
    ) -> HealthDoseRecord {
        HealthDoseRecord(sampleID: id, date: date, scheduledDate: scheduled, quantity: quantity, status: status)
    }

    private func plan(_ records: [HealthDoseRecord], existing: [DoseEvent] = [], createdAt: Date = .distantPast) -> HealthDosePlan {
        HealthDoseReconciler.plan(
            records: records,
            existing: existing,
            schedules: schedules,
            medicationID: medicationID,
            createdAt: createdAt,
            windowStart: windowStart,
            now: now,
            calendar: calendar
        )
    }

    // MARK: - Never twice

    func testASampleAlreadyStoredIsSkipped() {
        let sampleID = UUID()
        let stored = DoseEvent(medicationID: medicationID, recordedAt: date(10, 9), doseQuantity: 1, status: .taken,
                               note: DoseEvent.appleHealthNote, healthSampleID: sampleID)
        let plan = plan([record(date(10, 9), id: sampleID)], existing: [stored])
        XCTAssertTrue(plan.isEmpty)
    }

    func testAStatusChangedInHealthIsRestatedHere() {
        let sampleID = UUID()
        let stored = DoseEvent(medicationID: medicationID, recordedAt: date(10, 9), doseQuantity: 1, status: .taken,
                               note: DoseEvent.appleHealthNote, healthSampleID: sampleID)
        let plan = plan([record(date(10, 9), status: .skipped, id: sampleID)], existing: [stored])
        XCTAssertEqual(plan.statusChanges, [.init(eventID: stored.id, status: .skipped)])
        XCTAssertTrue(plan.insertions.isEmpty)
    }

    /// The import that came with a medication in 1.1 stored Health's doses
    /// without their sample identifiers; the sync recognises them by their time
    /// rather than storing each a second time.
    func testADoseImportedBeforeTheSyncIsAdoptedNotDuplicated() {
        let imported = DoseEvent(medicationID: medicationID, recordedAt: date(9, 21, 5), doseQuantity: 1, status: .taken,
                                 note: DoseEvent.appleHealthNote, countsTowardSupply: false)
        let sampleID = UUID()
        let plan = plan([record(date(9, 21, 5), id: sampleID)], existing: [imported])
        XCTAssertEqual(plan.adoptions, [.init(eventID: imported.id, sampleID: sampleID, status: .taken)])
        XCTAssertTrue(plan.insertions.isEmpty)
        XCTAssertTrue(plan.deletions.isEmpty)
    }

    func testTwoRecordsCannotAdoptTheSameImportedDose() {
        let imported = DoseEvent(medicationID: medicationID, recordedAt: date(9, 21), doseQuantity: 1, status: .taken,
                                 note: DoseEvent.appleHealthNote, countsTowardSupply: false)
        let plan = plan([record(date(9, 21)), record(date(9, 21, 0))], existing: [imported])
        XCTAssertEqual(plan.adoptions.count, 1)
        XCTAssertEqual(plan.insertions.count, 1)
    }

    // MARK: - Never double

    func testAHealthDoseForASlotAlreadyLoggedHereIsSkipped() {
        let slot = ScheduleEngine.doses(schedules: schedules, medicationID: medicationID, onDayOf: date(10, 12), calendar: calendar)
            .first { calendar.component(.hour, from: $0.date) == 8 }!
        let logged = DoseEvent(medicationID: medicationID, scheduleID: slot.scheduleID, scheduledAt: slot.date,
                               recordedAt: date(10, 8, 35), doseQuantity: 1, status: .taken)
        // Health's own reminder was set for 8:00; this app's slot is 8:30.
        let plan = plan([record(date(10, 8, 3), scheduled: date(10, 8))], existing: [logged])
        XCTAssertTrue(plan.isEmpty)
    }

    func testAHealthDoseForAnUnloggedSlotClaimsThatSlot() throws {
        let plan = plan([record(date(10, 20, 10), scheduled: date(10, 20))])
        let insertion = try XCTUnwrap(plan.insertions.first)
        XCTAssertEqual(plan.insertions.count, 1)
        XCTAssertEqual(insertion.scheduleID, schedules.first { $0.minutesAfterMidnight == 20 * 60 }?.id)
        XCTAssertEqual(insertion.scheduledAt, date(10, 20))
        XCTAssertEqual(insertion.quantity, 2, "the slot's amount when Health recorded none")
        XCTAssertEqual(insertion.status, .taken)
    }

    func testAHealthQuantityWinsOverTheSlotAmount() throws {
        let plan = plan([record(date(10, 20, 10), scheduled: date(10, 20), quantity: 1.5)])
        XCTAssertEqual(try XCTUnwrap(plan.insertions.first).quantity, 1.5)
    }

    func testAScheduledHealthDoseFarFromAnySlotIsUnscheduledHere() throws {
        // Health's reminder at 14:00 is over five hours from either slot.
        let plan = plan([record(date(10, 14, 2), scheduled: date(10, 14))])
        let insertion = try XCTUnwrap(plan.insertions.first)
        XCTAssertNil(insertion.scheduleID)
        XCTAssertNil(insertion.scheduledAt)
        XCTAssertEqual(insertion.quantity, 1, "the amount of the nearest schedule by time of day, which is 8:30's")
    }

    func testAnAsNeededHealthDoseWithinHalfAnHourOfAnAppDoseIsTheSameDose() {
        let appLogged = DoseEvent(medicationID: medicationID, recordedAt: date(10, 15), doseQuantity: 1, status: .taken)
        XCTAssertTrue(plan([record(date(10, 15, 20))], existing: [appLogged]).isEmpty)
        XCTAssertTrue(plan([record(date(10, 14, 40))], existing: [appLogged]).isEmpty)
        XCTAssertEqual(plan([record(date(10, 15, 31))], existing: [appLogged]).insertions.count, 1, "outside the window it is a second dose")
    }

    func testADoseLoggedHereFromHealthDoesNotBlockANewHealthDoseNearIt() {
        let mirrored = DoseEvent(medicationID: medicationID, recordedAt: date(10, 15), doseQuantity: 1, status: .taken,
                                 note: DoseEvent.appleHealthNote, healthSampleID: UUID())
        let plan = plan([record(date(10, 15), id: mirrored.healthSampleID!), record(date(10, 15, 10))], existing: [mirrored])
        XCTAssertEqual(plan.insertions.count, 1, "Health logged two doses ten minutes apart; both are Health's")
    }

    func testSkippedInHealthBecomesSkippedHere() throws {
        let plan = plan([record(date(10, 8, 31), scheduled: date(10, 8, 30), status: .skipped)])
        XCTAssertEqual(try XCTUnwrap(plan.insertions.first).status, .skipped)
    }

    // MARK: - Before the medication existed

    /// The import was declined, or the bottle was scanned and linked to Health
    /// afterwards: nothing is stored, and the doses from before the medication
    /// was added were not taken from the count entered now.
    func testAHealthDoseLoggedBeforeTheMedicationWasAddedNeverChargesTheCount() {
        let createdAt = date(8, 12)
        let before = record(date(7, 20, 5), scheduled: date(7, 20))
        let after = record(date(9, 20, 5), scheduled: date(9, 20))
        let plan = plan([before, after], createdAt: createdAt)
        XCTAssertEqual(plan.insertions.map(\.record), [after])
    }

    func testStoredHistoryFromBeforeTheMedicationIsNeitherStoredAgainNorRemoved() {
        let createdAt = date(8, 12)
        let sampleID = UUID()
        let imported = DoseEvent(medicationID: medicationID, recordedAt: date(7, 20, 5), doseQuantity: 1, status: .taken,
                                 note: DoseEvent.appleHealthNote, countsTowardSupply: false)
        let first = plan([record(date(7, 20, 5), id: sampleID)], existing: [imported], createdAt: createdAt)
        XCTAssertTrue(first.insertions.isEmpty)
        XCTAssertTrue(first.deletions.isEmpty)
        XCTAssertEqual(first.adoptions, [.init(eventID: imported.id, sampleID: sampleID, status: .taken)],
                       "recognised as Health's sample, so an undo in Health still reaches it")

        imported.healthSampleID = sampleID
        XCTAssertTrue(plan([record(date(7, 20, 5), id: sampleID)], existing: [imported], createdAt: createdAt).isEmpty,
                      "and the next pass has nothing to do")
    }

    // MARK: - Undo

    func testASampleHealthTookBackIsRemovedHere() {
        let gone = DoseEvent(medicationID: medicationID, recordedAt: date(9, 9), doseQuantity: 1, status: .taken,
                             note: DoseEvent.appleHealthNote, healthSampleID: UUID())
        let kept = DoseEvent(medicationID: medicationID, recordedAt: date(9, 21), doseQuantity: 1, status: .taken,
                             note: DoseEvent.appleHealthNote, healthSampleID: UUID())
        let plan = plan([record(date(9, 21), id: kept.healthSampleID!)], existing: [gone, kept])
        XCTAssertEqual(plan.deletions, [gone.id])
        XCTAssertTrue(plan.insertions.isEmpty)
    }

    func testOnlyMirroredEventsInsideTheWindowCanBeRemoved() {
        let old = DoseEvent(medicationID: medicationID, recordedAt: date(1, 0).addingTimeInterval(-60), doseQuantity: 1, status: .taken,
                            note: DoseEvent.appleHealthNote, healthSampleID: UUID())
        let manual = DoseEvent(medicationID: medicationID, recordedAt: date(9, 9), doseQuantity: 1, status: .taken)
        let other = DoseEvent(medicationID: otherMedicationID, recordedAt: date(9, 9), doseQuantity: 1, status: .taken,
                              note: DoseEvent.appleHealthNote, healthSampleID: UUID())
        let plan = plan([], existing: [old, manual, other])
        XCTAssertTrue(plan.deletions.isEmpty)
    }

    func testRecordsOutsideTheWindowAreIgnored() {
        XCTAssertTrue(plan([record(date(1, 0).addingTimeInterval(-1)), record(now.addingTimeInterval(60))]).isEmpty)
    }

    func testAnotherMedicationsEventsAreInvisible() {
        let theirs = DoseEvent(medicationID: otherMedicationID, recordedAt: date(10, 15), doseQuantity: 1, status: .taken)
        XCTAssertEqual(plan([record(date(10, 15, 5))], existing: [theirs]).insertions.count, 1)
    }

    // MARK: - Identity

    @MainActor
    func testOnlyAnExactIdentityLinksAMedicationToHealth() {
        XCTAssertEqual(Medication(name: "Sertraline", productIdentifier: "312938", productIdentifierType: "RxNorm").healthMatchingCodes, ["312938"])
        XCTAssertEqual(Medication(name: "Sertraline", rxNormCode: "312938").healthMatchingCodes, ["312938"])
        XCTAssertTrue(Medication(name: "Sertraline").healthMatchingCodes.isEmpty, "a name is never an identity for something that changes supply")
        XCTAssertTrue(Medication(name: "Sertraline", productIdentifier: "00093-1039-01", productIdentifierType: "NDC").healthMatchingCodes.isEmpty)
    }
}
