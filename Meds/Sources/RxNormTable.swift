import Foundation

/// The RxNorm concept behind an FDA product: the code RxNorm attaches to its
/// packages, and the clinical drug a branded code is a tradename of.
struct RxNormProduct: Hashable, Sendable {
    let rxcui: String
    /// The generic concept — ingredient, strength and form — when `rxcui` names
    /// a brand; nil when `rxcui` is already the clinical drug.
    let clinicalDrugRxcui: String?

    /// The one code every maker of the same drug, strength and form shares.
    var clinicalDrugCode: String { clinicalDrugRxcui ?? rxcui }
}

/// A slice of NLM's RxNorm "current prescribable content", bundled with the app
/// beside the FDA snapshot and read the same way: sorted by a fixed-width
/// numeric key and binary-searched in the file's own bytes.
///
/// It answers two questions the FDA directory cannot. Which RxNorm concept a
/// scanned bottle's NDC names, which is how a medication here is linked to the
/// same one in Apple Health, whose codings are RxNorm's; and which clinical
/// drug a branded concept is a tradename of, so a generic bottle and a Health
/// entry made from the brand read as one medication. RxNorm is courtesy of the
/// U.S. National Library of Medicine; the attribution is on the Safety sheet.
/// `Tools/build_rxnorm_table.py` writes the file; an absent file leaves every
/// question unanswered rather than wrong.
struct RxNormTable: Sendable {
    static let productsResourceName = "RxNormProducts"

    static let shared: RxNormTable = {
        guard let url = Bundle.main.url(forResource: productsResourceName, withExtension: "txt"),
              let data = try? Data(contentsOf: url) else { return RxNormTable(productsData: Data()) }
        return RxNormTable(productsData: data)
    }()

    static func warmUp() {
        Task.detached(priority: .utility) { _ = shared.isEmpty }
    }

    private let products: SortedKeyTable
    let snapshotDescription: String?

    init(productsData: Data) {
        products = SortedKeyTable(data: productsData, keyWidth: 9)
        snapshotDescription = products.header
    }

    var isEmpty: Bool { products.isEmpty }
    var productCount: Int { products.count }

    func product(for code: NationalDrugCode) -> RxNormProduct? {
        product(forProductKey: code.productKey)
    }

    func product(forProductKey key: String) -> RxNormProduct? {
        guard let fields = products.fields(forKey: key), fields.count >= 3, !fields[1].isEmpty else { return nil }
        return RxNormProduct(rxcui: fields[1], clinicalDrugRxcui: fields[2].isEmpty ? nil : fields[2])
    }

    /// The clinical drug a code names, whichever brand of it: the code itself
    /// for a generic, the generic for a brand. Only brands the products file
    /// mentions are known; any other code answers for itself.
    func clinicalDrugCode(for rxcui: String) -> String {
        brandToClinicalDrug[rxcui] ?? rxcui
    }

    private var brandToClinicalDrug: [String: String] { products.brandToClinicalDrug }
}

/// Lines of tab-separated fields that begin with a fixed-width, strictly
/// ascending decimal key, searched without parsing the whole file into strings.
private struct SortedKeyTable: Sendable {
    private let bytes: [UInt8]
    private let keys: [UInt32]
    private let offsets: [Int]
    private let keyWidth: Int
    let header: String?
    /// Third field by second field, for the rows that carry one. Small: only
    /// branded products have a clinical drug beside them.
    let brandToClinicalDrug: [String: String]

    init(data: Data, keyWidth: Int) {
        let bytes = [UInt8](data)
        var keys: [UInt32] = []
        var offsets: [Int] = []
        var header: String?
        var brands: [String: String] = [:]
        keys.reserveCapacity(bytes.count / 24)
        offsets.reserveCapacity(bytes.count / 24)

        var lineStart = 0
        while lineStart < bytes.count {
            var lineEnd = lineStart
            while lineEnd < bytes.count, bytes[lineEnd] != 0x0A { lineEnd += 1 }
            defer { lineStart = lineEnd + 1 }

            if bytes[lineStart] == UInt8(ascii: "#") {
                if header == nil, let text = String(bytes: bytes[lineStart..<lineEnd], encoding: .utf8) {
                    header = text.dropFirst().trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            guard lineEnd - lineStart > keyWidth, bytes[lineStart + keyWidth] == 0x09 else { continue }
            var key: UInt32 = 0
            var isNumeric = true
            for index in lineStart..<(lineStart + keyWidth) {
                let byte = bytes[index]
                guard byte >= 0x30, byte <= 0x39 else { isNumeric = false; break }
                key = key * 10 + UInt32(byte - 0x30)
            }
            // Binary search needs strictly ascending keys; a row out of order is a
            // malformed file, and dropping it is safer than answering wrongly.
            guard isNumeric, keys.last.map({ $0 < key }) ?? true else { continue }
            keys.append(key)
            offsets.append(lineStart)

            if let line = String(bytes: bytes[lineStart..<lineEnd], encoding: .utf8) {
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                if fields.count >= 3, !fields[2].isEmpty, !fields[1].isEmpty {
                    brands[String(fields[1])] = String(fields[2])
                }
            }
        }
        self.bytes = bytes
        self.keys = keys
        self.offsets = offsets
        self.keyWidth = keyWidth
        self.header = header
        brandToClinicalDrug = brands
    }

    var isEmpty: Bool { keys.isEmpty }
    var count: Int { keys.count }

    func fields(forKey key: String) -> [String]? {
        guard key.count == keyWidth, let numeric = UInt32(key) else { return nil }
        var low = 0
        var high = keys.count - 1
        while low <= high {
            let middle = (low + high) / 2
            if keys[middle] == numeric {
                let offset = offsets[middle]
                var lineEnd = offset
                while lineEnd < bytes.count, bytes[lineEnd] != 0x0A { lineEnd += 1 }
                guard let line = String(bytes: bytes[offset..<lineEnd], encoding: .utf8) else { return nil }
                return line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            } else if keys[middle] < numeric {
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return nil
    }
}
