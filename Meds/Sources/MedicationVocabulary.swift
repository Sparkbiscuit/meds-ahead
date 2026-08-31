import Foundation

enum MedicationVocabulary {
    private struct Match {
        let name: String
        let key: String
        let score: Int
    }

    private struct NameParts {
        let key: String
        let tokens: [String]
    }

    private struct Entry {
        let name: String
        let parts: NameParts
    }

    private static let entries: [Entry] = {
        guard let url = Bundle.main.url(forResource: "MedicationNames", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \Character.isNewline).map { line in
            let name = String(line)
            return Entry(name: name, parts: parts(name))
        }
    }()

    private static let entryKeys: Set<String> = Set(entries.map(\.parts.key))

    /// True when `source` reads as a piece of a longer medication name rather than
    /// a name in its own right.
    ///
    /// A curved bottle clips the ends off the product line, and what survives —
    /// "Rolol Succin" out of "Metoprolol succinate" — is name-shaped enough to pass
    /// every other check while naming no real drug. The strength-anchored path
    /// exists so a pharmacy's own wording ("Amphetamine salt combo") is not thrown
    /// away for missing from the vocabulary, and that wording is not a substring of
    /// anything; a clipped reading is. Anything that is contained in a real name,
    /// without being one, is the clipping and not the drug.
    static func isFragmentOfLongerName(_ source: String) -> Bool {
        isFragment(key(source)) || isFragment(coreKey(source))
    }

    /// The entry a noisy reading resolves to once the trailing release form and
    /// imprint code a pharmacy prints after the name are set aside, so
    /// "METOPROLOL SUCCINATE ER 50 MG TAB GG 263" is still metoprolol succinate.
    /// Exact equality only: this drops known noise, it does not guess.
    static func matchIgnoringTrailingNoise(for source: String) -> String? {
        let core = coreKey(source)
        guard core.count >= 5, !key(source).isEmpty, key(source) != core else { return nil }
        return entries.first { $0.parts.key == core }?.name
    }

    private static func isFragment(_ candidate: String) -> Bool {
        guard candidate.count >= 4, !entryKeys.contains(candidate) else { return false }
        return entries.contains { entry in
            entry.parts.key.count > candidate.count && entry.parts.key.contains(candidate)
        }
    }

    /// A release form or an imprint code trails the name on a dispensing label and
    /// belongs to the package, not the drug. Stripping it is deliberately eager:
    /// this feeds a check whose failure mode is a blank name, and a blank beats a
    /// clipped one.
    private static let trailingNoiseTokens: Set<String> = [
        "er", "xl", "xr", "sr", "cr", "dr", "odt", "la", "ec", "tab", "cap"
    ]

    private static func coreKey(_ value: String) -> String {
        var tokens = value
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        while tokens.count > 1, let last = tokens.last {
            let isNoise = trailingNoiseTokens.contains(last)
                || last.allSatisfy(\.isNumber)
                || last.count <= 2
                || (last.count <= 3 && last.contains(where: \.isNumber))
            guard isNoise else { break }
            tokens.removeLast()
        }
        return tokens.joined().filter { $0.isLetter || $0.isNumber }
    }

    /// Salt forms that name the same medicine the bare ingredient does. Deliberately
    /// excludes `succinate` and `tartrate`: metoprolol succinate and metoprolol
    /// tartrate are different products with different brands, and collapsing them
    /// would be the same class of error this gate exists to prevent.
    private static let interchangeableSaltTokens: Set<String> = [
        "hcl", "hydrochloride", "hbr", "hydrobromide", "sulfate", "sulphate",
        "mesylate", "besylate", "maleate", "citrate", "phosphate", "acetate", "fumarate"
    ]

    /// A reading that *is* a medication name, rather than one that resembles a
    /// medication name. Exact on the key, or exact once a salt that names the same
    /// medicine is set aside, so a label printing "SERTRALINE HCL" — which matched
    /// nothing at all before, and so left the field open to whatever junk elsewhere
    /// on the label happened to resemble a drug — resolves to sertraline.
    static func exactMatch(for source: String) -> String? {
        let sourceKey = key(source)
        guard sourceKey.count >= 5 else { return nil }
        if let hit = entries.first(where: { $0.parts.key == sourceKey }) { return hit.name }

        var tokens = parts(source).tokens
        var stripped = false
        while tokens.count > 1, let last = tokens.last, interchangeableSaltTokens.contains(last) {
            tokens.removeLast()
            stripped = true
        }
        guard stripped else { return nil }
        let strippedKey = tokens.joined()
        guard strippedKey.count >= 5 else { return nil }
        return entries.first(where: { $0.parts.key == strippedKey })?.name
    }

    static func uniqueMatch(for source: String) -> String? {
        uniqueMatch(source: parts(source), among: entries)
    }

    static func uniqueMatch(for source: String, among names: [String]) -> String? {
        uniqueMatch(
            source: parts(source),
            among: names.map { Entry(name: $0, parts: parts($0)) }
        )
    }

    private static func uniqueMatch(source sourceParts: NameParts, among entries: [Entry]) -> String? {
        guard sourceParts.key.count >= 5 else { return nil }

        var bestByKey: [String: Match] = [:]
        for entry in entries {
            let name = entry.name
            let nameParts = entry.parts
            guard nameParts.key.count >= 5,
                  let score = matchScore(source: sourceParts, name: nameParts) else { continue }
            let match = Match(name: name, key: nameParts.key, score: score)
            if let existing = bestByKey[nameParts.key] {
                if name.count < existing.name.count { bestByKey[nameParts.key] = match }
            } else {
                bestByKey[nameParts.key] = match
            }
        }

        guard let bestScore = bestByKey.values.map(\.score).min() else { return nil }
        let best = bestByKey.values.filter { $0.score == bestScore }
        guard best.count == 1 else { return nil }
        return best[0].name
    }

    private static func matchScore(source: NameParts, name: NameParts) -> Int? {
        let sourceKey = source.key
        let nameKey = name.key
        if sourceKey == nameKey { return 0 }

        let missing = nameKey.count - sourceKey.count
        let coverage = Double(sourceKey.count) / Double(nameKey.count)
        // A reading clipped at the end keeps the beginning, which is what tells two
        // drugs apart, so completing it is comparatively safe. A reading clipped at
        // the *start* asks us to invent the distinguishing part: "edronate" was
        // being completed to risedronate, and that is how a sertraline bottle came
        // back as a bisphosphonate. Completing backwards has to be near-certain.
        if missing > 0, nameKey.hasPrefix(sourceKey), missing <= 5, coverage >= 0.66 {
            return 10 + missing
        }
        if missing > 0, nameKey.hasSuffix(sourceKey), missing <= 3, coverage >= 0.80 {
            return 10 + missing
        }

        if let compoundScore = compoundEdgeScore(source: source.tokens, name: name.tokens) {
            return compoundScore
        }

        let lengthDifference = abs(nameKey.count - sourceKey.count)
        let allowedDistance = sourceKey.count >= 12 ? 2 : 1
        guard lengthDifference <= allowedDistance else { return nil }
        let distance = editDistance(sourceKey, nameKey)
        return distance <= allowedDistance ? 100 + distance : nil
    }

    /// Curved prescription bottles commonly reveal one complete ingredient and
    /// only the leading portion of the next. Complete that edge only when the
    /// token structure is preserved and the result is unique in the vocabulary.
    /// A one-character OCR error is permitted inside the visible partial token.
    private static func compoundEdgeScore(source: [String], name: [String]) -> Int? {
        guard source.count >= 2, source.count == name.count else { return nil }

        var exactTokenCount = 0
        var incompleteTokenCount = 0
        var missingCharacterCount = 0
        for (sourceToken, nameToken) in zip(source, name) {
            if sourceToken == nameToken {
                exactTokenCount += 1
                continue
            }

            guard sourceToken.count >= 6, sourceToken.count < nameToken.count else { return nil }
            let visiblePrefix = String(nameToken.prefix(sourceToken.count))
            guard editDistance(sourceToken, visiblePrefix) <= 1 else { return nil }
            incompleteTokenCount += 1
            missingCharacterCount += nameToken.count - sourceToken.count
        }

        guard exactTokenCount >= 1, incompleteTokenCount == 1 else { return nil }
        return 30 + missingCharacterCount
    }

    /// Digits are part of a name, not decoration. Dropping them collapsed
    /// "vitamin b12" and "vitamin b6" onto one key, and a B12 bottle resolved as B6.
    private static func key(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func parts(_ value: String) -> NameParts {
        let tokens = value
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        return NameParts(key: tokens.joined(), tokens: tokens)
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous[right.count]
    }
}
