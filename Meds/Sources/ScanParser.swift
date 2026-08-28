import Foundation

enum ScanEvidenceQuality {
    static let minimumTextConfidence = 0.45
    private static let contextualMinimumConfidence = 0.30

    static func isUsefulForAutofill(_ evidence: ScanEvidence) -> Bool {
        guard sanitized(evidence) != nil else { return false }
        guard evidence.kind == .text else { return true }
        guard normalized(evidence.value).count >= 3 else { return false }
        if evidence.origin == .liveCamera { return true }
        if evidence.origin == .cameraCapture || evidence.origin == .photoLibrary {
            return evidence.confidence >= 0.25
        }
        if evidence.confidence >= minimumTextConfidence { return true }
        return evidence.confidence >= contextualMinimumConfidence && containsMedicationFieldMarker(evidence.value)
    }

    static func sanitized(_ evidence: ScanEvidence) -> ScanEvidence? {
        guard !evidence.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard evidence.kind == .text else { return evidence }
        guard let value = LabelTextPolicy.sanitized(evidence.value) else { return nil }
        if value == evidence.value { return evidence }
        return ScanEvidence(
            id: evidence.id,
            kind: evidence.kind,
            value: value,
            symbology: evidence.symbology,
            confidence: evidence.confidence,
            origin: evidence.origin,
            captureID: evidence.captureID,
            lineIndex: evidence.lineIndex
        )
    }

    static func deduplicationKey(for evidence: ScanEvidence) -> String {
        "\(evidence.kind.rawValue):\(normalized(evidence.value))"
    }

    static func mergingBest(
        existing: [ScanEvidence],
        additions: [ScanEvidence]
    ) -> [ScanEvidence] {
        var result = existing.compactMap(sanitized).filter(isUsefulForAutofill)
        for item in additions.compactMap(sanitized) where isUsefulForAutofill(item) {
            if let index = result.firstIndex(where: { isEquivalentReading($0, item) }) {
                result[index] = preferred(result[index], item)
            } else {
                result.append(item)
            }
        }
        return Array(result.prefix(80))
    }

    static func isEquivalentReading(_ lhs: ScanEvidence, _ rhs: ScanEvidence) -> Bool {
        guard lhs.kind == rhs.kind else { return false }
        let left = normalized(lhs.value)
        let right = normalized(rhs.value)
        if left == right { return true }
        guard lhs.kind == .text else { return false }

        let leftCompact = left.filter(\.isLetter)
        let rightCompact = right.filter(\.isLetter)
        guard min(leftCompact.count, rightCompact.count) >= 5 else { return false }
        let shorter = leftCompact.count <= rightCompact.count ? leftCompact : rightCompact
        let longer = leftCompact.count > rightCompact.count ? leftCompact : rightCompact
        let missing = longer.count - shorter.count
        let coverage = Double(shorter.count) / Double(longer.count)
        if missing <= 5
            && coverage >= 0.66
            && (longer.hasPrefix(shorter) || longer.hasSuffix(shorter)) {
            return true
        }

        let allowedDistance = shorter.count >= 12 ? 2 : 1
        return shorter.count >= 5
            && missing <= allowedDistance
            && editDistance(shorter, longer) <= allowedDistance
    }

    static func preferred(_ lhs: ScanEvidence, _ rhs: ScanEvidence) -> ScanEvidence {
        readingScore(rhs) > readingScore(lhs) ? rhs : lhs
    }

    private static func readingScore(_ evidence: ScanEvidence) -> Double {
        evidence.confidence * 100 + Double(normalized(evidence.value).count)
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
    private static let packageQuantityPattern = /(?i)\b(\d+(?:\.\d+)?)\s*(?:tablets?|capsules?|patches?|puffs?|doses?|count|ct)\b/
    private static let refillPattern = /(?i)\b(\d+)\s+refills?\s+(?:left|remaining)\b/
    private static let labeledRefillPattern = /(?i)\b(?:refills?|rfls?)\s*(?:left|remaining)?\s*[:#]?\s*(\d+)\b/
    private static let simpleRefillPattern = /(?i)\b(\d+)\s+refills?\b/
    private static let noRefillsPattern = /(?i)\bno\s+refills?\s+(?:left|remaining)\b/
    private static let lotPattern = /(?i)\blot\s*[:#]?\s*([A-Z0-9-]+)\b/
    // Pharmacy vials print "DISCARD AFTER" or "USE BY" far more often than "EXP",
    // and manufacturer bottles print named months ("EXP MAY 2029", "Use by 01JUL26").
    // The date separators accept "|" and "." alongside "/" and "-": Vision reads
    // a printed slash as a pipe often enough that a real label's discard date
    // otherwise silently fails to prefill.
    private static let expirationPattern = /(?i)\b(?:exp(?:\.|ires?|iration)?|use\s+by|best\s+by|discard\s+after|do\s+not\s+use\s+after|beyond\s+use)\s*(?:date)?\s*[:.]?\s*(\d{1,2})[\/\-|.](?:(\d{1,2})[\/\-|.])?(\d{2,4})\b/
    private static let namedMonthExpirationPattern = /(?i)\b(?:exp(?:\.|ires?|iration)?|use\s+by|best\s+by|discard\s+after|do\s+not\s+use\s+after|beyond\s+use)\s*(?:date)?\s*[:.]?\s*(?:(\d{1,2})\s*)?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s*(?:(\d{1,2})(?:st|nd|rd|th)?\s*,?\s+)?(\d{2,4})\b/
    private static let ndcPattern = /(?i)\bNDC\s*[:#]?\s*(\d{4,5}-\d{3,4}-\d{1,2}|\d{10,11})\b/

    private struct TextLine {
        let value: String
        let confidence: Double
        let order: Int
    }

    static func parse(_ evidence: [ScanEvidence], now: Date = .now) -> MedicationDraft {
        let usableEvidence = evidence.compactMap(ScanEvidenceQuality.sanitized)
        let lines = makeTextLines(from: usableEvidence)
        let combined = lines.map(\.value).joined(separator: "\n")

        var draft = MedicationDraft()
        draft.source = .scanned
        draft.evidence = usableEvidence
        draft.overallConfidence = usableEvidence.isEmpty ? 0 : usableEvidence.map(\.confidence).reduce(0, +) / Double(usableEvidence.count)
        draft.strength = firstMatch(in: combined, pattern: strengthPattern) ?? ""
        let resolvedName = medicationName(from: lines, strength: draft.strength)
        draft.name = resolvedName.value
        draft.nameProvenance = resolvedName.provenance
        draft.form = inferForm(from: combined)
        draft.currentSupply = capturedQuantity(from: lines, combined: combined)
        draft.refillsRemaining = capturedRefills(in: combined)
        draft.lotNumber = capture(in: combined, pattern: lotPattern, group: 1) ?? ""
        draft.expirationDate = capturedExpiration(in: combined, now: now)
        draft.directions = capturedDirections(from: lines)

        if let barcode = preferredBarcode(in: usableEvidence) {
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

    private static func medicationName(
        from lines: [TextLine],
        strength: String
    ) -> (value: String, provenance: MedicationNameProvenance) {
        let stopWords = [
            "tablet", "capsule", "quantity", "contents", "refill", "take", "use", "apply",
            "inhale", "instill", "inject", "times a day",
            "dietary supplement", "drug-free", "gluten free", "lactose free", "rx#", "rx #",
            "prescriber", "patient", "pharmacy", "discard", "use by", "ndc", "phone", "address",
            "date filled", "lot", "exp", "doctor", "provider", "www.", ".com", "fax",
            "natural", "flavor", "cherry", "quick dissolve", "may help", "support", "sleep",
            "quality", "guaranteed", "certified", "store ", "cool dry place", "keep", "away",
            "children", "warning", "recommended while", "consult", "federal law", "transfer",
            "color", "shape", "manufacturer", "mfg", "targeted health", "actual size", "topcare", "health"
        ]

        if !strength.isEmpty,
           let strengthLineIndex = lines.firstIndex(where: { $0.value.localizedCaseInsensitiveContains(strength) }) {
            let line = lines[strengthLineIndex].value
            let cleaned = cleanedNameLine(line, removing: strength)
            if isPlausibleName(cleaned, stopWords: stopWords) {
                return (titleCasedDrugName(cleaned), .strengthAnchored)
            }

            for distance in 1...2 {
                for nearbyIndex in [strengthLineIndex - distance, strengthLineIndex + distance]
                    where lines.indices.contains(nearbyIndex) {
                    let nearby = lines[nearbyIndex]
                    if !isMetadataValue(at: nearbyIndex, in: lines),
                       isPlausibleName(nearby.value, stopWords: stopWords) {
                        return (titleCasedDrugName(nearby.value), .strengthAnchored)
                    }
                }
            }
        }

        let candidates: [TextLine] = lines.enumerated().compactMap { index, line -> TextLine? in
            guard !isMetadataValue(at: index, in: lines),
                  isPlausibleName(line.value, stopWords: stopWords) else { return nil }
            return line
        }
        guard candidates.count == 1, let onlyCandidate = candidates.first else {
            return ("", .none)
        }
        return (titleCasedDrugName(onlyCandidate.value), .soleCandidate)
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
        return tidiedNameResidue(cleaned)
    }

    /// Cutting the strength and dosage words out of a line leaves double spaces and a
    /// dangling abbreviation, so "AMPHETAMINE SALT COMBO 20 MG TAB" would reach the
    /// review screen as "Amphetamine Salt Combo  Tab". Abbreviations are matched on
    /// word boundaries so a name that merely contains those letters survives intact.
    static func tidiedNameResidue(_ value: String) -> String {
        var cleaned = value.replacing(/(?i)\b(?:tabs?|caps?|sol|susp|inj)\b/, with: "")
        cleaned = cleaned
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
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

    /// A labeled quantity ("QTY: 60", "CONTENTS 120") is trusted anywhere. The bare
    /// package-count fallback ("120 tablets") is only trusted on lines that are not
    /// directions: "Take 1 tablet by mouth twice daily" fits the same shape, and on
    /// an OTC bottle with no printed QTY it would autofill a supply of 1.
    private static func capturedQuantity(from lines: [TextLine], combined: String) -> Double? {
        if let raw = capture(in: combined, pattern: quantityPattern, group: 1) {
            return Double(raw)
        }
        for line in lines where !isDirectionLike(line.value) {
            if let raw = capture(in: line.value, pattern: packageQuantityPattern, group: 1) {
                return Double(raw)
            }
        }
        return nil
    }

    private static func isDirectionLike(_ value: String) -> Bool {
        let lower = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let directionVerbs = [
            "take ", "use ", "apply ", "inhale ", "instill ", "inject ", "place ",
            "give ", "chew ", "swallow ", "dissolve ", "adults", "children"
        ]
        if directionVerbs.contains(where: lower.hasPrefix) { return true }
        let frequencyMarkers = [
            " once daily", " twice daily", " daily", " times a day", " times daily",
            " every ", " as needed", " as directed", " at bedtime", " by mouth",
            " in the morning", " in the evening", " under the tongue"
        ]
        return frequencyMarkers.contains(where: lower.contains)
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

    /// Labels print both month/year ("EXP 05/2029") and full dates ("EXP 10/01/25").
    /// The middle group must be treated as a day when present: reading "10/01/25"
    /// as month 10 of year 01 would prefill an expiration a quarter-century past.
    private static func capturedExpiration(in value: String, now: Date) -> Date? {
        if let match = value.firstMatch(of: expirationPattern),
           let month = Int(match.1),
           let year = Int(match.3),
           let date = expirationDate(month: month, day: match.2.flatMap { Int($0) }, year: year) {
            return date
        }
        if let match = value.firstMatch(of: namedMonthExpirationPattern),
           let month = monthNumber(named: String(match.2)),
           let year = Int(match.4) {
            let day = match.1.flatMap { Int($0) } ?? match.3.flatMap { Int($0) }
            return expirationDate(month: month, day: day, year: year)
        }
        return nil
    }

    private static func expirationDate(month: Int, day: Int?, year rawYear: Int) -> Date? {
        var year = rawYear
        if year < 100 { year += 2000 }
        guard (1...12).contains(month), (2000...2099).contains(year) else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        if let day, (1...31).contains(day) {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            if let date = calendar.date(from: components),
               calendar.component(.month, from: date) == month {
                return date
            }
        }
        // Month/year-only labels mean "good through that month": use its last day.
        var components = DateComponents()
        components.year = year
        components.month = month + 1
        components.day = 0
        return calendar.date(from: components)
    }

    private static func monthNumber(named value: String) -> Int? {
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        return months.firstIndex(of: value.lowercased()).map { $0 + 1 }
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
            let hasCompleteInstruction = startsWithDirection
                && (hasFrequency || hasRouteInstruction || lower.contains(" as directed"))
            guard hasCompleteInstruction || hasDosageWithFrequency || hasRouteInstruction else { return nil }

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
