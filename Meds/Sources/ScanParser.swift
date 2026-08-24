import Foundation

enum ScanEvidenceQuality {
    static let minimumTextConfidence = 0.45
    private static let contextualMinimumConfidence = 0.30

    static func isUsefulForAutofill(_ evidence: ScanEvidence) -> Bool {
        guard !evidence.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard evidence.kind == .text else { return true }
        guard normalized(evidence.value).count >= 3 else { return false }
        if evidence.confidence >= minimumTextConfidence { return true }
        return evidence.confidence >= contextualMinimumConfidence && containsMedicationFieldMarker(evidence.value)
    }

    static func deduplicationKey(for evidence: ScanEvidence) -> String {
        "\(evidence.kind.rawValue):\(normalized(evidence.value))"
    }

    static func mergingBest(
        existing: [ScanEvidence],
        additions: [ScanEvidence]
    ) -> [ScanEvidence] {
        var result = existing.filter(isUsefulForAutofill)
        for item in additions where isUsefulForAutofill(item) {
            let key = deduplicationKey(for: item)
            if let index = result.firstIndex(where: { deduplicationKey(for: $0) == key }) {
                if item.confidence > result[index].confidence { result[index] = item }
            } else {
                result.append(item)
            }
        }
        return result
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters)
    }

    private static func containsMedicationFieldMarker(_ value: String) -> Bool {
        let lower = value.lowercased()
        let markers = [
            " mg", "mg ", " mcg", "mcg ", " ml", "ml ", "tablet", "capsule",
            "take ", "use ", "daily", "refill", "quantity", "qty", "contents", "lot", "exp"
        ]
        return markers.contains(where: lower.contains)
    }
}

enum ScanParser {
    private static let strengthPattern = /(?i)\b\d+(?:\.\d+)?\s?(?:mcg|mg|g|mL|%)(?:\s*\/\s*\d+(?:\.\d+)?\s?(?:mcg|mg|g|mL))?\b/
    private static let quantityPattern = /(?i)\b(?:qty|quantity|contents?)\s*[:#]?\s*(\d+(?:\.\d+)?)\b/
    private static let refillPattern = /(?i)\b(\d+)\s+refills?\s+(?:left|remaining)\b/
    private static let labeledRefillPattern = /(?i)\b(?:refills?|rfls?)\s*(?:left|remaining)?\s*[:#]?\s*(\d+)\b/
    private static let simpleRefillPattern = /(?i)\b(\d+)\s+refills?\b/
    private static let noRefillsPattern = /(?i)\bno\s+refills?\s+(?:left|remaining)\b/
    private static let lotPattern = /(?i)\blot\s*[:#]?\s*([A-Z0-9-]+)\b/
    private static let expirationPattern = /(?i)\b(?:exp|expires?|expiration)\s*[:.]?\s*(\d{1,2})[\/-](\d{2,4})\b/
    private static let ndcPattern = /(?i)\bNDC\s*[:#]?\s*(\d{4,5}-\d{3,4}-\d{1,2}|\d{10,11})\b/

    private struct TextLine {
        let value: String
        let confidence: Double
        let order: Int
    }

    static func parse(_ evidence: [ScanEvidence], now: Date = .now) -> MedicationDraft {
        let trustedEvidence = evidence.filter(ScanEvidenceQuality.isUsefulForAutofill)
        let lines = makeTextLines(from: trustedEvidence)
        let combined = lines.map(\.value).joined(separator: "\n")

        var draft = MedicationDraft()
        draft.source = .scanned
        draft.evidence = evidence
        draft.overallConfidence = trustedEvidence.isEmpty ? 0 : trustedEvidence.map(\.confidence).reduce(0, +) / Double(trustedEvidence.count)
        draft.strength = firstMatch(in: combined, pattern: strengthPattern) ?? ""
        draft.name = medicationName(from: lines, strength: draft.strength)
        draft.form = inferForm(from: combined)
        draft.currentSupply = capturedQuantity(in: combined)
        draft.refillsRemaining = capturedRefills(in: combined)
        draft.lotNumber = capture(in: combined, pattern: lotPattern, group: 1) ?? ""
        draft.expirationDate = capturedExpiration(in: combined, now: now)
        draft.directions = capturedDirections(from: lines)

        if let barcode = preferredBarcode(in: trustedEvidence) {
            draft.productIdentifier = barcode.value
            draft.productIdentifierType = barcode.symbology ?? "Barcode"
        } else if let ndc = capture(in: combined, pattern: ndcPattern, group: 1) {
            draft.productIdentifier = ndc
            draft.productIdentifierType = "NDC"
        }
        return draft
    }

    private static func makeTextLines(from evidence: [ScanEvidence]) -> [TextLine] {
        var seen: Set<String> = []
        var result: [TextLine] = []
        for item in evidence where item.kind == .text {
            for rawLine in item.value.components(separatedBy: .newlines) {
                let value = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = value.lowercased().split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
                guard !value.isEmpty, seen.insert(key).inserted else { continue }
                result.append(TextLine(value: value, confidence: item.confidence, order: result.count))
            }
        }
        return result
    }

    private static func medicationName(from lines: [TextLine], strength: String) -> String {
        let stopWords = [
            "tablet", "capsule", "quantity", "contents", "refill", "take", "use", "apply",
            "inhale", "instill", "inject", "times a day",
            "dietary supplement", "drug-free", "gluten free", "lactose free", "rx#", "rx #",
            "prescriber", "patient", "pharmacy", "discard", "use by", "ndc", "phone", "address",
            "date filled", "lot", "exp", "doctor", "provider", "www.", ".com", "fax"
        ]

        if !strength.isEmpty,
           let strengthLineIndex = lines.firstIndex(where: { $0.value.localizedCaseInsensitiveContains(strength) }) {
            let line = lines[strengthLineIndex].value
            let cleaned = cleanedNameLine(line, removing: strength)
            if isPlausibleName(cleaned, stopWords: stopWords) { return titleCasedDrugName(cleaned) }

            for distance in 1...2 {
                for nearbyIndex in [strengthLineIndex - distance, strengthLineIndex + distance]
                    where lines.indices.contains(nearbyIndex) {
                    let nearby = lines[nearbyIndex]
                    if nearby.confidence >= ScanEvidenceQuality.minimumTextConfidence,
                       !isMetadataValue(at: nearbyIndex, in: lines),
                       isPlausibleName(nearby.value, stopWords: stopWords) {
                        return titleCasedDrugName(nearby.value)
                    }
                }
            }
        }

        let candidates: [TextLine] = lines.enumerated().compactMap { index, line -> TextLine? in
            guard line.confidence >= 0.60,
                  !isMetadataValue(at: index, in: lines),
                  isPlausibleName(line.value, stopWords: stopWords) else { return nil }
            return line
        }
        let best = candidates.max { nameScore($0) < nameScore($1) }
        return best.map { titleCasedDrugName($0.value) } ?? ""
    }

    private static func cleanedNameLine(_ value: String, removing strength: String) -> String {
        var cleaned = value
            .replacingOccurrences(of: strength, with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "Each capsule contains", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "Each tablet contains", with: "", options: [.caseInsensitive])
        let dosageWords = [
            "tablets", "tablet", "capsules", "capsule", "oral solution", "solution",
            "injection", "patches", "patch", "drops", "cream", "ointment"
        ]
        for word in dosageWords {
            cleaned = cleaned.replacingOccurrences(of: word, with: "", options: [.caseInsensitive])
        }
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " :-,."))
    }

    private static func isMetadataValue(at index: Int, in lines: [TextLine]) -> Bool {
        let markers = ["patient", "patient name", "prescriber", "prescriber name", "doctor", "provider"]
        guard index > lines.startIndex else { return false }
        let preceding = lines[index - 1].value
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " :#"))
        return markers.contains(preceding)
    }

    private static func nameScore(_ line: TextLine) -> Double {
        let words = line.value.split(whereSeparator: \Character.isWhitespace)
        let hasDigit = line.value.rangeOfCharacter(from: .decimalDigits) != nil
        var score = line.confidence * 100
        if (1...4).contains(words.count) { score += 12 }
        if !hasDigit { score += 8 }
        score -= Double(line.order) * 0.05
        return score
    }

    private static func isPlausibleName(_ value: String, stopWords: [String]) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3,
              trimmed.count <= 64,
              trimmed.rangeOfCharacter(from: .letters) != nil,
              !trimmed.contains("http") else { return false }
        let lower = trimmed.lowercased()
        return !stopWords.contains(where: lower.contains)
    }

    private static func titleCasedDrugName(_ value: String) -> String {
        if value == value.uppercased() { return value.capitalized }
        return value
    }

    private static func inferForm(from value: String) -> MedicationForm {
        let lower = value.lowercased()
        if lower.contains("capsule") { return .capsule }
        if lower.contains("tablet") { return .tablet }
        if lower.contains("patch") { return .patch }
        if lower.contains("inhaler") || lower.contains("puff") { return .inhaler }
        if lower.contains("injection") || lower.contains("syringe") { return .injection }
        if lower.contains("drop") { return .drops }
        if lower.contains("cream") || lower.contains("ointment") || lower.contains("topical") { return .topical }
        if lower.contains("solution") || lower.contains("liquid") || lower.contains("syrup") { return .liquid }
        return .tablet
    }

    private static func capturedQuantity(in value: String) -> Double? {
        guard let raw = capture(in: value, pattern: quantityPattern, group: 1) else { return nil }
        return Double(raw)
    }

    private static func capturedRefills(in value: String) -> Int? {
        if value.firstMatch(of: noRefillsPattern) != nil { return 0 }
        for pattern in [refillPattern, labeledRefillPattern, simpleRefillPattern] {
            if let raw = capture(in: value, pattern: pattern, group: 1) {
                return Int(raw)
            }
        }
        return nil
    }

    private static func capturedExpiration(in value: String, now: Date) -> Date? {
        guard let match = value.firstMatch(of: expirationPattern),
              let month = Int(match.1),
              var year = Int(match.2),
              (1...12).contains(month) else { return nil }
        if year < 100 { year += 2000 }
        var components = DateComponents()
        components.year = year
        components.month = month + 1
        components.day = 0
        return Calendar(identifier: .gregorian).date(from: components)
    }

    private static func capturedDirections(from lines: [TextLine]) -> String {
        lines.compactMap { line -> (line: TextLine, score: Double)? in
            let lower = line.value
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let excludedFragments = [
                "daily value", "% daily", "use by", "do not use", "discard after",
                "for external use only", "expiration", "expires", "lot number"
            ]
            guard !excludedFragments.contains(where: lower.contains) else { return nil }

            let directionVerbs = ["take ", "use ", "apply ", "inhale ", "instill ", "inject ", "place "]
            let startsWithDirection = directionVerbs.contains(where: lower.hasPrefix)
            let frequencyMarkers = [
                " once daily", " twice daily", " daily", " times a day", " times daily",
                " every ", " as needed", " at bedtime", " in the morning", " in the evening"
            ]
            let hasFrequency = frequencyMarkers.contains(where: lower.contains)
            let dosageMarkers = ["tablet", "capsule", "puff", "drop", "spray", "patch", "ml"]
            let hasDosageWithFrequency = hasFrequency && dosageMarkers.contains(where: lower.contains)
            let hasRouteInstruction = lower.contains(" by mouth") || lower.contains(" under the tongue")
            guard startsWithDirection || hasDosageWithFrequency || hasRouteInstruction else { return nil }

            var score = line.confidence * 100
            if startsWithDirection { score += 25 }
            if hasFrequency { score += 12 }
            if hasRouteInstruction { score += 8 }
            return (line, score)
        }
        .max { $0.score < $1.score }?
        .line.value ?? ""
    }

    private static func preferredBarcode(in evidence: [ScanEvidence]) -> ScanEvidence? {
        let barcodes = evidence.filter { $0.kind == .barcode }
        return barcodes
            .filter { !$0.value.lowercased().hasPrefix("http") }
            .max { $0.confidence < $1.confidence }
            ?? barcodes.max { $0.confidence < $1.confidence }
    }

    private static func firstMatch<R: RegexComponent>(in value: String, pattern: R) -> String? where R.RegexOutput == Substring {
        value.firstMatch(of: pattern).map { String($0.output) }
    }

    private static func capture<Output>(in value: String, pattern: Regex<Output>, group: Int) -> String? {
        guard let match = value.firstMatch(of: pattern) else { return nil }
        let mirror = Mirror(reflecting: match.output)
        let children = Array(mirror.children)
        guard children.indices.contains(group), let substring = children[group].value as? Substring else { return nil }
        return String(substring)
    }
}
