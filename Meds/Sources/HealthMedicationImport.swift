import Foundation
import HealthKit

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

        if let code = summary.rxNormCode {
            draft.productIdentifier = code
            draft.productIdentifierType = "RxNorm"
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
    /// the same RxNorm code, or the same name in either the generic or brand field.
    static func existingMedication(for draft: MedicationDraft, among medications: [Medication]) -> Medication? {
        let active = medications.filter { !$0.isArchived }
        if draft.productIdentifierType == "RxNorm", !draft.productIdentifier.isEmpty,
           let byCode = active.first(where: { $0.productIdentifierType == "RxNorm" && $0.productIdentifier == draft.productIdentifier }) {
            return byCode
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

    /// Presents Health's medication picker, then returns whatever the person has
    /// shared. Cancelling the picker is not an error: earlier choices still apply.
    static func chooseMedications() async throws -> [HealthMedicationSummary] {
        guard isAvailable else { throw ImportError.unavailable }
        let store = HKHealthStore()
        try? await store.requestPerObjectReadAuthorization(for: .userAnnotatedMedicationType(), predicate: nil)
        let medications = try await HKUserAnnotatedMedicationQueryDescriptor().result(for: store)
        return medications.enumerated().map { index, medication in summary(index: index, medication) }
    }

    static func summary(index: Int, _ medication: HKUserAnnotatedMedication) -> HealthMedicationSummary {
        let concept = medication.medication
        let rxNormCode = concept.relatedCodings
            .filter { $0.system.lowercased().contains("rxnorm") }
            .map(\.code)
            .sorted { ($0.count, $0) < ($1.count, $1) }
            .first
        return HealthMedicationSummary(
            id: "\(index)-\(concept.displayText)",
            displayText: concept.displayText,
            nickname: medication.nickname ?? "",
            form: form(concept.generalForm),
            hasSchedule: medication.hasSchedule,
            isArchived: medication.isArchived,
            rxNormCode: rxNormCode
        )
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
