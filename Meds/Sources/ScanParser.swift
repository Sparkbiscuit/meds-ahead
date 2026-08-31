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
    // Insulin, heparin and vitamin D print their strength in units or IU rather than
    // a mass, so a label that plainly reads "100 units/mL" left the field blank and
    // made someone retype it. The denominator half is allowed to carry no number of
    // its own, which is how "units/mL" is written.
    // Put the combination shapes before the single-unit ratio shape so a label such
    // as "400-80 MG" cannot be reduced to its trailing component.
    // A vitamin bottle prints "1,000 IU"; without the grouped-number form the
    // match started at "000" and offered a tenfold-wrong strength for confirmation.
    private static let strengthPattern = /(?i)\b(?:(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?\s*[-\u{2013}\/]\s*(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?\s*(?:mcg|mg|g|mL|units?|iu|%)|(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?\s*(?:mcg|mg|g|mL|units?|iu|%)\s*[-\u{2013}\/]\s*(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?\s*(?:mcg|mg|g|mL|units?|iu|%)|(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?\s*(?:mcg|mg|g|mL|units?|iu|%)(?:\s*\/\s*(?:(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?\s*)?(?:mcg|mg|g|mL|units?|iu))?)(?![A-Za-z0-9])/
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
        /// Where this line sat on the capture it came from. A photo yields one
        /// evidence item per recognised line, sorted top to bottom, sharing a
        /// capture and numbered in order; the live camera yields items with neither.
        let captureID: UUID?
        let lineIndex: Int?
    }

    /// Two lines are adjacent when the label says they are.
    ///
    /// Reading adjacency off the evidence *item* was wrong in both directions: the
    /// photo path makes one item per line, so nothing was ever adjacent to anything
    /// and a wrapped sig never assembled; the live path carries no capture identity
    /// at all. With a capture, consecutive line numbers within it decide. Without
    /// one, the order the lines were read in is all there is.
    private static func areAdjacent(_ line: TextLine, _ next: TextLine) -> Bool {
        if let capture = line.captureID, let index = line.lineIndex {
            guard next.captureID == capture, let nextIndex = next.lineIndex else { return false }
            return nextIndex == index + 1
        }
        guard next.captureID == nil else { return false }
        return next.order == line.order + 1
    }

    static func parse(_ evidence: [ScanEvidence], now: Date = .now) -> MedicationDraft {
        let usableEvidence = evidence.compactMap(ScanEvidenceQuality.sanitized)
        let lines = makeTextLines(from: usableEvidence)
        let combined = lines.map(\.value).joined(separator: "\n")

        var draft = MedicationDraft()
        draft.source = .scanned
        draft.evidence = usableEvidence
        draft.overallConfidence = usableEvidence.isEmpty ? 0 : usableEvidence.map(\.confidence).reduce(0, +) / Double(usableEvidence.count)
        draft.strength = capturedStrength(from: lines, combined: combined) ?? ""
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
            for (offset, rawLine) in item.value.components(separatedBy: .newlines).enumerated() {
                let value = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = value.lowercased().split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
                guard !value.isEmpty, seen.insert(key).inserted else { continue }
                result.append(
                    TextLine(
                        value: value,
                        confidence: item.confidence,
                        order: result.count,
                        captureID: item.captureID,
                        lineIndex: item.lineIndex.map { $0 + offset }
                    )
                )
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
           let strengthLineIndex = lines.firstIndex(where: {
               $0.value.localizedCaseInsensitiveContains(strength)
                   || strengthMatches(in: $0.value).contains(strength)
           }) {
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
                        return (titleCasedDrugName(nearby.value), .adjacentToStrength)
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
        if let rawStrength = firstMatch(in: value, pattern: strengthPattern),
           normalizedStrength(rawStrength) == strength {
            cleaned = cleaned.replacingOccurrences(of: rawStrength, with: "", options: [.caseInsensitive])
        }
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
        var tokens = cleaned.split(whereSeparator: \Character.isWhitespace).map { String($0) }
        // Two tokens must survive. A pharmacy imprint sits after a full name
        // ("Sertraline HCl G1"), whereas the "B12" in "Vitamin B12" is the name.
        while tokens.count > 2, let trailing = tokens.last {
            let hasLetters = trailing.contains { $0.isLetter }
            let hasDigits = trailing.contains { $0.isNumber }
            let shortMixedToken = (1...4).contains(trailing.count) && hasLetters && hasDigits
            let trailingSingleLetter = trailing.count == 1 && trailing.first?.isLetter == true
            guard shortMixedToken || trailingSingleLetter else { break }
            tokens.removeLast()
        }
        tokens = tokens.map { token in
            switch token.lowercased() {
            case "hcl": return "HCl"
            case "hbr": return "HBr"
            default: return token
            }
        }
        return tokens.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " :-,."))
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
        guard !isAddressOrPersonName(trimmed),
              trimmed.count >= 3,
              trimmed.count <= 64,
              trimmed.rangeOfCharacter(from: .letters) != nil,
              !trimmed.contains("http") else { return false }
        let lower = trimmed.lowercased()
        return !stopWords.contains(where: lower.contains)
    }

    /// True when a line names a place or a person rather than a medication.
    static func isAddressOrPersonName(_ value: String) -> Bool {
        let tokens = value
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let addressTokens: Set<String> = [
            "st", "street", "ave", "avenue", "rd", "road", "blvd", "boulevard",
            "ln", "lane", "dr", "drive", "ct", "court", "way", "suite", "ste",
            "apt", "unit", "floor", "fl", "box", "po", "hospital", "clinic",
            "pharmacy", "medical", "center", "centre", "hosp", "terrace"
        ]
        if tokens.contains(where: addressTokens.contains) { return true }

        func isDigits(_ token: String, count: Int) -> Bool {
            token.count == count && token.allSatisfy { $0.isNumber }
        }
        if tokens.contains(where: { isDigits($0, count: 5) }) { return true }
        for index in tokens.indices where tokens.indices.contains(index + 1) {
            if isDigits(tokens[index], count: 5) && isDigits(tokens[index + 1], count: 4) {
                return true
            }
        }

        var personName = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if personName.last == "." {
            personName.removeLast()
            personName = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let parts = personName.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return parts.allSatisfy { part in
            isPersonNamePart(String(part))
        }
    }

    private static func isPersonNamePart(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let characters = Array(trimmed)
        guard let first = characters.first,
              let last = characters.last,
              first.isLetter,
              last.isLetter else { return false }

        var previousWasSeparator = false
        for character in characters {
            if character.isLetter {
                previousWasSeparator = false
            } else if character == "'" || character == "\u{2019}" || character == "-" {
                guard !previousWasSeparator else { return false }
                previousWasSeparator = true
            } else {
                return false
            }
        }
        return !previousWasSeparator
    }

    private static func titleCasedDrugName(_ value: String) -> String {
        let tokens = value.split(whereSeparator: \Character.isWhitespace)
        guard tokens.allSatisfy({ token in
            let value = String(token)
            return value == value.uppercased()
                || value.lowercased() == "hcl"
                || value.lowercased() == "hbr"
        }) else { return value }
        return tokens.map { token in
            switch String(token).lowercased() {
            case "hcl": return "HCl"
            case "hbr": return "HBr"
            default: return String(token).capitalized
            }
        }.joined(separator: " ")
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

    /// Canonical display form for a strength read off a label: "50MG" -> "50 mg",
    /// "400-80MG" -> "400-80 mg". Returns nil when `value` holds no strength.
    static func normalizedStrength(_ value: String) -> String? {
        strengthMatches(in: value).first
    }

    /// Every strength-shaped substring in `value`, in canonical form, in order.
    static func strengthMatches(in value: String) -> [String] {
        value.matches(of: strengthPattern).compactMap { canonicalStrength(String($0.output)) }
    }

    private static func canonicalStrength(_ value: String) -> String? {
        let characters = Array(value)
        var result = ""
        var index = 0
        var previousWasNumber = false

        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
                continue
            }
            if character.isNumber {
                let start = index
                repeat { index += 1 } while index < characters.count
                    && (characters[index].isNumber || characters[index] == "." || characters[index] == ",")
                result += String(characters[start..<index]).filter { $0 != "," }
                previousWasNumber = true
                continue
            }
            if character == "-" || character == "–" || character == "/" {
                result += String(character)
                index += 1
                previousWasNumber = false
                continue
            }
            if character == "%" {
                if previousWasNumber { result += " " }
                result += "%"
                index += 1
                previousWasNumber = false
                continue
            }
            guard character.isLetter else { return nil }
            let start = index
            while index < characters.count, characters[index].isLetter {
                index += 1
            }
            guard let unit = canonicalUnit(String(characters[start..<index])) else { return nil }
            if previousWasNumber { result += " " }
            result += unit
            previousWasNumber = false
        }

        let canonical = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return canonical.isEmpty ? nil : canonical
    }

    private static func canonicalUnit(_ value: String) -> String? {
        switch value.lowercased() {
        case "mcg": return "mcg"
        case "mg": return "mg"
        case "g": return "g"
        case "ml": return "mL"
        case "unit": return "unit"
        case "units": return "units"
        case "iu": return "IU"
        default: return nil
        }
    }

    /// Strength belongs to the product, and the product line is where it is printed.
    /// A directions line quotes an amount to *take* — "Inject 10 units" — which is a
    /// dose, not a strength, and on an insulin label it is printed larger and read
    /// first. Direction-shaped lines are consulted only if nothing else carries one.
    private static func capturedStrength(from lines: [TextLine], combined: String) -> String? {
        for line in lines where !isDirectionLike(line.value) {
            if let match = normalizedStrength(line.value) { return match }
        }
        return normalizedStrength(combined)
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
            "give ", "chew ", "swallow ", "dissolve ", "spray ", "adults", "children"
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
           let date = expirationDate(month: month, day: match.2.flatMap { Int($0) }, year: year, now: now) {
            return date
        }
        if let match = value.firstMatch(of: namedMonthExpirationPattern),
           let month = monthNumber(named: String(match.2)),
           let year = Int(match.4) {
            let day = match.1.flatMap { Int($0) } ?? match.3.flatMap { Int($0) }
            return expirationDate(month: month, day: day, year: year, now: now)
        }
        return nil
    }

    /// Nothing dispensed today is good for another sixty years, so a reading that far
    /// out is an OCR slip on the year — a `2026` read as `2096` — rather than a date
    /// worth offering for confirmation. Dates already in the past are kept: an expired
    /// package is real information, and the detail screen flags it as expired.
    private static let latestPlausibleExpirationYears = 6

    private static func expirationDate(month: Int, day: Int?, year rawYear: Int, now: Date) -> Date? {
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
                return plausibleExpiration(date, now: now)
            }
        }
        // Month/year-only labels mean "good through that month": use its last day.
        var components = DateComponents()
        components.year = year
        components.month = month + 1
        components.day = 0
        return calendar.date(from: components).flatMap { plausibleExpiration($0, now: now) }
    }

    private static func plausibleExpiration(_ date: Date, now: Date) -> Date? {
        let calendar = Calendar(identifier: .gregorian)
        guard let horizon = calendar.date(byAdding: .year, value: latestPlausibleExpirationYears, to: now) else {
            return date
        }
        return date <= horizon ? date : nil
    }

    private static func monthNumber(named value: String) -> Int? {
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        return months.firstIndex(of: value.lowercased()).map { $0 + 1 }
    }

    private static let trustedDirectionVerbs = [
        "take", "use", "apply", "inhale", "instill", "inject", "place",
        "give", "chew", "swallow", "dissolve", "spray", "swish"
    ]
    private static let directionsDatePattern = /\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}/
    private static let directionsPhonePattern = /\d{3}[-.\s]\d{3}[-.\s]\d{4}/
    private static let directionsCourseLengthPattern = /(?i)\b(?:for|x)\s+\d+(?:\.\d+)?\s+days?\b/

    /// A pharmacy sig may omit the verb entirely — "ONE CAPSULE TWICE DAILY" is a
    /// complete instruction — so a leading dose phrase opens the same door a verb
    /// does. What stays shut is a line that opens with neither, which is how an OCR
    /// slip such as "like 2 tablets by mouth" (a mangled "Take") is turned away.
    private static let doseQuantityWords = [
        "one", "two", "three", "four", "five", "six", "half", "a", "an"
    ]
    private static let doseFormWords = [
        "tablet", "tablets", "capsule", "capsules", "puff", "puffs", "drop", "drops",
        "spray", "sprays", "patch", "patches", "ml", "teaspoon", "teaspoons", "tsp",
        "tablespoon", "tablespoons", "tbsp", "unit", "units", "dose", "doses",
        "lozenge", "lozenges", "suppository", "suppositories", "tab", "tabs", "cap", "caps"
    ]

    private static func startsWithDosePhrase(_ value: String) -> Bool {
        let opening = value.drop(while: { $0.isWhitespace || $0.isPunctuation })
        let tokens = String(opening)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "/" && $0 != "-" })
            .map(String.init)
        guard let first = tokens.first else { return false }

        var doseFormIndex: Int
        if isNumericDoseAmount(first) {
            if tokens.count > 2,
               (tokens[1] == "to" || tokens[1] == "-"),
               isNumericDoseAmount(tokens[2]) {
                doseFormIndex = 3
            } else {
                doseFormIndex = 1
            }
        } else if doseQuantityWords.contains(first) || first == "one-half" {
            doseFormIndex = 1
        } else {
            return false
        }
        guard tokens.indices.contains(doseFormIndex) else { return false }
        return doseFormWords.contains(tokens[doseFormIndex])
    }

    private static func isNumericDoseAmount(_ value: String) -> Bool {
        func isUnsignedInteger(_ part: Substring) -> Bool {
            !part.isEmpty && part.allSatisfy { $0.isNumber }
        }

        let decimalParts = value.split(separator: ".", omittingEmptySubsequences: false)
        if decimalParts.count <= 2,
           decimalParts.allSatisfy(isUnsignedInteger) {
            return true
        }
        let fractionParts = value.split(separator: "/", omittingEmptySubsequences: false)
        if fractionParts.count == 2,
           fractionParts.allSatisfy(isUnsignedInteger) {
            return true
        }
        let rangeParts = value.split(separator: "-", omittingEmptySubsequences: false)
        return rangeParts.count == 2 && rangeParts.allSatisfy(isUnsignedInteger)
    }

    private static func directionOpening(afterQualifier value: String) -> String {
        let candidate = value.drop(while: { $0.isWhitespace })
        let lower = String(candidate).lowercased()
        for qualifier in ["adults", "children"] {
            guard lower.hasPrefix(qualifier) else { continue }
            let remainder = candidate.dropFirst(qualifier.count)
            guard let first = remainder.first,
                  first == ":" || first.isWhitespace else { continue }
            return String(remainder.drop(while: { $0 == ":" || $0.isWhitespace }))
        }
        return String(candidate)
    }

    /// True when the line opens the way a direction opens, by verb or by dose phrase.
    private static func opensLikeDirections(_ value: String) -> Bool {
        let opening = directionOpening(afterQualifier: value)
        return directionVerb(in: opening) != nil || startsWithDosePhrase(opening)
    }

    private static func directionVerb(in value: String) -> String? {
        let candidate = value.drop(while: { $0.isWhitespace || $0.isPunctuation })
        let lower = String(candidate).lowercased()
        for verb in trustedDirectionVerbs {
            guard lower.hasPrefix(verb) else { continue }
            let remainder = lower.dropFirst(verb.count)
            if let next = remainder.first, !next.isWhitespace && !next.isPunctuation {
                continue
            }
            return verb
        }
        return nil
    }

    private static func hasDirectionFrequency(_ value: String) -> Bool {
        let lower = value.lowercased()
        let padded = " \(lower) "
        let frequencyMarkers = [
            " once daily", " twice daily", " daily", " times a day", " time a day",
            " times daily", " time daily", " every ", " as needed", " at bedtime", " in the morning",
            " in the evening", " once a day", " twice a day", " each day", " per day",
            " weekly", " nightly", " monthly", " a week", " per week", " a month", " per month",
            " with food", " with meals", " before meals", " after meals", " before breakfast",
            " after breakfast", " before bed", " at night", " each night", " each morning",
            " each evening"
        ]
        if frequencyMarkers.contains(where: padded.contains) { return true }

        let frequencyAbbreviations: Set<String> = [
            "qd", "bid", "tid", "qid", "prn", "qhs", "hs", "qam", "qpm", "qod",
            "q4h", "q6h", "q8h", "q12h", "q24h", "ac", "pc"
        ]
        let tokens = lower
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        if tokens.contains(where: frequencyAbbreviations.contains) { return true }
        if value.firstMatch(of: directionsCourseLengthPattern) != nil { return true }

        let weekdays: Set<String> = [
            "mon", "monday", "mondays", "tue", "tues", "tuesday", "tuesdays",
            "wed", "wednesday", "wednesdays", "thu", "thur", "thurs", "thursday", "thursdays",
            "fri", "friday", "fridays", "sat", "saturday", "saturdays", "sun", "sunday", "sundays"
        ]
        let weekdayCount = lower
            .split(whereSeparator: { !$0.isLetter })
            .reduce(into: 0) { count, token in
                if weekdays.contains(String(token)) { count += 1 }
            }
        if weekdayCount >= 2 { return true }
        guard weekdayCount == 1 else { return false }
        let trimmed = lower.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.hasSuffix(",") && !trimmed.hasSuffix(" and")
    }

    /// True when `value` is a complete, trustworthy label direction.
    static func isTrustedDirections(_ value: String) -> Bool {
        guard (8...200).contains(value.count), opensLikeDirections(value) else { return false }

        let lower = value.lowercased()
        // Whole words, not substrings: "lot" inside "lotion" and "exp" inside
        // "exposed" were rejecting perfectly good topical directions.
        let dispensingWords: Set<String> = [
            "rph", "filled", "fill", "ndc", "qty", "quantity", "refill", "refills",
            "prescriber", "prescribed", "pharmacist", "pharmacy", "discard", "lot",
            "mfg", "exp", "patient", "doctor", "dr"
        ]
        let words = lower.split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard !words.contains(where: dispensingWords.contains) else { return false }
        guard !lower.contains("rx#"), !lower.contains("rx #") else { return false }
        guard value.firstMatch(of: directionsDatePattern) == nil,
              value.firstMatch(of: directionsPhonePattern) == nil else { return false }

        let hasOCRGarbage = value
            .split(whereSeparator: { !$0.isLetter })
            .contains { token in
                guard token.count >= 3 else { return false }
                let characters = Array(token)
                return zip(characters, characters.dropFirst()).contains { pair in
                    pair.0.isLowercase && pair.1.isUppercase
                }
            }
        guard !hasOCRGarbage else { return false }

        return hasDirectionFrequency(value)
            || lower.contains("as directed")
            || lower.contains("as needed")
    }

    private static func capturedDirections(from lines: [TextLine]) -> String {
        let excludedFragments = [
            "daily value", "% daily", "use by", "do not use", "discard after",
            "for external use only", "expiration", "expires", "lot number"
        ]
        let trusted = lines.compactMap { line -> (line: TextLine, score: Double)? in
            let lower = line.value
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard isTrustedDirections(line.value) else { return nil }
            guard !excludedFragments.contains(where: lower.contains) else { return nil }

            let startsWithDirection = directionVerb(in: line.value) != nil
            let hasFrequency = hasDirectionFrequency(line.value)
            let hasRouteInstruction = lower.contains(" by mouth") || lower.contains(" under the tongue")

            var score = line.confidence * 100
            if startsWithDirection { score += 25 }
            if hasFrequency { score += 12 }
            if hasRouteInstruction { score += 8 }
            return (line, score)
        }
        if let best = trusted.max(by: { $0.score < $1.score }) {
            return best.line.value
        }

        // A wrapped sig must stay adjacent, bounded, and inside a single capture.
        // Joining across captures once produced "TAKE 1 TABLET Patient: Jane Doe
        // TWICE DAILY" out of three unrelated readings.
        for index in lines.indices {
            let line = lines[index]
            guard opensLikeDirections(line.value),
                  !isTrustedDirections(line.value) else { continue }
            for additionalLines in 1...2 {
                let endIndex = index + additionalLines
                guard lines.indices.contains(endIndex),
                      areAdjacent(lines[endIndex - 1], lines[endIndex]) else { break }
                let joined = (index...endIndex).map { lines[$0].value }.joined(separator: " ")
                if isTrustedDirections(joined) { return joined }
            }
        }
        return ""
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
