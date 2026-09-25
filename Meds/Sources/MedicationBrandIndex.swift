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

    /// Generics whose every tablet and capsule is one modified release, so
    /// the table's brand is that release though its name carries no letters:
    /// Protonix is a delayed-release tablet, Pristiq an extended-release one.
    /// Checked against the FDA directory; a generic sold in any other release
    /// does not belong here.
    private static let inherentRelease: [String: ReleaseForm] = [
        "desvenlafaxine": .extended, "mirabegron": .extended, "ranolazine": .extended,
        "dexlansoprazole": .delayed, "esomeprazole": .delayed, "lansoprazole": .delayed,
        "omeprazole": .delayed, "pantoprazole": .delayed, "rabeprazole": .delayed,
        "mycophenolatesodium": .delayed, "mycophenolicacid": .delayed
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

    /// The brand the table pairs with a generic. `release` is the release the
    /// medication is known to be, from its label or its directory listing: a
    /// modified release withholds a brand of any other, so an extended-release
    /// tacrolimus is never given Prograf, which is immediate-release.
    static func brandName(forGeneric name: String, release: ReleaseForm? = nil) -> String? {
        matchingEntry(for: name, in: genericIndex, release: release)?.brand
    }

    static func genericName(forBrand name: String) -> String? {
        matchingEntry(for: name, in: brandIndex, isBrand: true)?.generic
    }

    /// The table stores generics lowercase, the way the bundled vocabulary does.
    /// This is the form a field shows.
    static func displayName(forGeneric generic: String) -> String {
        guard !generic.isEmpty else { return generic }
        return String(generic.prefix(1)).uppercased() + String(generic.dropFirst())
    }

    /// Resolves any medication name — generic or brand — to the curated pair.
    /// See `brandName(forGeneric:release:)` for `release`.
    static func resolve(_ name: String, release: ReleaseForm? = nil) -> (generic: String, brand: String)? {
        let entry = matchingEntry(for: name, in: genericIndex, release: release)
            ?? matchingEntry(for: name, in: brandIndex, release: release, isBrand: true)
        guard let entry else { return nil }
        return (generic: entry.generic, brand: entry.brand)
    }

    /// The release of the product a medication's name and brand describe, or
    /// nil when neither says and the table does not know it. Letters in either
    /// name come first: "Tacrolimus ER" is extended-release whatever its brand.
    static func release(ofName name: String, brand: String) -> ReleaseForm? {
        if let release = ReleaseForm.named(in: name) ?? ReleaseForm.named(in: brand) { return release }
        let entry = (brand.isEmpty ? nil : matchingEntry(for: brand, in: brandIndex, isBrand: true))
            ?? matchingEntry(for: name, in: genericIndex)
        return entry.map(release(of:))
    }

    /// The release of the product a brand in the table names: its own letters
    /// ("Toprol XL"), then the generic's only release, then immediate, which is
    /// what a reference brand without letters is.
    private static func release(of entry: Pair) -> ReleaseForm {
        ReleaseForm.named(in: entry.brand) ?? inherentRelease[entry.genericKey] ?? .immediate
    }

    private static func matchingEntry(
        for name: String,
        in index: [String: Pair],
        release stated: ReleaseForm? = nil,
        isBrand: Bool = false
    ) -> Pair? {
        let fullKey = key(name)
        guard !fullKey.isEmpty else { return nil }
        if let exact = index[fullKey] {
            return stated?.isModified == true && release(of: exact) != stated ? nil : exact
        }

        guard let (fallbackKey, suffix) = keyByRemovingTrailingToken(from: name),
              let entry = index[fallbackKey] else { return nil }
        guard let suffixRelease = ReleaseForm.named(by: suffix) else {
            return stated?.isModified == true && release(of: entry) != stated ? nil : entry
        }
        // A release suffix is the product's identity, not noise to strip.
        // "Tacrolimus XL" is not Prograf, and "Metformin ER" is not
        // Glucophage: a blank brand is better than the immediate-release one.
        if let stated, stated.isModified, stated != suffixRelease { return nil }
        let entryRelease = release(of: entry)
        if entryRelease == suffixRelease { return entry }
        // A reference brand with release letters added is that release's own
        // brand, "Adderall XR" or "Glucophage XR", and is kept as written.
        guard isBrand, entryRelease == .immediate, suffixRelease.isModified else { return nil }
        let brand = "\(entry.brand) \(suffix.uppercased())"
        return Pair(generic: entry.generic, brand: brand, genericKey: entry.genericKey, brandKey: key(brand))
    }

    private static func keyByRemovingTrailingToken(from value: String) -> (key: String, suffix: String)? {
        let tokens = value
            .lowercased()
            .split(whereSeparator: { !$0.isLetter })

        guard let suffix = tokens.last,
              removableSuffixes.contains(String(suffix)) || ReleaseForm.named(by: String(suffix)) != nil else { return nil }

        let remainingKey = tokens.dropLast().joined()
        guard remainingKey.count >= 5 else { return nil }
        return (remainingKey, String(suffix))
    }

    private static func key(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }
}
