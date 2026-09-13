import Foundation
import HealthKit
import SwiftData

/// A medication as Apple Health describes it, reduced to plain values.
///
/// Everything the rest of the app needs from Health is copied into this struct at
/// the boundary, so the mapping to a draft is testable and no other file has to
/// import HealthKit.
struct HealthMedicationSummary: Hashable, Sendable, Identifiable {
    enum Form: String, Hashable, Sendable {
        case capsule, cream, device, drops, foam, gel, inhaler, injection, liquid, lotion
        case ointment, patch, powder, spray, suppository, tablet, topical, unknown
    }

    let id: String
    /// The name the person chose or typed in Health.
    let displayText: String
    let nickname: String
    let form: Form
    let hasSchedule: Bool
    let isArchived: Bool
    /// Health's RxNorm coding for the medication, when it has one.
    let rxNormCode: String?
    /// Doses Health recorded as taken in the last thirty days, oldest first.
    /// Empty when the person declined to share dose logs, or logged none.
    var recentTakenDoses: [ImportedDose] = []
    /// Every RxNorm coding Health carries for the medication; the sync matches
    /// on any of them.
    var rxNormCodes: Set<String> = []
}

/// Turns a Health medication into a draft for the review screen.
enum HealthMedicationMapper {
    /// RxNorm-style names carry the brand in brackets: `sertraline 50 MG Oral Tablet [Zoloft]`.
    private static let bracketedBrandPattern = /\[([^\]]+)\]/
    private static let strengthPattern =
        /(?i)\b\d[\d.,]*(?:\s*[-\/]\s*\d[\d.,]*)*\s*(?:mcg|mg|g|mL|units?|iu|%)(?:\s*\/\s*(?:\d[\d.,]*\s*)?(?:mcg|mg|g|mL|units?|iu))?(?![A-Za-z0-9])/
    private static let formAndRoutePattern =
        /(?i)\b(?:oral|chewable|sublingual|buccal|topical|transdermal|ophthalmic|otic|nasal|rectal|vaginal|inhalation|injectable|injection|extended[- ]release|delayed[- ]release|immediate[- ]release|film[- ]coated|disintegrating|prefilled|metered|dose|tablets?|capsules?|caplets?|softgels?|solution|suspension|syrup|elixir|cream|ointment|gel|lotion|foam|patch(?:es)?|drops?|spray|inhaler|powder|suppositor(?:y|ies)|syringe|pen|vial|kit|pack|er|xr|xl|sr|dr|cr|odt)\b/

    static func draft(for summary: HealthMedicationSummary) -> MedicationDraft {
        var draft = MedicationDraft()
        draft.source = .appleHealth
        draft.nameProvenance = .appleHealth
        draft.nickname = summary.nickname
        draft.isAsNeeded = !summary.hasSchedule

        let text = summary.displayText
        draft.strength = ScanParser.normalizedStrength(text) ?? ""
        let bracketedBrand = text.firstMatch(of: bracketedBrandPattern).map { String($0.1).trimmingCharacters(in: .whitespaces) }
        let cleaned = cleanedName(from: text)
        let identity = resolvedIdentity(cleaned, bracketedBrand: bracketedBrand)
        draft.name = identity.name
        draft.brandName = identity.brand
        draft.form = form(for: summary.form) ?? ScanParser.inferForm(from: text)
        draft.importedDoses = summary.recentTakenDoses

        if let code = summary.rxNormCode {
            draft.productIdentifier = code
            draft.productIdentifierType = "RxNorm"
            draft.rxNormCode = code
        }
        return draft
    }

    /// The name with its strength, form and route wording set aside.
    static func cleanedName(from displayText: String) -> String {
        var cleaned = displayText.replacing(bracketedBrandPattern, with: " ")
        cleaned = cleaned.replacing(strengthPattern, with: " ")
        cleaned = cleaned.replacing(formAndRoutePattern, with: " ")
        cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        let tidied = ScanParser.tidiedNameResidue(cleaned)
        return tidied.isEmpty ? displayText.trimmingCharacters(in: .whitespacesAndNewlines) : tidied
    }

    /// The curated generic-and-brand pair when the name is one the table knows,
    /// then the vocabulary's spelling. The table goes first because the vocabulary
    /// lists brand names too, and "Zoloft" must land in the brand field with
    /// sertraline beside it rather than stand alone as the generic. A name neither
    /// knows is kept exactly as the person typed it: it is their word for their
    /// medication, not a reading to gate.
    static func resolvedIdentity(_ cleaned: String, bracketedBrand: String?) -> (name: String, brand: String) {
        if let pair = MedicationBrandIndex.resolve(cleaned) {
            return (MedicationBrandIndex.displayName(forGeneric: pair.generic), pair.brand)
        }
        if let match = MedicationVocabulary.exactMatch(for: cleaned) {
            let generic = MedicationBrandIndex.displayName(forGeneric: match)
            return (generic, bracketedBrand ?? MedicationBrandIndex.brandName(forGeneric: match) ?? "")
        }
        if let bracketedBrand, let pair = MedicationBrandIndex.resolve(bracketedBrand) {
            return (MedicationBrandIndex.displayName(forGeneric: pair.generic), pair.brand)
        }
        let name = cleaned == cleaned.uppercased() ? cleaned.capitalized : cleaned
        return (name, bracketedBrand ?? "")
    }

    static func form(for form: HealthMedicationSummary.Form) -> MedicationForm? {
        switch form {
        case .tablet: .tablet
        case .capsule: .capsule
        case .liquid: .liquid
        case .injection: .injection
        case .inhaler: .inhaler
        case .patch: .patch
        case .drops: .drops
        case .cream, .foam, .gel, .lotion, .ointment, .topical: .topical
        case .device, .powder, .spray, .suppository: .other
        case .unknown: nil
        }
    }

    /// The medication already on file that this Health entry describes, if any:
    /// the same RxNorm concept — or the same clinical drug, so a generic bottle
    /// scanned here is the brand chosen in Health — or the same name in either
    /// the generic or brand field.
    static func existingMedication(
        for draft: MedicationDraft,
        among medications: [Medication],
        rxNormTable: RxNormTable = .shared
    ) -> Medication? {
        let active = medications.filter { !$0.isArchived }
        let draftCodes = Set([draft.rxNormCode, draft.productIdentifierType == "RxNorm" ? draft.productIdentifier : ""].filter { !$0.isEmpty })
        if !draftCodes.isEmpty {
            let wanted = Set(draftCodes.map { rxNormTable.clinicalDrugCode(for: $0) })
            if let byCode = active.first(where: { medication in
                !wanted.isDisjoint(with: medication.healthMatchingCodes.map { rxNormTable.clinicalDrugCode(for: $0) })
            }) {
                return byCode
            }
        }
        let keys = Set([draft.name, draft.brandName].map(key).filter { $0.count >= 4 })
        guard !keys.isEmpty else { return nil }
        return active.first { medication in
            !keys.isDisjoint(with: [key(medication.name), key(medication.brandName), key(medication.nickname)])
        }
    }

    private static func key(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// Reads the medications a person chooses to share from Apple Health.
///
/// Read-only, and per medication: Health shows its own picker, and only the
/// medications ticked there ever reach this app. Nothing is written back and
/// nothing leaves the iPhone; the Health entry is simply the starting point for
/// the same review every other medication goes through.
@available(iOS 26.0, *)
enum HealthMedicationImporter {
    enum ImportError: Error {
        case unavailable
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// How far back dose logs are read. Matches the as-needed forecast's window,
    /// which is the only thing the history is for.
    static let doseHistoryDays = 30

    /// Presents Health's medication picker, then returns whatever the person has
    /// shared. Cancelling the picker is not an error: earlier choices still apply.
    /// Dose logs come with the medication: the per-object grant that shares a
    /// medication is the grant for the doses logged against it, and asking for the
    /// dose-event type on its own is refused by HealthKit with an exception, so no
    /// second permission is requested. A medication whose logs cannot be read
    /// simply arrives without history.
    static func chooseMedications() async throws -> [HealthMedicationSummary] {
        guard isAvailable else { throw ImportError.unavailable }
        let store = HKHealthStore()
        try? await store.requestPerObjectReadAuthorization(for: .userAnnotatedMedicationType(), predicate: nil)
        let medications = try await HKUserAnnotatedMedicationQueryDescriptor().result(for: store)

        var summaries: [HealthMedicationSummary] = []
        for (index, medication) in medications.enumerated() {
            var summary = summary(index: index, medication)
            summary.recentTakenDoses = (try? await recentTakenDoses(for: medication.medication, in: store)) ?? []
            summaries.append(summary)
        }
        return summaries
    }

    /// Taken doses for one medication over the history window, oldest first.
    /// Only doses the person marked taken count; skipped, snoozed and untouched
    /// reminders are Health's business, not a usage rate.
    static func recentTakenDoses(for concept: HKMedicationConcept, in store: HKHealthStore) async throws -> [ImportedDose] {
        let now = Date.now
        guard let start = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -doseHistoryDays, to: now) else { return [] }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "%K == %@", HKPredicateKeyPathMedicationConceptIdentifier, concept.identifier),
            HKQuery.predicateForSamples(withStart: start, end: now, options: [])
        ])
        // Sorted here rather than by a key-path sort descriptor, which Swift 6
        // flags as non-Sendable across the query's actor hop.
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: HKObjectType.medicationDoseEventType(), predicate: predicate)],
            sortDescriptors: []
        )
        return try await descriptor.result(for: store)
            .compactMap { sample -> ImportedDose? in
                guard let event = sample as? HKMedicationDoseEvent, event.logStatus == .taken else { return nil }
                let quantity = event.doseQuantity ?? event.scheduledDoseQuantity ?? 1
                return ImportedDose(date: event.startDate, quantity: quantity > 0 ? quantity : 1, sampleID: event.uuid)
            }
            .sorted { $0.date < $1.date }
    }

    /// Taken and skipped doses for one medication over a window, as plain records
    /// for the sync. Reminders the person never touched, snoozed, or undid are
    /// not doses.
    static func doseRecords(
        for concept: HKMedicationConcept,
        in store: HKHealthStore,
        from start: Date,
        to end: Date
    ) async throws -> [HealthDoseRecord] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "%K == %@", HKPredicateKeyPathMedicationConceptIdentifier, concept.identifier),
            HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        ])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: HKObjectType.medicationDoseEventType(), predicate: predicate)],
            sortDescriptors: []
        )
        return try await descriptor.result(for: store).compactMap { sample -> HealthDoseRecord? in
            guard let event = sample as? HKMedicationDoseEvent else { return nil }
            let status: HealthDoseRecord.Status
            switch event.logStatus {
            case .taken: status = .taken
            case .skipped: status = .skipped
            default: return nil
            }
            return HealthDoseRecord(
                sampleID: event.uuid,
                date: event.startDate,
                scheduledDate: event.scheduleType == .schedule ? (event.scheduledDate ?? event.startDate) : nil,
                quantity: event.doseQuantity.flatMap { $0 > 0 ? $0 : nil },
                status: status
            )
        }
    }

    static func summary(index: Int, _ medication: HKUserAnnotatedMedication) -> HealthMedicationSummary {
        let concept = medication.medication
        let codes = rxNormCodes(of: concept)
        let rxNormCode = codes.sorted { ($0.count, $0) < ($1.count, $1) }.first
        return HealthMedicationSummary(
            id: "\(index)-\(concept.displayText)",
            displayText: concept.displayText,
            nickname: medication.nickname ?? "",
            form: form(concept.generalForm),
            hasSchedule: medication.hasSchedule,
            isArchived: medication.isArchived,
            rxNormCode: rxNormCode,
            rxNormCodes: codes
        )
    }

    static func rxNormCodes(of concept: HKMedicationConcept) -> Set<String> {
        Set(concept.relatedCodings
            .filter { $0.system.lowercased().contains("rxnorm") }
            .map(\.code))
    }

    private static func form(_ form: HKMedicationGeneralForm) -> HealthMedicationSummary.Form {
        switch form {
        case .capsule: .capsule
        case .cream: .cream
        case .device: .device
        case .drops: .drops
        case .foam: .foam
        case .gel: .gel
        case .inhaler: .inhaler
        case .injection: .injection
        case .liquid: .liquid
        case .lotion: .lotion
        case .ointment: .ointment
        case .patch: .patch
        case .powder: .powder
        case .spray: .spray
        case .suppository: .suppository
        case .tablet: .tablet
        case .topical: .topical
        default: .unknown
        }
    }
}

/// Keeps the ledger in step with the doses a person logs in Apple Health for a
/// medication that is also here.
///
/// Runs on launch and on returning to the foreground, beside notification
/// replanning. Only medications with an exact identity Health shares — an RxNorm
/// code — take part; nothing is ever matched by name, because a wrong match here
/// changes a supply count. The medications come from the per-object grant the
/// import already holds, so no picker and no new permission is shown, and the
/// dose events come under the same grant; the dose-event type is never requested
/// on its own, which HealthKit refuses with an exception. Still read-only: a
/// dose logged here is never written to Health.
@available(iOS 26.0, *)
enum HealthDoseSync {
    static let lastCheckKey = "healthDoseSync.lastCheck"

    struct Outcome: Equatable, Sendable {
        var linkedMedications = 0
        var inserted = 0
        var adopted = 0
        var updated = 0
        var removed = 0
    }

    /// The window checked on every pass: the same thirty days the as-needed
    /// forecast measures over, so an undo in Health is caught for as long as the
    /// dose still matters to the estimate.
    static let windowDays = 30

    @MainActor
    static func run(in context: ModelContext, now: Date = .now) async -> Outcome? {
        guard HealthMedicationImporter.isAvailable else { return nil }
        let medications = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        let linked = medications.filter { !$0.isArchived && !$0.healthMatchingCodes.isEmpty }
        guard !linked.isEmpty else { return nil }
        let store = HKHealthStore()
        guard let shared = try? await HKUserAnnotatedMedicationQueryDescriptor().result(for: store),
              let windowStart = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -windowDays, to: now) else {
            return nil
        }

        var outcome = Outcome()
        let schedules = (try? context.fetch(FetchDescriptor<DoseSchedule>())) ?? []
        let doseEvents = (try? context.fetch(FetchDescriptor<DoseEvent>())) ?? []
        let table = RxNormTable.shared
        for annotated in shared {
            // Both sides are widened to the clinical drug, so a generic bottle
            // scanned here and the brand chosen in Health read as one medication.
            let codes = expanded(HealthMedicationImporter.rxNormCodes(of: annotated.medication), table: table)
            let matches = linked.filter { !codes.isDisjoint(with: expanded($0.healthMatchingCodes, table: table)) }
            // Two medications here with one identity in Health — the same drug for
            // two people — cannot be told apart, so neither is touched.
            guard matches.count == 1, let medication = matches.first else { continue }
            outcome.linkedMedications += 1
            let records = (try? await HealthMedicationImporter.doseRecords(
                for: annotated.medication,
                in: store,
                from: windowStart,
                to: now
            )) ?? []
            let plan = HealthDoseReconciler.plan(
                records: records,
                existing: doseEvents,
                schedules: schedules,
                medicationID: medication.id,
                windowStart: windowStart,
                now: now
            )
            apply(plan, to: medication, existing: doseEvents, in: context, outcome: &outcome)
        }
        if (try? context.save()) != nil {
            UserDefaults.standard.set(now, forKey: lastCheckKey)
        }
        return outcome
    }

    static func expanded(_ codes: Set<String>, table: RxNormTable) -> Set<String> {
        codes.union(codes.map { table.clinicalDrugCode(for: $0) })
    }

    @MainActor
    private static func apply(
        _ plan: HealthDosePlan,
        to medication: Medication,
        existing: [DoseEvent],
        in context: ModelContext,
        outcome: inout Outcome
    ) {
        for insertion in plan.insertions {
            // A dose logged after the medication existed here was taken from the
            // count this app is keeping, so it counts toward the supply.
            context.insert(DoseEvent(
                medicationID: medication.id,
                scheduleID: insertion.scheduleID,
                scheduledAt: insertion.scheduledAt,
                recordedAt: insertion.record.date,
                doseQuantity: insertion.quantity,
                status: insertion.status,
                note: DoseEvent.appleHealthNote,
                countsTowardSupply: true,
                healthSampleID: insertion.record.sampleID
            ))
            outcome.inserted += 1
        }
        for adoption in plan.adoptions {
            guard let event = existing.first(where: { $0.id == adoption.eventID }) else { continue }
            event.healthSampleID = adoption.sampleID
            if event.status != adoption.status { event.status = adoption.status }
            outcome.adopted += 1
        }
        for change in plan.statusChanges {
            guard let event = existing.first(where: { $0.id == change.eventID }) else { continue }
            event.status = change.status
            outcome.updated += 1
        }
        for eventID in plan.deletions {
            guard let event = existing.first(where: { $0.id == eventID }) else { continue }
            context.delete(event)
            outcome.removed += 1
        }
        if !plan.isEmpty { medication.updatedAt = .now }
    }
}
