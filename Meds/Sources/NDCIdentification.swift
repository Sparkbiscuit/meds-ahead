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
    }

    enum Verdict: Hashable, Sendable {
        case accepted
        /// The code resolved, but nothing else on the label backs it up. A barcode
        /// needs no backing; printed digits do.
        case uncorroborated
        /// The label plainly names a different drug, strength or form than the
        /// directory does.
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
        var order: [String] = []
        for reading in readings(in: evidence) {
            let hits = reading.candidates.compactMap { code in
                directory.product(for: code).map { Match(code: code, product: $0, source: reading.source) }
            }
            guard Set(hits.map(\.product.productKey)).count == 1, let hit = hits.first else { continue }
            let key = hit.product.productKey
            if byProduct[key] == nil { order.append(key) }
            // A barcode reading of the same product outranks a printed one.
            if byProduct[key] == nil || (hit.source == .barcode && byProduct[key]?.source != .barcode) {
                byProduct[key] = hit
            }
        }
        let judged = order.compactMap { key in byProduct[key].map { ($0, verdict(for: $0, against: draft, labelText: labelText)) } }
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
        if !product.brandName.isEmpty { text += " (\(product.brandName))" }
        return text
    }

    static func verdict(for match: Match, against draft: MedicationDraft, labelText: String) -> Verdict {
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

        if match.source == .barcode { return .accepted }
        let corroborated = strengthVerdict == .equivalent || namesAgree(labelText: labelText, product: product)
        return corroborated ? .accepted : .uncorroborated
    }

    /// Fills the identity fields from the directory when the label agrees. When it
    /// does not, the draft is returned as the parser left it, printed code and all.
    /// An accepted code also carries the RxNorm concept the bundled table gives
    /// it, which is how the medication is later recognised in Apple Health.
    static func applying(
        _ match: Match,
        to draft: MedicationDraft,
        labelText: String,
        rxNormTable: RxNormTable = .shared
    ) -> MedicationDraft {
        guard verdict(for: match, against: draft, labelText: labelText) == .accepted else { return draft }
        let product = match.product
        var result = draft
        result.name = displayName(for: product)
        result.brandName = product.brandName.isEmpty
            ? (MedicationBrandIndex.brandName(forGeneric: result.name) ?? draft.brandName)
            : product.brandName
        result.strength = displayStrength(for: product, labelStrength: draft.strength)
        result.form = product.form
        result.nameProvenance = .ndc
        result.productIdentifier = match.code.hyphenated
        result.productIdentifierType = "NDC"
        result.rxNormCode = rxNormTable.product(for: match.code)?.rxcui ?? ""
        return result
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
