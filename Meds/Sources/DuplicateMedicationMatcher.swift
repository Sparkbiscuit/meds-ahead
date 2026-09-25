import Foundation

/// The medications already tracked that a new one under review may be.
///
/// A second bottle of something already here, saved as new, splits one supply
/// into two counts that each run out early and rings every reminder twice. So
/// the review screen asks first. It only asks: two people in one household can
/// take the same drug, so every match is returned, with whose it is, and the
/// person decides.
enum DuplicateMedicationMatcher {
    /// What a new medication is known by at the moment of review.
    struct Identity: Hashable, Sendable {
        var name: String
        var strength: String
        /// A code that filled the identity. Empty for a code that was only read.
        var ndc: String = ""
        var rxNormCodes: Set<String> = []

        init(name: String, strength: String, ndc: String = "", rxNormCodes: Set<String> = []) {
            self.name = name
            self.strength = strength
            self.ndc = ndc
            self.rxNormCodes = rxNormCodes.filter { !$0.isEmpty }
        }

        /// The review screen's fields. A code the label printed but did not
        /// vouch for fills nothing, so it matches nothing either: only one the
        /// label corroborated, or one the person chose under Use This Product,
        /// leaves the name as `.ndc`.
        init(
            name: String,
            strength: String,
            productIdentifier: String,
            productIdentifierType: String,
            rxNormCode: String,
            nameProvenance: MedicationNameProvenance
        ) {
            self.init(
                name: name,
                strength: strength,
                ndc: nameProvenance == .ndc && productIdentifierType == "NDC" ? productIdentifier : "",
                rxNormCodes: [rxNormCode, productIdentifierType == "RxNorm" ? productIdentifier : ""]
            )
        }

        init(draft: MedicationDraft) {
            self.init(
                name: draft.name,
                strength: draft.strength,
                productIdentifier: draft.productIdentifier,
                productIdentifierType: draft.productIdentifierType,
                rxNormCode: draft.rxNormCode,
                nameProvenance: draft.nameProvenance
            )
        }
    }

    /// Every active medication the identity matches: the same NDC product in any
    /// package size, the same RxNorm concept, or the same name at the same
    /// strength. Archived medications are left out; restoring one is its own
    /// decision.
    static func matches(for identity: Identity, among medications: [Medication]) -> [Medication] {
        let product = productKey(identity.ndc)
        let name = nameKey(identity.name)
        let strength = strengthKey(identity.strength)
        return medications
            .filter { medication in
                guard !medication.isArchived else { return false }
                // A different strength is a different medication whatever the
                // codes say: a 40 mg bottle in a 20 mg count doubles every dose
                // it forecasts. Written two ways for one amount is not different.
                if strengthsDiffer(identity.strength, medication.strength) { return false }
                if let product, medication.productIdentifierType == "NDC",
                   productKey(medication.productIdentifier) == product {
                    return true
                }
                if !identity.rxNormCodes.isDisjoint(with: rxNormCodes(of: medication)) { return true }
                return !name.isEmpty && name == nameKey(medication.name) && strength == strengthKey(medication.strength)
            }
            .sorted { lhs, rhs in
                (lhs.displayName.localizedLowercase, lhs.personName.localizedLowercase, lhs.createdAt)
                    < (rhs.displayName.localizedLowercase, rhs.personName.localizedLowercase, rhs.createdAt)
            }
    }

    /// "Furosemide 20 mg · for Sam": the medication as the banner names it,
    /// with whose it is when a person is set, since that is what tells two
    /// matches apart.
    static func description(of medication: Medication) -> String {
        var text = medication.displayName
        if !medication.strength.isEmpty { text += " \(medication.strength)" }
        if !medication.personName.isEmpty { text += " · for \(medication.personName)" }
        return text
    }

    // MARK: - Keys

    /// The nine digits that name a product whatever the package size. Nil for
    /// anything that is not one code: ten bare digits fit three layouts.
    static func productKey(_ code: String) -> String? {
        let candidates = NationalDrugCode.candidates(fromRendering: code.trimmingCharacters(in: .whitespacesAndNewlines))
        guard candidates.count == 1 else { return nil }
        return candidates[0].productKey
    }

    static func nameKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { !$0.isWhitespace }
    }

    /// The parser's canonical form, so "20MG" is "20 mg", but only when that
    /// form is all the field holds: "25 mg ER" is not "25 mg", and the first
    /// strength of "100 mg/5 mL, 200 mg" is not the whole of it.
    static func strengthKey(_ strength: String) -> String {
        let written = compact(strength)
        if let canonical = ScanParser.normalizedStrength(strength),
           compact(canonical) == written.replacingOccurrences(of: ",", with: "") {
            return compact(canonical)
        }
        return written
    }

    /// Two strengths that are both known and name different amounts. The label
    /// and the directory write one amount several ways ("800-160 mg" and
    /// "800 mg/160 mg"), so a code match survives that; a name match does not
    /// need to, and requires the same key.
    private static func strengthsDiffer(_ lhs: String, _ rhs: String) -> Bool {
        let left = strengthKey(lhs)
        let right = strengthKey(rhs)
        guard !left.isEmpty, !right.isEmpty, left != right else { return false }
        return StrengthComparison.compare(label: lhs, product: rhs) != .equivalent
            && StrengthComparison.compare(label: rhs, product: lhs) != .equivalent
    }

    private static func rxNormCodes(of medication: Medication) -> Set<String> {
        Set([medication.rxNormCode, medication.productIdentifierType == "RxNorm" ? medication.productIdentifier : ""]
            .filter { !$0.isEmpty })
    }

    private static func compact(_ value: String) -> String {
        value.lowercased().filter { !$0.isWhitespace }
    }
}
