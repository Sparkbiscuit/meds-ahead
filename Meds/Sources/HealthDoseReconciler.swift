import Foundation

/// A dose event as Apple Health reported it, reduced to plain values at the
/// boundary so the rules below can be tested without HealthKit.
struct HealthDoseRecord: Hashable, Sendable {
    enum Status: Hashable, Sendable {
        case taken
        case skipped
    }

    /// Health's identifier for the sample.
    let sampleID: UUID
    /// When the dose was taken or skipped.
    let date: Date
    /// The reminder slot Health logged it against, when it was logged from one.
    let scheduledDate: Date?
    /// The amount Health recorded, when it recorded one.
    let quantity: Double?
    let status: Status
}

/// What the sync should do to the ledger for one medication. Computed as plain
/// values first so every rule can be checked on its own, then applied in one
/// place.
struct HealthDosePlan: Equatable {
    struct Insertion: Equatable {
        let record: HealthDoseRecord
        let scheduleID: UUID?
        let scheduledAt: Date?
        let quantity: Double
        let status: DoseEventStatus
    }

    /// A dose imported before the sync existed, now recognised as Health's sample.
    struct Adoption: Equatable {
        let eventID: UUID
        let sampleID: UUID
        let status: DoseEventStatus
    }

    struct StatusChange: Equatable {
        let eventID: UUID
        let status: DoseEventStatus
    }

    var insertions: [Insertion] = []
    var adoptions: [Adoption] = []
    var statusChanges: [StatusChange] = []
    /// Events that mirror a sample Health no longer has.
    var deletions: [UUID] = []

    var isEmpty: Bool {
        insertions.isEmpty && adoptions.isEmpty && statusChanges.isEmpty && deletions.isEmpty
    }
}

/// Decides which of Health's dose events become dose events here, and which
/// stored copies Health has since taken back. Never twice, never double: a
/// sample already stored is skipped, a Health dose that maps to a slot the
/// person already logged here is the same dose, and an unscheduled Health dose
/// within half an hour of a dose logged here is the same dose too.
enum HealthDoseReconciler {
    /// An as-needed dose logged in both places within this interval is one dose.
    static let sameDoseWindow: TimeInterval = 30 * 60
    /// How far a Health reminder slot may sit from this app's schedule and
    /// still be the same slot: the engine's reach for any dose logged outside
    /// a slot, so a Health dose and a Take Now dose are matched alike.
    static let slotTolerance: TimeInterval = ScheduleEngine.nearbySlotTolerance
    /// A dose imported before samples carried identifiers is recognised by its
    /// time, which was Health's time.
    static let importedDoseTolerance: TimeInterval = 60

    static func plan(
        records: [HealthDoseRecord],
        existing: [DoseEvent],
        schedules: [DoseSchedule],
        medicationID: UUID,
        createdAt: Date = .distantPast,
        windowStart: Date,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> HealthDosePlan {
        var plan = HealthDosePlan()
        let events = existing.filter { $0.medicationID == medicationID }
        var byHealthSample: [UUID: DoseEvent] = [:]
        for event in events {
            if let sampleID = event.healthSampleID { byHealthSample[sampleID] = event }
        }
        var adopted: Set<UUID> = []
        // Doses this app logged itself, which a Health copy must never double.
        let appLogged = events.filter { $0.healthSampleID == nil && $0.note != DoseEvent.appleHealthNote }

        for record in records.sorted(by: { $0.date < $1.date }) {
            guard record.date >= windowStart, record.date <= now else { continue }
            let status: DoseEventStatus = record.status == .taken ? .taken : .skipped

            if let stored = byHealthSample[record.sampleID] {
                if stored.status != status {
                    plan.statusChanges.append(.init(eventID: stored.id, status: status))
                }
                continue
            }

            // Earlier builds' import stored Health's doses without their sample
            // identifiers. Recognise them by their time.
            if let imported = events.first(where: {
                $0.healthSampleID == nil
                    && $0.note == DoseEvent.appleHealthNote
                    && !adopted.contains($0.id)
                    && abs($0.recordedAt.timeIntervalSince(record.date)) <= importedDoseTolerance
            }) {
                adopted.insert(imported.id)
                plan.adoptions.append(.init(eventID: imported.id, sampleID: record.sampleID, status: status))
                continue
            }

            // A dose from before the medication existed here was not taken from
            // the count this app keeps. The import that comes with a medication
            // stores that history as non-counting; with the import declined, or
            // a bottle scanned and linked to Health afterwards, there is nothing
            // to adopt, and storing the dose now would charge it to the count.
            guard record.date >= createdAt else { continue }

            var slot: ScheduledDose?
            if let scheduledDate = record.scheduledDate {
                slot = ScheduleEngine.nearestScheduledDose(
                    to: scheduledDate,
                    schedules: schedules,
                    medicationID: medicationID,
                    tolerance: slotTolerance,
                    calendar: calendar
                )
                if let slot, ScheduleEngine.loggedStatus(for: slot, in: events, now: now, calendar: calendar) != nil {
                    // The person logged this slot here already; Health's copy is
                    // the same dose.
                    continue
                }
            }

            if appLogged.contains(where: { abs($0.recordedAt.timeIntervalSince(record.date)) <= sameDoseWindow }) {
                continue
            }

            let quantity = record.quantity
                ?? slot?.quantity
                ?? ScheduleEngine.nearestScheduledQuantity(
                    schedules: schedules,
                    medicationID: medicationID,
                    now: record.date,
                    calendar: calendar
                )
                ?? 1
            plan.insertions.append(.init(
                record: record,
                scheduleID: slot?.scheduleID,
                scheduledAt: slot?.date,
                quantity: quantity > 0 ? quantity : 1,
                status: status
            ))
        }

        // A sample that has gone from Health was undone there; its copy goes too.
        let reported = Set(records.map(\.sampleID))
        for event in events {
            guard let sampleID = event.healthSampleID, event.recordedAt >= windowStart, event.recordedAt <= now,
                  !reported.contains(sampleID) else { continue }
            plan.deletions.append(event.id)
        }
        return plan
    }
}
