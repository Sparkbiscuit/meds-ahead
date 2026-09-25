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
        var brandName: String = ""
        /// A code that filled the identity. Empty for a code that was only read.
        var ndc: String = ""
        var rxNormCodes: Set<String> = []

        init(name: String, strength: String, brandName: String = "", ndc: String = "", rxNormCodes: Set<String> = []) {
            self.name = name
            self.strength = strength
            self.brandName = brandName
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
            brandName: String,
            productIdentifier: String,
            productIdentifierType: String,
            rxNormCode: String,
            nameProvenance: MedicationNameProvenance
        ) {
            self.init(
                name: name,
                strength: strength,
                brandName: brandName,
                ndc: nameProvenance == .ndc && productIdentifierType == "NDC" ? productIdentifier : "",
                rxNormCodes: [rxNormCode, productIdentifierType == "RxNorm" ? productIdentifier : ""]
            )
        }

        init(draft: MedicationDraft) {
            self.init(
                name: draft.name,
                strength: draft.strength,
                brandName: draft.brandName,
                productIdentifier: draft.productIdentifier,
                productIdentifierType: draft.productIdentifierType,
                rxNormCode: draft.rxNormCode,
                nameProvenance: draft.nameProvenance
            )
        }
    }

    /// Every active medication the identity matches: the same NDC product in any
    /// package size, the same clinical drug by RxNorm, or the same name at the
    /// same strength when nothing says they are different products. Archived
    /// medications are left out; restoring one is its own decision.
    static func matches(
        for identity: Identity,
        among medications: [Medication],
        directory: @autoclosure () -> NDCDirectory = .shared,
        rxNormTable: @autoclosure () -> RxNormTable = .shared
    ) -> [Medication] {
        let product = productKey(identity.ndc)
        // The tables are opened only for a draft with codes, which the scanner
        // or Use This Product has read them for already: a name typed by hand
        // never waits here on loading them.
        let directory = product == nil ? nil : directory()
        let table = identity.rxNormCodes.isEmpty ? nil : rxNormTable()
        let clinicalDrugs = Set(identity.rxNormCodes.compactMap { table?.clinicalDrugCode(for: $0) })
        let name = nameKey(identity.name)
        let strength = strengthKey(identity.strength)
        let brand = nameKey(identity.brandName)
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
                // By clinical drug, as the Health import matches: a generic
                // bottle is its brand, and a brand's code is not a generic's.
                let theirClinicalDrugs = Set(rxNormCodes(of: medication).compactMap { table?.clinicalDrugCode(for: $0) })
                if !clinicalDrugs.isDisjoint(with: theirClinicalDrugs) { return true }

                // Past here only the name links them, and the directory files
                // products that are not interchangeable under one name and
                // strength: Prograf and Astagraf XL are both tacrolimus 1 mg
                // capsules, one taken twice a day and the other once. Anything
                // that names them as different products outranks the name.
                if !clinicalDrugs.isEmpty, !theirClinicalDrugs.isEmpty { return false }
                if let product, let directory, let theirs = identifyingProductKey(of: medication, in: directory), theirs != product {
                    return false
                }
                let theirBrand = nameKey(medication.brandName)
                if !brand.isEmpty, !theirBrand.isEmpty, brand != theirBrand { return false }
                return !name.isEmpty && name == nameKey(medication.name) && strength == strengthKey(medication.strength)
            }
            .sorted { lhs, rhs in
                (lhs.displayName.localizedLowercase, lhs.personName.localizedLowercase, lhs.createdAt)
                    < (rhs.displayName.localizedLowercase, rhs.personName.localizedLowercase, rhs.createdAt)
            }
    }

    /// "Tacrolimus 1 mg (Prograf) · “Morning pill” · for Sam": the medication by
    /// its own name, which is what the bottle in hand can be checked against,
    /// then its brand and nickname, and whose it is when a person is set, since
    /// that is what tells two matches apart.
    static func description(of medication: Medication) -> String {
        var text = medication.name
        if !medication.strength.isEmpty { text += " \(medication.strength)" }
        if !medication.brandName.isEmpty, nameKey(medication.brandName) != nameKey(medication.name) {
            text += " (\(medication.brandName))"
        }
        if !medication.nickname.isEmpty, nameKey(medication.nickname) != nameKey(medication.name) {
            text += " · “\(medication.nickname)”"
        }
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
    /// strength of "100 mg/5 mL, 200 mg" is not the whole of it. Each number is
    /// then written one way, so "1.0 mg" is "1 mg" and ".5 mg" is "0.5 mg":
    /// equal amounts, never different ones.
    static func strengthKey(_ strength: String) -> String {
        let written = compact(strength)
        var key = written
        if let canonical = ScanParser.normalizedStrength(strength),
           compact(canonical) == written.replacingOccurrences(of: ",", with: "") {
            key = compact(canonical)
        }
        // "1,000" is one thousand, as the directory's strengths are read.
        key = key.replacing(/(\d),(\d{3})(?!\d)/) { "\($0.1)\($0.2)" }
        return key.replacing(/\d*\.?\d+/) { match in
            Decimal(string: String(match.output), locale: Locale(identifier: "en_US_POSIX")).map { "\($0)" } ?? String(match.output)
        }
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

    /// The product a tracked medication's code names, when the directory lists
    /// it under the medication's own name and strength. A code the label
    /// printed but never vouched for is kept on the medication as read, and a
    /// misreading cannot say that two bottles are different products.
    private static func identifyingProductKey(of medication: Medication, in directory: NDCDirectory) -> String? {
        guard medication.productIdentifierType == "NDC" else { return nil }
        let candidates = NationalDrugCode.candidates(fromRendering: medication.productIdentifier.trimmingCharacters(in: .whitespacesAndNewlines))
        guard candidates.count == 1, let listed = directory.product(for: candidates[0]),
              nameKey(NDCIdentification.displayName(for: listed)) == nameKey(medication.name),
              !strengthsDiffer(listed.strength, medication.strength) else { return nil }
        return candidates[0].productKey
    }

    private static func rxNormCodes(of medication: Medication) -> Set<String> {
        Set([medication.rxNormCode, medication.productIdentifierType == "RxNorm" ? medication.productIdentifier : ""]
            .filter { !$0.isEmpty })
    }

    private static func compact(_ value: String) -> String {
        value.lowercased().filter { !$0.isWhitespace }
    }
}
