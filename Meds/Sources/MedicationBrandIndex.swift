import Foundation

enum MedicationBrandIndex {
    private struct Pair {
        let generic: String
        let brand: String
        let genericKey: String
        let brandKey: String
    }

    private static let removableSuffixes: Set<String> = [
        "hcl", "hydrochloride", "hbr", "hydrobromide", "sodium", "potassium",
        "calcium", "maleate", "tartrate", "succinate", "fumarate", "besylate",
        "mesylate", "citrate", "sulfate", "acetate", "er", "xr", "sr", "cr",
        "dr", "la", "xl", "odt"
    ]

    private static let entries: [Pair] = {
        guard let url = Bundle.main.url(forResource: "MedicationBrandNames", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        return text.split(whereSeparator: \Character.isNewline).compactMap { line in
            let components = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard components.count == 2,
                  !components[0].isEmpty,
                  !components[1].isEmpty else { return nil }

            let generic = String(components[0])
            let brand = String(components[1])
            return Pair(
                generic: generic,
                brand: brand,
                genericKey: key(generic),
                brandKey: key(brand)
            )
        }
    }()

    private static let genericIndex: [String: Pair] = {
        var index: [String: Pair] = [:]
        for entry in entries {
            index[entry.genericKey] = entry
        }
        return index
    }()

    /// One brand can legitimately answer to two generic names — Myfortic is sold as
    /// both `mycophenolate sodium` and `mycophenolic acid`. The first entry in file
    /// order wins so the name a label resolves to never depends on dictionary
    /// ordering, and the table's sort decides it rather than chance.
    private static let brandIndex: [String: Pair] = {
        var index: [String: Pair] = [:]
        for entry in entries where index[entry.brandKey] == nil {
            index[entry.brandKey] = entry
        }
        return index
    }()

    static func brandName(forGeneric name: String) -> String? {
        matchingEntry(for: name, in: genericIndex)?.brand
    }

    static func genericName(forBrand name: String) -> String? {
        matchingEntry(for: name, in: brandIndex)?.generic
    }

    /// Resolves any medication name — generic or brand — to the curated pair.
    static func resolve(_ name: String) -> (generic: String, brand: String)? {
        let entry = matchingEntry(for: name, in: genericIndex)
            ?? matchingEntry(for: name, in: brandIndex)
        guard let entry else { return nil }
        return (generic: entry.generic, brand: entry.brand)
    }

    private static func matchingEntry(for name: String, in index: [String: Pair]) -> Pair? {
        let fullKey = key(name)
        guard !fullKey.isEmpty else { return nil }
        if let exact = index[fullKey] { return exact }

        guard let fallbackKey = keyByRemovingTrailingToken(from: name) else { return nil }
        return index[fallbackKey]
    }

    private static func keyByRemovingTrailingToken(from value: String) -> String? {
        let tokens = value
            .lowercased()
            .split(whereSeparator: { !$0.isLetter })

        guard let suffix = tokens.last,
              removableSuffixes.contains(String(suffix)) else { return nil }

        let remainingKey = tokens.dropLast().joined()
        guard remainingKey.count >= 5 else { return nil }
        return remainingKey
    }

    private static func key(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }
}
