import Foundation

extension Double {
    /// The quantity fields accept as many digits as a person can type, and
    /// `Int(_:)` traps rather than saturating once a `Double` runs past `Int.max`.
    /// Anything that large is a mistyped count, and printing it is better than
    /// ending the app mid-entry.
    private static let wholeNumberPrintingLimit = 1e15

    var medicationQuantityText: String {
        if rounded() == self, magnitude < Double.wholeNumberPrintingLimit {
            return String(Int(self))
        }
        return formatted(.number.precision(.fractionLength(0...2)))
    }

    /// Parses a person-typed quantity. The decimal pad follows the device region,
    /// so a comma-decimal locale types "1,5" — which `Double.init` rejects — and a
    /// scanned draft prefills the same locale-formatted text. Plain `Double` runs
    /// first so "1.5" keeps meaning one and a half everywhere.
    static func medicationQuantity(from text: String, locale: Locale = .autoupdatingCurrent) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let value = Double(trimmed), value.isFinite { return value }
        guard let value = try? Double(trimmed, format: .number.locale(locale)), value.isFinite else { return nil }
        return value
    }
}
