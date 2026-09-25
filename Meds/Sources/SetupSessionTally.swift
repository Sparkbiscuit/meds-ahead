import Foundation

/// The bottles a run of scans has put away, in the words the scanner's bar shows.
///
/// On the day someone comes home from the hospital, a caregiver may add a dozen
/// bottles in a row, and by the fifth the question is which ones are done. The
/// scanner answers it without leaving the camera: names as they were saved, and
/// the medications a bottle was added to rather than saved as new.
struct SetupSessionTally: Hashable, Sendable {
    enum Entry: Hashable, Sendable {
        /// Saved as a new medication, under this name.
        case added(String)
        /// Added to a medication already tracked, by that medication's name.
        case addedTo(String)
    }

    private(set) var entries: [Entry] = []

    var isEmpty: Bool { entries.isEmpty }

    mutating func recordAdded(_ name: String) {
        entries.append(.added(name.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    mutating func recordAddedTo(_ name: String) {
        entries.append(.addedTo(name.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    /// "3 added: Tacrolimus, Prednisone and Furosemide · Added to Amlodipine",
    /// or nil before the first bottle. The list is the locale's own, so a
    /// region that writes a serial comma gets one.
    func summary(locale: Locale = .autoupdatingCurrent) -> String? {
        let added = entries.compactMap { entry -> String? in
            if case let .added(name) = entry { name } else { nil }
        }
        // A medication named once however many bottles went into it: the line
        // says where bottles went, and a name repeated reads as two medications.
        var addedTo: [String] = []
        for case let .addedTo(name) in entries where !addedTo.contains(name) {
            addedTo.append(name)
        }
        var parts: [String] = []
        if !added.isEmpty {
            parts.append("\(added.count) added: \(added.formatted(.list(type: .and).locale(locale)))")
        }
        if !addedTo.isEmpty {
            parts.append("Added to \(addedTo.formatted(.list(type: .and).locale(locale)))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
