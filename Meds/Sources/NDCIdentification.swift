import Foundation

/// Turns the codes a label carries into the one product they name, and decides
/// whether the label agrees before that product is allowed to fill the review.
///
/// An NDC is exact — manufacturer, drug, strength and package — so a resolved code
/// is more trustworthy than any reading of the printed name. It is also the one
/// place a single misread digit could produce a confidently wrong medication, and
/// a wrong identification is worse than none. So a code read by OCR must be
/// backed by something else on the label, and a code from any source is refused
/// when the label plainly names a different drug, strength or form.
enum NDCIdentification {
    struct Match: Hashable, Sendable {
        let code: NationalDrugCode
        let product: NDCProduct
        let source: NDCReadingSource
        /// False when printed readings of this product disagree on the package
        /// digits. The directory and the label vouch for the product, never the
        /// package, so a reading that differs only there has nothing to settle it.
        var packageIsSettled = true

        /// The code a medication keeps and the shared list prints. A package
        /// read two ways is left off rather than guessed: the product NDC names
        /// the drug exactly, and a wrong package code handed to a pharmacist
        /// names a bottle that was never dispensed.
        var recordedCode: String {
            packageIsSettled ? code.hyphenated : code.productHyphenated
        }
    }

    enum Verdict: Hashable, Sendable {
        case accepted
        /// The code resolved, but nothing else on the label backs it up. A barcode
        /// needs no backing; printed digits do.
        case uncorroborated
        /// The label plainly names a different drug, strength, form, release or
        /// brand than the directory does.
        case contradicted
    }

    /// The one product every code in the evidence resolves to, or nil.
    ///
    /// Ten bare digits can name three products; if more than one exists, that
    /// reading proves nothing. Two readings that resolve to different products
    /// prove nothing either. A barcode match outranks a printed one because it
    /// needs no corroboration.
    static func match(in evidence: [ScanEvidence], directory: NDCDirectory = .shared) -> Match? {
        guard !directory.isEmpty else { return nil }
        let readings = readings(in: evidence)

        var resolved: [Match] = []
        for reading in readings {
            let hits = reading.candidates.compactMap { code in
                directory.product(for: code).map { Match(code: code, product: $0, source: reading.source) }
            }
            guard Set(hits.map(\.product.productKey)).count == 1, let hit = hits.first else { continue }
            resolved.append(hit)
        }
        guard Set(resolved.map(\.product.productKey)).count == 1 else { return nil }
        return resolved.first { $0.source == .barcode } ?? resolved.first
    }

    /// The one product the label vouches for, with the verdict on it, when the
    /// evidence carries more than one reading of the code.
    ///
    /// A blurred line is misread as a well-formed code, and the still pipeline
    /// reads such a line twice, so two codes naming two products is an ordinary
    /// result rather than a sign of two labels. The label settles it: a product
    /// the label plainly contradicts is set aside, and only if more than one
    /// product survives that is the reading ambiguous. When every product is
    /// contradicted the first is returned with that verdict, so the review
    /// screen can say which code was read and refused.
    static func identify(
        in evidence: [ScanEvidence],
        against draft: MedicationDraft,
        labelText: String,
        directory: NDCDirectory = .shared
    ) -> (match: Match, verdict: Verdict)? {
        guard !directory.isEmpty else { return nil }
        var byProduct: [String: Match] = [:]
        var printedPackages: [String: Set<String>] = [:]
        var order: [String] = []
        for reading in readings(in: evidence) {
            let hits = reading.candidates.compactMap { code in
                directory.product(for: code).map { Match(code: code, product: $0, source: reading.source) }
            }
            guard Set(hits.map(\.product.productKey)).count == 1, let hit = hits.first else { continue }
            let key = hit.product.productKey
            if byProduct[key] == nil { order.append(key) }
            if hit.source == .printedText { printedPackages[key, default: []].insert(String(hit.code.digits.suffix(2))) }
            // A barcode reading of the same product outranks a printed one.
            if byProduct[key] == nil || (hit.source == .barcode && byProduct[key]?.source != .barcode) {
                byProduct[key] = hit
            }
        }
        // A barcode's check digit covers the package; printed digits are settled
        // only when every reading of the product agrees on them.
        for (key, match) in byProduct where match.source == .printedText && (printedPackages[key]?.count ?? 0) > 1 {
            byProduct[key]?.packageIsSettled = false
        }
        let judged = order.compactMap { key in
            byProduct[key].map { ($0, verdict(for: $0, against: draft, labelText: labelText, directory: directory)) }
        }
        guard !judged.isEmpty else { return nil }
        let surviving = judged.filter { $0.1 != .contradicted }
        if surviving.isEmpty { return judged[0] }
        guard surviving.count == 1 else { return nil }
        return surviving[0]
    }

    /// Every code the evidence carries. The text is read as one document in line
    /// order rather than line by line: a code broken across two recognized lines
    /// ("NDC 00093-" then "1039-01") is only a code when the lines are looked at
    /// together, and the reader already allows one break inside a rendering.
    static func readings(in evidence: [ScanEvidence]) -> [NDCReading] {
        let text = LabelCandidateBuilder.textLines(from: evidence).joined(separator: "\n")
        var readings = NationalDrugCode.readings(inLabelText: text)
        for item in evidence where item.kind == .barcode {
            readings += NationalDrugCode.readings(inBarcode: item.value)
        }
        return readings
    }

    /// Why nothing resolved, when a code was read at all: the review screen must
    /// not show the same blank for "no code on the label" and "a code that
    /// matched nothing", because only the second is worth a second look at the
    /// digits.
    static func unresolvedOutcome(in evidence: [ScanEvidence], directory: NDCDirectory = .shared) -> NDCIdentificationOutcome? {
        guard !directory.isEmpty else { return nil }
        let readings = readings(in: evidence)
        guard !readings.isEmpty else { return nil }
        let listed = Set(readings.flatMap { reading in
            reading.candidates.compactMap { directory.product(for: $0)?.productKey }
        })
        // Two listed products the label does not choose between; a reading that
        // fits two products on its own is counted by `match`.
        if listed.count > 1 || match(in: evidence, directory: directory) == nil && listed.count == 1 && readings.contains(where: { reading in
            Set(reading.candidates.compactMap { directory.product(for: $0)?.productKey }).count > 1
        }) { return .ambiguous }
        let printed = readings.first { $0.source == .printedText }
        let code = printed?.raw ?? readings.first?.candidates.first?.hyphenated ?? ""
        return listed.isEmpty ? .unlisted(code: code) : nil
    }

    /// The product in the words the review screen uses: "Sertraline 50 mg (Zoloft)".
    static func summary(of product: NDCProduct) -> String {
        var text = displayName(for: product)
        if !product.strength.isEmpty { text += " " + product.strength }
        // The release is the one difference between this product and the one
        // on the bottle when a single digit was misread, so it is said unless
        // the brand already says it.
        if let release = product.comparableRelease, release.isModified, ReleaseForm.named(in: product.brandName) != release {
            text += release == .extended ? " extended-release" : " delayed-release"
        }
        if !product.brandName.isEmpty { text += " (\(product.brandName))" }
        return text
    }

    static func verdict(
        for match: Match,
        against draft: MedicationDraft,
        labelText: String,
        directory: NDCDirectory = .shared
    ) -> Verdict {
        let product = match.product

        // The label's own confirmed name is a different drug.
        if draft.nameProvenance == .vocabulary || draft.nameProvenance == .strengthAnchored,
           !draft.name.isEmpty,
           !namesAgree(labelText: draft.name + " " + draft.brandName, product: product) {
            return .contradicted
        }

        let strengthVerdict = StrengthComparison.compare(label: draft.strength, product: product.strength)
        if strengthVerdict == .different {
            return .contradicted
        }

        if let printedForm = explicitForm(in: labelText),
           let productForm = comparableForm(product.form),
           printedForm != productForm {
            return .contradicted
        }

        let labelWords = Set(words(labelText))
        let reference = referenceBrand(of: product)
        let siblings = brandedSiblings(of: product, directory: directory)
        let release = releaseEvidence(in: labelText, labelWords: labelWords, for: product, reference: reference, siblings: siblings, draft: draft)
        if releaseContradicts(release, product: product)
            || printsAnotherBrand(reference, siblings: siblings, on: labelWords, product: product) {
            return .contradicted
        }

        if match.source == .barcode { return .accepted }
        let corroborated = strengthVerdict == .equivalent || namesAgree(labelText: labelText, product: product)
        guard corroborated else { return .uncorroborated }
        return releaseIsBackedUp(release, labelWords: labelWords, product: product, draft: draft) ? .accepted : .uncorroborated
    }

    // MARK: - Release and brand

    /// What the label says about release on the lines that name this drug.
    /// Where it says nothing in letters, a reference brand it prints says it
    /// for it: PROGRAF is immediate-release tacrolimus, as TOPROL XL is
    /// extended-release metoprolol. So does a brand of the labeler's other
    /// products of the drug, wherever it is printed: ASTAGRAF XL on a line of
    /// its own under "TACROLIMUS 1 MG CAPSULE" is extended release. The
    /// product's own brand printed is the label naming this very product, and
    /// implies nothing further.
    private static func releaseEvidence(
        in labelText: String,
        labelWords: Set<String>,
        for product: NDCProduct,
        reference: String?,
        siblings: [NDCProduct],
        draft: MedicationDraft
    ) -> ReleaseForm.Evidence {
        let reference = reference ?? ""
        let nameWords = (words(product.genericName) + words(product.brandName) + words(draft.name) + words(reference))
            .filter { !uninformativeTokens.contains($0) && !interchangeableSalts.contains($0) }
        var evidence = ReleaseForm.evidence(in: labelText, namedBy: Set(nameWords))
        guard !printsOwnBrand(product, on: labelWords) else { return evidence }
        // Only a modified release is taken from a sibling's listing: an empty
        // column claims nothing, and Tecfidera is delayed-release filed plain.
        for sibling in siblings where printsOwnBrand(sibling, on: labelWords) {
            if let release = sibling.comparableRelease, release.isModified { evidence.stated.insert(release) }
        }
        if evidence.stated.isEmpty,
           let key = brandKey(reference), key.isSubset(of: labelWords),
           let implied = MedicationBrandIndex.release(ofName: "", brand: reference) {
            evidence.stated.insert(implied)
        }
        return evidence
    }

    /// Whether the label states a release the product is not.
    ///
    /// A listing that claims no release is refused by a label that says ER,
    /// and not by one that says DR. The FDA files some delayed-release
    /// products as plain capsules and tablets, Tecfidera among them, so such a
    /// listing is no proof against DR; extended release is the one that
    /// changes how often a dose is taken, and the one Prograf and Astagraf XL
    /// differ in.
    private static func releaseContradicts(_ evidence: ReleaseForm.Evidence, product: NDCProduct) -> Bool {
        guard let release = product.comparableRelease,
              !evidence.stated.isEmpty, !evidence.stated.contains(release) else { return false }
        return release.isModified || evidence.stated.contains(.extended)
    }

    /// A printed code for an extended- or delayed-release product fills
    /// nothing until the label says that release too: in letters, in a
    /// phrase, by printing the product's own brand, or by naming a drug the
    /// table knows only in that release, as metoprolol succinate is only ever
    /// extended-release. A code misread by one digit lands on the same drug in
    /// its other release, and the name, strength and form cannot tell the two
    /// apart.
    private static func releaseIsBackedUp(
        _ evidence: ReleaseForm.Evidence,
        labelWords: Set<String>,
        product: NDCProduct,
        draft: MedicationDraft
    ) -> Bool {
        guard let release = product.comparableRelease, release.isModified else { return true }
        if evidence.suggested.contains(release) { return true }
        if printsOwnBrand(product, on: labelWords) { return true }
        return (draft.nameProvenance == .vocabulary || draft.nameProvenance == .strengthAnchored)
            && MedicationBrandIndex.release(ofName: draft.name, brand: "") == release
    }

    /// Whether a brand the table would lend a label's name is one the label
    /// argues against: a code read on it names the drug in another release, or
    /// it prints another brand of the drug. "TACROLIMUS 1 MG CAPSULE" borrows
    /// Prograf, which is immediate-release; beside a code for Astagraf XL,
    /// whether or not the label could confirm the code, or under a line that
    /// reads ASTAGRAF XL, the release is in doubt, and a brand that settles it
    /// wrongly is worse than none. A brand the label prints is never doubted.
    static func doubts(
        borrowedBrand brand: String,
        for name: String,
        evidence: [ScanEvidence],
        labelText: String,
        directory: NDCDirectory = .shared
    ) -> Bool {
        guard !brand.isEmpty, !name.isEmpty, !directory.isEmpty, let borrowed = brandKey(brand) else { return false }
        let labelWords = Set(words(labelText))
        guard !borrowed.isSubset(of: labelWords) else { return false }
        let borrowedRelease = MedicationBrandIndex.release(ofName: "", brand: brand)
        let products = readings(in: evidence)
            .flatMap(\.candidates)
            .compactMap { directory.product(for: $0) }
            .filter { namesAgree(labelText: name, product: $0) }
        return products.contains { product in
            if let release = product.comparableRelease, let borrowedRelease, release != borrowedRelease { return true }
            return ([product] + brandedSiblings(of: product, directory: directory)).contains { other in
                printsOwnBrand(other, on: labelWords) && brandKey(other.brandName) != borrowed
            }
        }
    }

    /// Whether the label prints another brand of this drug while the code
    /// names a brand it does not print: PROGRAF on the label with Astagraf XL
    /// from the code, or the other way round. The other brands are the
    /// table's reference brand and the brands of the labeler's other products
    /// of the drug, which a code misread by one digit lands on. Like a salt, a
    /// brand makes a different product; unlike a salt it is refused only when
    /// the product's own brand is nowhere on the label. A store's brand ("CVS
    /// Health Ibuprofen") is the generic under a shop's name and prints
    /// "compare to Advil" beside it, and a variant of the product's own brand
    /// ("Bactrim DS", "Adderall XR") differs from it in strength or release,
    /// which are checked on their own, so neither is held to this.
    private static func printsAnotherBrand(
        _ reference: String?,
        siblings: [NDCProduct],
        on labelWords: Set<String>,
        product: NDCProduct
    ) -> Bool {
        guard let own = brandKey(product.brandName), !own.isSubset(of: labelWords),
              own.isDisjoint(with: words(product.genericName)) else { return false }
        let referenceKey = reference.flatMap(brandKey)
        let others = (referenceKey.map { [$0] } ?? [])
            + siblings.filter { printsOwnBrand($0, on: labelWords) }.compactMap { brandKey($0.brandName) }
        return others.contains { !$0.isSubset(of: own) && $0.isSubset(of: labelWords) }
    }

    /// The labeler's other products of this drug that carry a brand of their
    /// own: Astagraf XL beside Prograf. A code misread by one digit lands on
    /// these first, because a labeler numbers its line in sequence.
    private static func brandedSiblings(of product: NDCProduct, directory: NDCDirectory) -> [NDCProduct] {
        directory.products(withLabeler: String(product.productKey.prefix(5)), genericName: product.genericName)
            .filter { $0.productKey != product.productKey && isDistinctiveBrand($0) }
    }

    /// Whether the label prints the product's brand, and the brand is more
    /// than the drug's name. Some listings carry the generic and its strength
    /// as their brand, "Aspirin 81 mg" or "Guaifenesin 600 mg", and a label
    /// that names the drug has not named such a product.
    private static func printsOwnBrand(_ product: NDCProduct, on labelWords: Set<String>) -> Bool {
        guard let key = brandKey(product.brandName), key.isSubset(of: labelWords) else { return false }
        return isDistinctiveBrand(product)
    }

    private static func isDistinctiveBrand(_ product: NDCProduct) -> Bool {
        guard let key = brandKey(product.brandName) else { return false }
        let generic = Set(words(product.genericName))
        return key.contains { word in
            !generic.contains(word) && !interchangeableSalts.contains(word) && !strippableQualifiers.contains(word)
                && !strengthWords.contains(word) && word.first?.isNumber == false && ReleaseForm.named(by: word) == nil
        }
    }

    private static let strengthWords: Set<String> = ["mg", "mcg", "g", "ml", "iu", "unit", "units", "hr", "hour"]

    /// The brand the curated table gives this product's drug, whatever brand
    /// the listing carries: Prograf for every tacrolimus.
    private static func referenceBrand(of product: NDCProduct) -> String? {
        MedicationBrandIndex.brandName(forGeneric: product.genericName)
            ?? MedicationBrandIndex.brandName(forGeneric: displayName(for: product))
    }

    /// The stricter bar for a code that was not the recognizer's first guess:
    /// the label names this product, and no other product of its labeler.
    ///
    /// A guess one digit off is most often a neighbouring code of the same
    /// labeler, which numbers its line in sequence: the same drug at another
    /// strength, or at the same strength in another release. Prograf and
    /// Astagraf XL, immediate- and extended-release tacrolimus, sit one digit
    /// apart at every strength, so a label reading "tacrolimus 1 mg capsule"
    /// names both and must choose neither. So the label's confirmed name and
    /// printed strength must be the product's, a form, brand or release it
    /// prints must be the product's, nothing on it may contradict the product,
    /// and none of the labeler's other products may fit it as well. A label
    /// that prints "Prograf" sets Astagraf XL apart; one that prints "XL" sets
    /// Prograf apart; one that prints a brand the product does not carry
    /// refuses the guess.
    static func labelNamesExactly(
        _ match: Match,
        draft: MedicationDraft,
        labelText: String,
        directory: NDCDirectory = .shared
    ) -> Bool {
        let product = match.product
        guard draft.nameProvenance == .vocabulary || draft.nameProvenance == .strengthAnchored,
              !draft.name.isEmpty,
              StrengthComparison.compare(label: draft.strength, product: product.strength) == .equivalent,
              verdict(for: match, against: draft, labelText: labelText, directory: directory) == .accepted else {
            return false
        }
        let siblings = directory.products(withLabeler: String(product.productKey.prefix(5)))
            .filter { $0.productKey != product.productKey && namesAgree(labelText: draft.name + " " + draft.brandName, product: $0) }
        let labelWords = Set(words(labelText))
        let knownBrands = [product.brandName, MedicationBrandIndex.brandName(forGeneric: product.genericName) ?? ""]
            + siblings.map(\.brandName)
        let printedBrands = Set(knownBrands.compactMap(brandKey).filter { $0.isSubset(of: labelWords) })

        func labelFits(_ candidate: NDCProduct) -> Bool {
            guard namesAgree(labelText: draft.name + " " + draft.brandName, product: candidate),
                  StrengthComparison.compare(label: draft.strength, product: candidate.strength) != .different else {
                return false
            }
            if let printedForm = explicitForm(in: labelText), printedForm != candidate.form { return false }
            let release = releaseEvidence(
                in: labelText, labelWords: labelWords, for: candidate, reference: referenceBrand(of: candidate),
                siblings: brandedSiblings(of: candidate, directory: directory), draft: draft
            )
            if releaseContradicts(release, product: candidate) {
                return false
            }
            // The brand's name printed without the rest of it names another
            // release of the brand: "WELLBUTRIN XL" is not Wellbutrin SR.
            if let brand = brandKey(candidate.brandName), !brand.isSubset(of: labelWords),
               brand.contains(where: { $0.count >= 4 && labelWords.contains($0) }) {
                return false
            }
            if !printedBrands.isEmpty {
                guard let brand = brandKey(candidate.brandName), printedBrands.contains(brand) else { return false }
            }
            return true
        }
        return labelFits(product) && !siblings.contains(where: labelFits)
    }

    /// The words that pick a brand out on a label, release letters included:
    /// "Wellbutrin SR" and "Wellbutrin XL" are different medicines, so a label
    /// printing "WELLBUTRIN" alone prints neither. Nil when a listing carries
    /// no brand, or none worth matching.
    private static func brandKey(_ brand: String) -> Set<String>? {
        let key = Set(words(brand).filter { $0.count >= 2 && !uninformativeTokens.contains($0) })
        return key.isEmpty ? nil : key
    }

    /// Fills the identity fields from the directory when the label agrees. When it
    /// does not, the draft is returned as the parser left it, printed code and all.
    /// An accepted code also carries the RxNorm concept the bundled table gives
    /// it, which is how the medication is later recognised in Apple Health.
    static func applying(
        _ match: Match,
        to draft: MedicationDraft,
        labelText: String,
        directory: NDCDirectory = .shared,
        rxNormTable: RxNormTable = .shared
    ) -> MedicationDraft {
        guard verdict(for: match, against: draft, labelText: labelText, directory: directory) == .accepted else { return draft }
        let product = match.product
        var result = draft
        (result.name, result.brandName) = identity(of: product, labelBrand: draft.brandName)
        result.strength = displayStrength(for: product, labelStrength: draft.strength)
        result.form = product.form
        result.nameProvenance = .ndc
        result.productIdentifier = match.recordedCode
        result.productIdentifierType = "NDC"
        result.rxNormCode = rxNormTable.product(for: match.code)?.rxcui ?? ""
        return result
    }

    /// The name and brand a directory product fills in. A generic listing
    /// borrows the table's reference brand, and failing that keeps the brand
    /// the label gave, but never one of another release: generic
    /// extended-release tacrolimus is not Prograf. When the reference brand is
    /// withheld for that reason, the name keeps the release instead,
    /// "Tacrolimus ER", because nothing else on the medication would say it
    /// and the immediate-release product has the same name.
    static func identity(of product: NDCProduct, labelBrand: String = "") -> (name: String, brand: String) {
        let name = displayName(for: product)
        guard product.brandName.isEmpty else { return (name, product.brandName) }
        guard let release = product.comparableRelease, release.isModified else {
            return (name, MedicationBrandIndex.brandName(forGeneric: name) ?? labelBrand)
        }
        if let reference = MedicationBrandIndex.brandName(forGeneric: name, release: release) {
            return (name, reference)
        }
        let labelRelease = MedicationBrandIndex.release(ofName: "", brand: labelBrand)
        let brand = labelRelease == nil || labelRelease == release ? labelBrand : ""
        let withheld = MedicationBrandIndex.brandName(forGeneric: name) != nil && ReleaseForm.named(in: brand) == nil
        return (withheld ? ReleaseForm.name(name, keeping: release.abbreviation) : name, brand)
    }

    // MARK: - Names

    /// The vocabulary's spelling when it has one, so a medication reads the same
    /// whichever path identified it: the bare ingredient ahead of a salt form, as
    /// the label parser already prefers, then the listing's own name.
    static func displayName(for product: NDCProduct) -> String {
        let generic = product.genericName
        if let stripped = saltStripped(generic), let match = MedicationVocabulary.exactMatch(for: stripped) {
            return capitalizedName(match)
        }
        if let match = MedicationVocabulary.exactMatch(for: generic)
            ?? MedicationVocabulary.exactMatch(for: generic.replacingOccurrences(of: " and ", with: " / ")) {
            return capitalizedName(match)
        }
        // A combination listed under every salt of every ingredient reads as the
        // vocabulary's shortest name for that same set of ingredients.
        if let combination = MedicationVocabulary.shortestName(forCombination: generic) {
            return capitalizedName(combination)
        }
        if let pair = MedicationBrandIndex.resolve(product.brandName) ?? MedicationBrandIndex.resolve(generic) {
            return MedicationBrandIndex.displayName(forGeneric: pair.generic)
        }
        return capitalizedName(generic)
    }

    /// Salt forms that name the same medicine, mirroring the vocabulary's own list.
    private static let interchangeableSalts: Set<String> = [
        "hcl", "hydrochloride", "hbr", "hydrobromide", "sulfate", "sulphate",
        "mesylate", "besylate", "maleate", "citrate", "phosphate", "acetate", "fumarate"
    ]

    /// Cations and hydration states that a listing appends after the salt:
    /// "prednisolone sodium phosphate", "amlodipine besylate monohydrate".
    private static let strippableQualifiers: Set<String> = [
        "sodium", "potassium", "calcium", "magnesium", "monohydrate", "dihydrate",
        "trihydrate", "hemihydrate", "hydrate", "anhydrous"
    ]

    /// The base ingredient, when the listing's name is that ingredient plus salt
    /// wording. Whether the shorter name is real is settled by the caller against
    /// the vocabulary; this only proposes it.
    private static func saltStripped(_ name: String) -> String? {
        var tokens = words(name)
        var stripped = false
        while tokens.count > 1, let last = tokens.last,
              interchangeableSalts.contains(last) || strippableQualifiers.contains(last) {
            tokens.removeLast()
            stripped = true
        }
        return stripped ? tokens.joined(separator: " ") : nil
    }

    private static func capitalizedName(_ value: String) -> String {
        guard let first = value.first else { return value }
        return first.uppercased() + value.dropFirst()
    }

    /// Salts that make different products. Metoprolol succinate is not metoprolol
    /// tartrate, and a label naming one must not be identified as the other.
    private static let distinguishingSalts: Set<String> = ["succinate", "tartrate"]

    /// Tokens too common to tell one drug from another.
    private static let uninformativeTokens: Set<String> = [
        "acid", "oral", "extended", "delayed", "release", "tablets", "tablet", "capsules", "capsule",
        "sodium", "potassium", "calcium", "magnesium", "chloride", "monohydrate", "dihydrate",
        "anhydrous", "with", "and", "for", "human", "vitamin", "pharmacy", "health", "pain",
        "relief", "sleep", "night", "cold", "extra", "strength", "maximum", "childrens", "adult"
    ]

    /// Whether the label text is about this product: a substantial word of the
    /// label is, or begins, a word of the product's name, with no salt or vitamin
    /// number saying otherwise.
    static func namesAgree(labelText: String, product: NDCProduct) -> Bool {
        let productWords = Set(words(product.genericName) + words(product.brandName))
        let productTokens = productWords.filter { !$0.isEmpty && !uninformativeTokens.contains($0) && !interchangeableSalts.contains($0) }
        guard !productTokens.isEmpty else { return false }

        let labelWords = Set(words(labelText))
        let overlaps = labelWords.contains { word in
            productTokens.contains { token in
                if word == token { return word.count >= 4 }
                guard word.count >= 6, token.count >= 6 else { return false }
                return token.hasPrefix(word) || word.hasPrefix(token)
            }
        }
        guard overlaps else { return false }

        let labelSalts = labelWords.intersection(distinguishingSalts)
        let productSalts = productWords.intersection(distinguishingSalts)
        if !labelSalts.isEmpty, !productSalts.isEmpty, labelSalts.isDisjoint(with: productSalts) { return false }

        // Vitamin B12 and B6 differ only in their digits.
        let labelNumbered = labelWords.filter(isLetterDigitToken)
        let productNumbered = productWords.filter(isLetterDigitToken)
        if !labelNumbered.isEmpty, !productNumbered.isEmpty, labelNumbered.isDisjoint(with: productNumbered) { return false }
        return true
    }

    /// "b12", "d3", "k2": a letter-led token that carries a digit. A strength such
    /// as "50mg" leads with its digit and is not a name.
    private static func isLetterDigitToken(_ token: String) -> Bool {
        guard let first = token.first, first.isLetter else { return false }
        return token.contains(where: \.isNumber)
    }

    private static func words(_ value: String) -> [String] {
        value.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    // MARK: - Forms

    /// The form the label states in so many words, or nil when it names none or
    /// several. Only the forms that are printed unambiguously are compared.
    static func explicitForm(in labelText: String) -> MedicationForm? {
        let tokens = Set(words(labelText))
        var found: Set<MedicationForm> = []
        let markers: [(MedicationForm, Set<String>)] = [
            (.capsule, ["capsule", "capsules", "cap", "caps"]),
            (.tablet, ["tablet", "tablets", "tab", "tabs"]),
            (.patch, ["patch", "patches", "transdermal"]),
            (.injection, ["injection", "inject", "injectable", "syringe", "syringes"]),
            (.inhaler, ["inhaler", "inhalation", "puff", "puffs"])
        ]
        for (form, formTokens) in markers where !tokens.isDisjoint(with: formTokens) {
            found.insert(form)
        }
        return found.count == 1 ? found.first : nil
    }

    private static func comparableForm(_ form: MedicationForm) -> MedicationForm? {
        switch form {
        case .tablet, .capsule, .patch, .injection, .inhaler: form
        default: nil
        }
    }

    // MARK: - Strengths

    /// What the printed label says when it says the same thing, so the review
    /// screen shows the number on the bottle; otherwise the directory's.
    static func displayStrength(for product: NDCProduct, labelStrength: String) -> String {
        if StrengthComparison.compare(label: labelStrength, product: product.strength) == .equivalent, !labelStrength.isEmpty {
            return labelStrength
        }
        // The build tool already writes strengths the way a label prints them.
        return product.strength.isEmpty ? labelStrength : product.strength
    }
}

/// Whether two strengths name the same amount.
///
/// Labels and the directory write one fact several ways: `800-160 mg` against
/// `800 mg/160 mg`, `100 units/mL` against `100 IU/mL`, and a mixed-salt stimulant
/// printed as its 20 mg total against four 5 mg components. Only a product with
/// one or two components can contradict a label; a multi-ingredient listing
/// against a label's partial reading proves nothing either way.
enum StrengthComparison {
    enum Outcome: Hashable {
        case equivalent
        case different
        case incomparable
    }

    struct Component: Hashable {
        let value: Double
        let unit: String
    }

    struct Parsed: Hashable {
        let components: [Component]
        let denominator: Component?
    }

    static func compare(label: String, product: String) -> Outcome {
        guard let labelParsed = parse(label), let productParsed = parse(product) else { return .incomparable }
        if areEquivalent(labelParsed, productParsed) { return .equivalent }
        return productParsed.components.count <= 2 ? .different : .incomparable
    }

    static func areEquivalent(_ label: Parsed, _ product: Parsed) -> Bool {
        if let labelDenominator = label.denominator, let productDenominator = product.denominator,
           labelDenominator != productDenominator {
            return false
        }
        if multiset(label.components) == multiset(product.components) { return true }

        // A single printed total against several components of one unit.
        let units = Set(product.components.map(\.unit))
        if product.components.count >= 2, units.count == 1, label.components.count == 1,
           let labelComponent = label.components.first, labelComponent.unit == units.first {
            let total = product.components.map(\.value).reduce(0, +)
            return abs(total - labelComponent.value) < 0.0005
        }
        return false
    }

    private static let pairPattern = /(\/?)\s*(\d+(?:\.\d+)?)?\s*([A-Za-z%µ]+)?/

    static func parse(_ text: String) -> Parsed? {
        // "1,000 IU" is one thousand, not one and then nothing.
        let text = text.replacing(/(\d),(\d{3})/) { "\($0.1)\($0.2)" }
        var pending: [(value: Double?, unit: String?, afterSlash: Bool)] = []
        for match in text.matches(of: pairPattern) {
            let value = match.2.flatMap { Double($0) }
            let unit = match.3.flatMap { canonicalUnit(String($0)) }
            guard value != nil || unit != nil else { continue }
            pending.append((value, unit, !match.1.isEmpty))
        }
        guard !pending.isEmpty else { return nil }

        // A number written before its unit ("800-160 mg") takes the unit that follows.
        var components: [Component] = []
        var denominator: Component?
        var unitlessValues: [Double] = []
        for entry in pending {
            if entry.afterSlash, let unit = entry.unit, !componentUnits.contains(unit), unitlessValues.isEmpty {
                denominator = Component(value: entry.value ?? 1, unit: unit)
                continue
            }
            guard let unit = entry.unit else {
                if let value = entry.value { unitlessValues.append(value) }
                continue
            }
            for value in unitlessValues { components.append(Component(value: value, unit: unit)) }
            unitlessValues.removeAll()
            if let value = entry.value { components.append(Component(value: value, unit: unit)) }
        }
        guard !components.isEmpty, unitlessValues.isEmpty else { return nil }
        return Parsed(components: components, denominator: denominator)
    }

    private static let componentUnits: Set<String> = ["mg", "mcg", "g", "iu", "%", "meq", "mmol"]

    private static func canonicalUnit(_ raw: String) -> String? {
        switch raw.lowercased() {
        case "mg": "mg"
        case "mcg", "ug", "µg": "mcg"
        case "g", "gm": "g"
        case "iu", "unit", "units", "u": "iu"
        case "ml": "ml"
        case "l": "l"
        case "%": "%"
        case "meq": "meq"
        case "mmol": "mmol"
        default: nil
        }
    }

    private static func multiset(_ components: [Component]) -> [String: Int] {
        components.reduce(into: [:]) { counts, component in
            counts["\(component.value)|\(component.unit)", default: 0] += 1
        }
    }
}
