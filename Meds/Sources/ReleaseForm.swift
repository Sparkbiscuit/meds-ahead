import Foundation

/// How a product lets its drug go: at once, spread over the day, or held back
/// past the stomach.
///
/// Two products of one drug at one strength in one form can be different
/// medicines. Prograf and Astagraf XL are both tacrolimus 1 mg capsules, the
/// first taken twice a day and the second once, and nothing else in the FDA
/// directory or on a pharmacy label tells them apart. So release is part of a
/// product's identity wherever a code is checked against a label, a brand is
/// found for a name, or one medication is matched to another.
enum ReleaseForm: String, Hashable, Sendable {
    case immediate
    case extended
    case delayed

    /// The bundled directory's sixth column, as `Tools/build_ndc_directory.py`
    /// writes it: "er", "dr", or empty for a listing that claims neither.
    init?(directoryValue: String) {
        switch directoryValue {
        case "": self = .immediate
        case "er": self = .extended
        case "dr": self = .delayed
        default: return nil
        }
    }

    var isModified: Bool { self != .immediate }

    /// The letters a pharmacy prints for the release, which a name keeps when
    /// no brand beside it says it: "Tacrolimus ER".
    var abbreviation: String {
        switch self {
        case .immediate: "IR"
        case .extended: "ER"
        case .delayed: "DR"
        }
    }

    /// The name with the release letters after it, unless it already carries
    /// a release of its own.
    static func name(_ name: String, keeping letters: String) -> String {
        guard !name.isEmpty, !letters.isEmpty, named(in: name) == nil else { return name }
        return "\(name) \(letters)"
    }

    /// The release a single lowercased word names: the letters a pharmacy and
    /// a brand print after the name ("XL", "CD", "EC"), or nil.
    static func named(by word: String) -> ReleaseForm? {
        if extendedWords.contains(word) { return .extended }
        if delayedWords.contains(word) { return .delayed }
        if immediateWords.contains(word) { return .immediate }
        return nil
    }

    private static let extendedWords: Set<String> = ["er", "xl", "xr", "sr", "cr", "la", "cd", "xt", "extended"]
    private static let delayedWords: Set<String> = ["dr", "ec", "delayed"]
    private static let immediateWords: Set<String> = ["ir", "immediate"]

    /// The release a medication's name carries, "Toprol XL" or "Tacrolimus ER",
    /// or nil when it names none, or more than one. A name's first word never
    /// counts: a release is written after the drug, and "Dr. Sheffield" and
    /// "La Roche-Posay" lead with the same letters.
    static func named(in name: String) -> ReleaseForm? {
        let found = Set(words(in: name).dropFirst().compactMap(named(by:)))
        return found.count == 1 ? found.first : nil
    }

    /// What a label says about release, read only from the lines that name the
    /// medication, which are the lines a pharmacy prints the release on. Read
    /// from the whole label, "DR. A. GREENE" is delayed release and a
    /// Louisiana address is long-acting.
    struct Evidence: Hashable, Sendable {
        /// Said in so many words: "ER", "XL", "extended-release", "EC", "IR".
        /// Enough to refuse a product of another release.
        var stated: Set<ReleaseForm> = []
        /// Only suggested: "24 HR" is on Nexium 24HR and Allegra 24 Hour, which
        /// are not extended-release, as well as on products that are. Enough to
        /// back a product up, never to refuse one.
        var suggested: Set<ReleaseForm> = []
        /// The letters the label prints for each release it states, "XL" or
        /// "CD", so a name that keeps its release reads as the bottle does.
        var letters: [ReleaseForm: String] = [:]

        /// The one modified release the label states, when it states exactly one.
        var modified: ReleaseForm? {
            let modified = stated.filter(\.isModified)
            return modified.count == 1 ? modified.first : nil
        }

        /// The letters for a release the label states.
        func printedLetters(for release: ReleaseForm) -> String {
            letters[release] ?? release.abbreviation
        }
    }

    /// The release evidence on the lines of `labelText` that carry one of
    /// `nameWords`. A phrase such as "Extended-Release Capsules" also counts
    /// on the line after, where a manufacturer's label sets it under the name,
    /// and so do extended-release letters that open the rest of the
    /// description there.
    static func evidence(in labelText: String, namedBy nameWords: Set<String>) -> Evidence {
        let nameWords = nameWords.filter { $0.count >= 4 }
        var evidence = Evidence()
        guard !nameWords.isEmpty else { return evidence }
        let lines = labelText.components(separatedBy: .newlines)
        var previousNamedTheDrug = false
        for line in lines {
            let lower = line.lowercased()
            let lineWords = words(in: lower)
            let namesTheDrug = !nameWords.isDisjoint(with: lineWords)
            if namesTheDrug || previousNamedTheDrug {
                evidence.stated.formUnion(phrases(in: lower))
            }
            if namesTheDrug {
                for (release, word) in abbreviations(in: lower) {
                    evidence.stated.insert(release)
                    if word.count <= 3, evidence.letters[release] == nil { evidence.letters[release] = word.uppercased() }
                }
                if lower.replacing(dosingInterval, with: " ").contains(hourDuration) {
                    evidence.suggested.insert(.extended)
                }
            } else if previousNamedTheDrug, continuesTheDescription(lineWords, lower) {
                for (release, word) in abbreviations(in: lower) where wrappedLetters.contains(word) {
                    evidence.stated.insert(release)
                    if evidence.letters[release] == nil { evidence.letters[release] = word.uppercased() }
                }
            }
            previousNamedTheDrug = namesTheDrug
        }
        evidence.suggested.formUnion(evidence.stated)
        return evidence
    }

    private static let extendedPhrase = /\b(?:extended|sustained|controlled)[\s-]*release/
    private static let delayedPhrase = /\b(?:delayed[\s-]*release|enteric[\s-]*coated)/
    private static let immediatePhrase = /\bimmediate[\s-]*release/
    /// "24 HR" or "24-Hour" as a product's name carries it. Twelve hours is
    /// left out: "every 12 hours" is how immediate-release tacrolimus is
    /// taken, and a label that says it must not vouch for the extended-release
    /// product.
    private static let hourDuration = /\b24[\s-]*(?:hr|hour)\b/
    /// "Every 24 hours", "q 12 hr", "in 24 hours": how often, not how the
    /// product releases.
    private static let dosingInterval = /\b(?:every|each|per|in|within|for|q)\s*\d+[\s-]*(?:hr|hrs|hour|hours|h)\b/
    /// A prescriber, "DR. A. GREENE" or "DR JONES", rather than delayed release.
    private static let prescriber = /\bdr\b\.?\s*(?:[a-z]\.\s*)*[a-z]{2,}/

    private static func phrases(in lower: String) -> Set<ReleaseForm> {
        var found: Set<ReleaseForm> = []
        if lower.contains(extendedPhrase) { found.insert(.extended) }
        if lower.contains(delayedPhrase) { found.insert(.delayed) }
        if lower.contains(immediatePhrase) { found.insert(.immediate) }
        return found
    }

    /// Each release word on the line, in order, with the word as printed.
    private static func abbreviations(in lower: String) -> [(ReleaseForm, String)] {
        let withoutPrescriber = lower.replacing(prescriber) { match in
            // "DR CAPSULE" and "DR TAB" are the release before the form, not a name.
            let rest = match.output.dropFirst(2).trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
            return formWords.contains(rest) ? String(match.output) : ""
        }
        return words(in: withoutPrescriber).compactMap { word in named(by: word).map { ($0, word) } }
    }

    /// The extended-release letters that still count on the line after the
    /// drug's, where a narrow label wraps "TACROLIMUS" / "XL 1 MG CAPSULE".
    /// DR, EC and LA stay on the drug's own line: they are also a prescriber,
    /// a manufacturer and a state, and those are what follow a drug's line.
    private static let wrappedLetters: Set<String> = ["er", "xl", "xr", "sr", "cr", "cd", "xt"]

    /// Whether a line reads as the rest of the drug's description: it names a
    /// form or a strength, or carries nothing but release letters.
    private static func continuesTheDescription(_ lineWords: [String], _ lower: String) -> Bool {
        guard !lineWords.isEmpty else { return false }
        return lineWords.allSatisfy(wrappedLetters.contains)
            || !formWords.isDisjoint(with: lineWords)
            || lower.contains(strength)
    }

    private static let strength = /\b\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml)\b/

    /// What follows "DR" when it is the release: the form it describes.
    private static let formWords: Set<String> = [
        "tab", "tabs", "tablet", "tablets", "cap", "caps", "capsule", "capsules", "sprinkle", "granules"
    ]

    private static func words(in text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
