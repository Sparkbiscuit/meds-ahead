import Foundation

/// Where the SwiftData store lives, and the one-time move that put it there.
///
/// 1.0 kept the store in the app's own Application Support directory. A widget
/// runs in its own process and can only reach a store in an app group
/// container, so 1.1 moves the store there once, on the first launch after
/// the update, before any connection is opened: all three SQLite files
/// together, because a committed transaction can sit in the write-ahead log
/// until the next checkpoint. The copy is checked against the original before
/// the original is set aside, and the original is renamed rather than deleted,
/// so a launch that somehow found the copy unusable could be recovered by hand.
enum StoreLocation {
    static let appGroupIdentifier = "group.com.christoforakis.Meds"
    static let fileName = "Meds.store"
    /// The main file and SQLite's write-ahead log and shared-memory sidecars.
    static let sidecarSuffixes = ["", "-wal", "-shm"]
    /// What a moved store's originals are renamed to, beside their old name.
    static let retiredSuffix = ".before-app-group"
    /// What a copy is called until the whole move is known to be good. The main
    /// file appears under its real name last, so its existence means a finished
    /// move: a launch cut short between two copies used to leave the main file
    /// in place without its write-ahead log, and the next launch opened it and
    /// lost whatever was still in the log.
    static let inProgressSuffix = ".moving"

    /// The store the app and its widgets share.
    static var sharedURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(fileName)
    }

    /// Where 1.0 kept it.
    static var legacyURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fileName)
    }

    enum Outcome: Equatable {
        /// A shared store already exists; nothing is touched, whatever is left
        /// at the legacy location.
        case alreadyShared
        /// There was never a legacy store: a fresh install.
        case nothingToMove
        /// The legacy store was copied, checked, and its originals retired.
        case moved
        /// The copy could not be made or could not be trusted; the legacy store
        /// stays in use and nothing at the shared location was left behind.
        case keptLegacy(String)
    }

    static func migrate(from legacy: URL, to shared: URL, fileManager: FileManager = .default) -> Outcome {
        if fileManager.fileExists(atPath: shared.path) { return .alreadyShared }
        guard fileManager.fileExists(atPath: legacy.path) else { return .nothingToMove }

        var leftBehind: [URL] = []
        func abandon(_ reason: String) -> Outcome {
            for url in leftBehind { try? fileManager.removeItem(at: url) }
            return .keptLegacy(reason)
        }

        do {
            try fileManager.createDirectory(at: shared.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return .keptLegacy("group container: \(error.localizedDescription)")
        }
        // No main file means no earlier attempt finished; whatever one left
        // behind is discarded rather than trusted.
        for suffix in sidecarSuffixes {
            try? fileManager.removeItem(at: URL(fileURLWithPath: shared.path + suffix + inProgressSuffix))
            if !suffix.isEmpty { try? fileManager.removeItem(at: URL(fileURLWithPath: shared.path + suffix)) }
        }
        for suffix in sidecarSuffixes {
            let source = URL(fileURLWithPath: legacy.path + suffix)
            let destination = URL(fileURLWithPath: shared.path + suffix + inProgressSuffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            do {
                try fileManager.copyItem(at: source, to: destination)
                leftBehind.append(destination)
            } catch {
                return abandon("copy of \(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        // The main file and the log are the history; the shared-memory file is
        // rebuilt by SQLite and may legitimately differ.
        for suffix in ["", "-wal"] where fileManager.fileExists(atPath: legacy.path + suffix) {
            let source = URL(fileURLWithPath: legacy.path + suffix)
            let copy = URL(fileURLWithPath: shared.path + suffix + inProgressSuffix)
            guard let sourceSize = fileSize(source, fileManager), let copySize = fileSize(copy, fileManager),
                  sourceSize == copySize, suffix.isEmpty ? copySize > 0 : true else {
                return abandon("the copy of \(source.lastPathComponent) is not the size of the original")
            }
        }
        // Sidecars into place first, the main file last.
        for suffix in ["-shm", "-wal", ""] {
            let copy = URL(fileURLWithPath: shared.path + suffix + inProgressSuffix)
            let destination = URL(fileURLWithPath: shared.path + suffix)
            guard fileManager.fileExists(atPath: copy.path) else { continue }
            do {
                try fileManager.moveItem(at: copy, to: destination)
                leftBehind.append(destination)
            } catch {
                return abandon("placing \(destination.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // From here the shared store is the store. Retiring the originals is
        // best effort: a leftover legacy file is harmless once the shared one
        // exists, whereas going back to the legacy store after a good copy
        // would split the history between two files.
        for suffix in sidecarSuffixes {
            let source = URL(fileURLWithPath: legacy.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let retired = URL(fileURLWithPath: legacy.path + retiredSuffix + suffix)
            try? fileManager.removeItem(at: retired)
            try? fileManager.moveItem(at: source, to: retired)
        }
        return .moved
    }

    private static func fileSize(_ url: URL, _ fileManager: FileManager) -> Int64? {
        (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }
}
