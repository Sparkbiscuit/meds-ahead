import Foundation

/// One product from the FDA National Drug Code Directory, reduced to the facts
/// a label review needs.
struct NDCProduct: Hashable, Sendable {
    /// Labeler (5) and product (4) digits of the code.
    let productKey: String
    /// The nonproprietary name as the labeler listed it, lowercased.
    let genericName: String
    /// The proprietary name when the labeler listed one that is not merely the
    /// generic restated; empty otherwise.
    let brandName: String
    /// Formatted by the build tool the way a label prints it: `50 mg`,
    /// `800-160 mg`, `15 mg/5 mL`. Empty when the listing carries no usable strength.
    let strength: String
    let form: MedicationForm
    /// What the listing claims about release: its dosage form ("CAPSULE,
    /// EXTENDED RELEASE"), else its names. Nil for a row written without the
    /// column, where only release letters in the brand ("Astagraf XL") say it.
    ///
    /// Immediate means only that the listing claims nothing else. The FDA
    /// files some delayed-release products as plain capsules, Tecfidera among
    /// them, so an immediate listing is not proof against delayed release.
    let release: ReleaseForm?

    /// The release, where it is what tells two products of one drug apart: a
    /// tablet, capsule or oral liquid. A patch is extended-release by nature,
    /// and a label for a patch or an injection seldom prints a release, so
    /// asking one to would only refuse codes it names correctly.
    var comparableRelease: ReleaseForm? {
        switch form {
        case .tablet, .capsule, .liquid: release
        default: nil
        }
    }
}

/// The FDA National Drug Code Directory, trimmed to what a label needs and
/// bundled with the app.
///
/// The directory is public domain and refreshed daily by the FDA. The bundled
/// copy is a snapshot taken at release time by `Tools/build_ndc_directory.py`,
/// sorted by nine-digit product key, so a lookup is a binary search over the
/// file's own bytes: about a hundred thousand products cost one buffer and two
/// small arrays rather than a dictionary of a hundred thousand strings. Loading
/// happens once, on first use, off the main actor wherever the parse pipeline
/// already runs.
struct NDCDirectory: Sendable {
    static let resourceName = "NDCDirectory"

    static let shared: NDCDirectory = {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "txt"),
              let data = try? Data(contentsOf: url) else {
            return NDCDirectory(data: Data())
        }
        return NDCDirectory(data: data)
    }()

    /// Touches the shared directory so its one-time load happens before the
    /// scanner needs an answer, never on the main actor.
    static func warmUp() {
        Task.detached(priority: .utility) { _ = shared.count }
    }

    private let bytes: [UInt8]
    private let keys: [UInt32]
    private let offsets: [Int]
    /// The tool's header line, without its leading `# `: what was snapshotted and when.
    let snapshotDescription: String?

    init(data: Data) {
        let bytes = [UInt8](data)
        var keys: [UInt32] = []
        var offsets: [Int] = []
        var header: String?
        keys.reserveCapacity(bytes.count / 48)
        offsets.reserveCapacity(bytes.count / 48)

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
            // A row is nine digits, a tab, and the product's fields.
            guard lineEnd - lineStart >= 10, bytes[lineStart + 9] == 0x09 else { continue }
            var key: UInt32 = 0
            var isNumeric = true
            for index in lineStart..<(lineStart + 9) {
                let byte = bytes[index]
                guard byte >= 0x30, byte <= 0x39 else { isNumeric = false; break }
                key = key * 10 + UInt32(byte - 0x30)
            }
            // Binary search needs strictly ascending keys. A row out of order is a
            // malformed file, and dropping it is safer than answering wrongly.
            guard isNumeric, keys.last.map({ $0 < key }) ?? true else { continue }
            keys.append(key)
            offsets.append(lineStart)
        }

        self.bytes = bytes
        self.keys = keys
        self.offsets = offsets
        snapshotDescription = header
    }

    var count: Int { keys.count }
    var isEmpty: Bool { keys.isEmpty }

    func product(for code: NationalDrugCode) -> NDCProduct? {
        product(forKey: code.productKey)
    }

    func product(forKey key: String) -> NDCProduct? {
        guard key.count == 9, let numeric = UInt32(key) else { return nil }
        var low = 0
        var high = keys.count - 1
        while low <= high {
            let middle = (low + high) / 2
            if keys[middle] == numeric {
                return parseRow(at: offsets[middle], key: key)
            } else if keys[middle] < numeric {
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return nil
    }

    /// Every product listed under one five-digit labeler code, in key order. A
    /// labeler numbers its line in sequence, so these are the codes a misread
    /// product segment lands on.
    func products(withLabeler labeler: String) -> [NDCProduct] {
        guard labeler.count == 5, let numeric = UInt32(labeler) else { return [] }
        let first = numeric * 10_000
        var low = 0
        var high = keys.count
        while low < high {
            let middle = (low + high) / 2
            if keys[middle] < first { low = middle + 1 } else { high = middle }
        }
        var products: [NDCProduct] = []
        var index = low
        while index < keys.count, keys[index] < first + 10_000 {
            let key = String(format: "%09u", keys[index])
            if let product = parseRow(at: offsets[index], key: key) { products.append(product) }
            index += 1
        }
        return products
    }

    private func parseRow(at offset: Int, key: String) -> NDCProduct? {
        var lineEnd = offset
        while lineEnd < bytes.count, bytes[lineEnd] != 0x0A { lineEnd += 1 }
        guard let line = String(bytes: bytes[offset..<lineEnd], encoding: .utf8) else { return nil }
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 5 else { return nil }
        return NDCProduct(
            productKey: key,
            genericName: fields[1],
            brandName: fields[2],
            strength: fields[3],
            form: MedicationForm(rawValue: fields[4]) ?? .other,
            release: fields.count >= 6 ? ReleaseForm(directoryValue: fields[5]) : ReleaseForm.named(in: fields[2])
        )
    }
}
