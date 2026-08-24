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
        if missing > 0,
           missing <= 5,
           coverage >= 0.66,
           nameKey.hasPrefix(sourceKey) || nameKey.hasSuffix(sourceKey) {
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

    private static func key(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }

    private static func parts(_ value: String) -> NameParts {
        let tokens = value
            .lowercased()
            .split(whereSeparator: { !$0.isLetter })
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
