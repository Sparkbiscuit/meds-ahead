import Foundation

/// A National Drug Code in the one form every rendering reduces to: eleven
/// digits laid out labeler (5), product (4), package (2).
///
/// The FDA assigns codes in three ten-digit layouts — 4-4-2, 5-3-2 and 5-4-1 —
/// and a label may print any of them, the zero-padded eleven-digit layout that
/// billing systems use, or the bare digits of either. Only the eleven-digit form
/// is unambiguous, so it is what the bundled directory is keyed on and what a
/// reviewed medication stores.
struct NationalDrugCode: Hashable, Sendable {
    /// Eleven ASCII digits.
    let digits: String

    init?(canonicalDigits: String) {
        guard canonicalDigits.count == 11, canonicalDigits.allSatisfy(\.isASCIIDigit) else { return nil }
        digits = canonicalDigits
    }

    /// Pads each segment to the eleven-digit layout. A segment wider than its slot
    /// is not a code at all.
    init?(labeler: Substring, product: Substring, package: Substring) {
        guard (1...5).contains(labeler.count), (1...4).contains(product.count), (1...2).contains(package.count),
              [labeler, product, package].allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }) else { return nil }
        digits = Self.padded(labeler, to: 5) + Self.padded(product, to: 4) + Self.padded(package, to: 2)
    }

    /// The nine digits that name the product regardless of package size, which is
    /// the level at which name, strength and form are decided.
    var productKey: String { String(digits.prefix(9)) }

    /// `00093-1039-01`
    var hyphenated: String {
        "\(digits.prefix(5))-\(digits.dropFirst(5).prefix(4))-\(digits.suffix(2))"
    }

    private static func padded(_ segment: Substring, to width: Int) -> String {
        String(repeating: "0", count: width - segment.count) + segment
    }
}

/// Where a code was read decides how much it has to prove. A barcode carries a
/// check digit, so a decoded code is the code that was printed; OCR of printed
/// digits has no such guarantee and needs the rest of the label to agree.
enum NDCReadingSource: Hashable, Sendable {
    case printedText
    case barcode
}

struct NDCReading: Hashable, Sendable {
    /// Every code the reading could denote. Hyphenated and eleven-digit readings
    /// have one; ten bare digits have three, because the layout is not recoverable
    /// from the digits alone.
    let candidates: [NationalDrugCode]
    let source: NDCReadingSource
    /// The digits as read, kept for the product-code row when nothing resolves.
    let raw: String
}

extension NationalDrugCode {
    /// Vision reads a printed zero as the letter O and a one as I or l often enough
    /// that refusing those would drop a real code; the directory lookup and the
    /// label itself decide whether the repaired digits name the right product.
    private static let printedPattern =
        /(?i)\bNDC\s*(?:#|no\.?|number)?\s*[:.]?\s*([0-9OIl]{4,5}-[0-9OIl]{3,4}-[0-9OIl]{1,2}|[0-9OIl]{10,11})(?![0-9OIl])/

    /// Every code printed in a label's text, in order, without repeats.
    static func readings(inLabelText text: String) -> [NDCReading] {
        var seen: Set<String> = []
        return text.matches(of: printedPattern).compactMap { match in
            let repaired = String(match.1.map(repairedDigit))
            let candidates = candidates(fromRendering: repaired)
            guard !candidates.isEmpty, seen.insert(repaired).inserted else { return nil }
            return NDCReading(candidates: candidates, source: .printedText, raw: repaired)
        }
    }

    /// The code inside a manufacturer barcode, when the barcode carries one.
    ///
    /// A US drug package's GTIN is its ten-digit NDC wrapped in a `3` number-system
    /// digit and a check digit: `3` + NDC + check for UPC-A, `003` + NDC + check
    /// once padded to fourteen digits. GS1-128 and DataMatrix payloads prefix the
    /// same GTIN with application identifier `01`. A pharmacy's own barcode is an
    /// Rx number and decodes to nothing here, which is the correct answer for it.
    static func readings(inBarcode payload: String) -> [NDCReading] {
        guard let gtin = gtin14(from: payload) else { return [] }
        let characters = Array(gtin)
        guard characters[1] == "0", characters[2] == "3" else { return [] }
        let candidates = candidates(fromTenDigits: String(characters[3..<13]))
        guard !candidates.isEmpty else { return [] }
        return [NDCReading(candidates: candidates, source: .barcode, raw: payload)]
    }

    /// Codes a hyphenated or bare rendering could denote.
    static func candidates(fromRendering rendering: String) -> [NationalDrugCode] {
        let segments = rendering.split(separator: "-", omittingEmptySubsequences: false)
        if segments.count == 3 {
            let validLayouts: Set<[Int]> = [[4, 4, 2], [5, 3, 2], [5, 4, 1], [5, 4, 2]]
            guard validLayouts.contains(segments.map(\.count)),
                  let code = NationalDrugCode(labeler: segments[0], product: segments[1], package: segments[2]) else {
                return []
            }
            return [code]
        }
        guard segments.count == 1, rendering.allSatisfy(\.isASCIIDigit) else { return [] }
        switch rendering.count {
        case 11: return NationalDrugCode(canonicalDigits: rendering).map { [$0] } ?? []
        case 10: return candidates(fromTenDigits: rendering)
        default: return []
        }
    }

    /// Ten bare digits fit all three native layouts, and nothing in the digits says
    /// which one was meant. All three are offered; the directory settles it.
    static func candidates(fromTenDigits digits: String) -> [NationalDrugCode] {
        guard digits.count == 10, digits.allSatisfy(\.isASCIIDigit) else { return [] }
        return [(4, 4, 2), (5, 3, 2), (5, 4, 1)].compactMap { labeler, product, package in
            NationalDrugCode(
                labeler: digits.prefix(labeler),
                product: digits.dropFirst(labeler).prefix(product),
                package: digits.suffix(package)
            )
        }
    }

    /// The fourteen-digit GTIN inside a barcode payload, or nil when the payload is
    /// not a GTIN or fails its own check digit.
    static func gtin14(from payload: String) -> String? {
        var body = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        // DataMatrix payloads may open with an FNC1 separator before the first identifier.
        body = body.trimmingCharacters(in: CharacterSet(charactersIn: "\u{1D}"))
        if body.hasPrefix("(01)") {
            body = String(body.dropFirst(4).prefix(14))
        } else if body.hasPrefix("01"), body.count >= 16, body.dropFirst(2).prefix(14).allSatisfy(\.isASCIIDigit) {
            body = String(body.dropFirst(2).prefix(14))
        }
        guard !body.isEmpty, body.allSatisfy(\.isASCIIDigit) else { return nil }
        let padded: String
        switch body.count {
        case 14: padded = body
        case 13: padded = "0" + body
        case 12: padded = "00" + body
        default: return nil
        }
        return hasValidGS1CheckDigit(padded) ? padded : nil
    }

    static func hasValidGS1CheckDigit(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == digits.count, values.count >= 8, let check = values.last else { return false }
        var sum = 0
        for (position, value) in values.dropLast().reversed().enumerated() {
            sum += value * (position.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10 == check
    }

    private static func repairedDigit(_ character: Character) -> Character {
        switch character {
        case "O", "o": "0"
        case "I", "i", "l", "L": "1"
        default: character
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
