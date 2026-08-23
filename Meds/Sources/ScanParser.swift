import Foundation

enum ScanParser {
    private static let strengthPattern = /(?i)\b\d+(?:\.\d+)?\s?(?:mcg|mg|g|mL|%)(?:\s*\/\s*\d+(?:\.\d+)?\s?(?:mcg|mg|g|mL))?\b/
    private static let quantityPattern = /(?i)\b(?:qty|quantity|contents?)\s*[:#]?\s*(\d+(?:\.\d+)?)\b/
    private static let refillPattern = /(?i)\b(\d+)\s+refills?\s+(?:left|remaining)\b/
    private static let noRefillsPattern = /(?i)\bno\s+refills?\s+(?:left|remaining)\b/
    private static let lotPattern = /(?i)\blot\s*[:#]?\s*([A-Z0-9-]+)\b/
    private static let expirationPattern = /(?i)\b(?:exp|expires?|expiration)\s*[:.]?\s*(\d{1,2})[\/-](\d{2,4})\b/

    static func parse(_ evidence: [ScanEvidence], now: Date = .now) -> MedicationDraft {
        let textEvidence = evidence.filter { $0.kind == .text }
        let lines = textEvidence
            .map(\.value)
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let combined = lines.joined(separator: "\n")

        var draft = MedicationDraft()
        draft.source = .scanned
        draft.evidence = evidence
        draft.overallConfidence = evidence.isEmpty ? 0 : evidence.map(\.confidence).reduce(0, +) / Double(evidence.count)
        draft.strength = firstMatch(in: combined, pattern: strengthPattern) ?? ""
        draft.name = medicationName(from: lines, strength: draft.strength)
        draft.form = inferForm(from: combined)
        draft.currentSupply = capturedQuantity(in: combined)
        draft.refillsRemaining = capturedRefills(in: combined)
        draft.lotNumber = capture(in: combined, pattern: lotPattern, group: 1) ?? ""
        draft.expirationDate = capturedExpiration(in: combined, now: now)
        draft.directions = capturedDirections(from: lines)

        if let barcode = preferredBarcode(in: evidence) {
            draft.productIdentifier = barcode.value
            draft.productIdentifierType = barcode.symbology ?? "Barcode"
        }
        return draft
    }

    private static func medicationName(from lines: [String], strength: String) -> String {
        let stopWords = [
            "tablet", "capsule", "quantity", "contents", "refill", "take", "times a day",
            "dietary supplement", "drug-free", "gluten free", "lactose free", "rx#", "lot", "exp"
        ]

        if !strength.isEmpty,
           let strengthLineIndex = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains(strength) }) {
            let line = lines[strengthLineIndex]
            let cleaned = line.replacingOccurrences(of: strength, with: "", options: [.caseInsensitive])
                .replacingOccurrences(of: "Each capsule contains", with: "", options: [.caseInsensitive])
                .replacingOccurrences(of: "Each tablet contains", with: "", options: [.caseInsensitive])
                .trimmingCharacters(in: CharacterSet(charactersIn: " :-,."))
            if isPlausibleName(cleaned, stopWords: stopWords) { return titleCasedDrugName(cleaned) }

            if strengthLineIndex > 0 {
                let prior = lines[strengthLineIndex - 1]
                if isPlausibleName(prior, stopWords: stopWords) { return titleCasedDrugName(prior) }
            }
        }

        let candidates = lines.filter { isPlausibleName($0, stopWords: stopWords) }
        return candidates.first.map(titleCasedDrugName) ?? ""
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
        guard let raw = capture(in: value, pattern: refillPattern, group: 1) else { return nil }
        return Int(raw)
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

    private static func capturedDirections(from lines: [String]) -> String {
        lines.first { line in
            let lower = line.lowercased()
            return lower.contains("take ") || lower.contains("use ") || lower.contains("times a day") || lower.contains("daily")
        } ?? ""
    }

    private static func preferredBarcode(in evidence: [ScanEvidence]) -> ScanEvidence? {
        let barcodes = evidence.filter { $0.kind == .barcode }
        return barcodes.first { !($0.value.lowercased().hasPrefix("http")) } ?? barcodes.first
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
