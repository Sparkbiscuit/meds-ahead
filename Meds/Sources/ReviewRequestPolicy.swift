import Foundation

/// When it is fair to ask for an App Store rating.
///
/// The ask is made only after a good moment — a dose was just logged — and only
/// for someone who has used the app for a few days and logged enough doses to
/// have an opinion. Never during onboarding, never twice for one version, and
/// never more than once a season. Apple counts the prompts too, so a request
/// that fails this policy is never made rather than made and rate-limited.
enum ReviewRequestPolicy {
    static let minimumDaysOfUse = 3
    static let minimumTakenDoses = 10
    static let minimumDaysBetweenRequests = 120

    static func shouldRequest(
        now: Date,
        firstUse: Date,
        takenDoses: Int,
        lastRequest: Date?,
        lastRequestedVersion: String?,
        version: String,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard takenDoses >= minimumTakenDoses else { return false }
        guard days(from: firstUse, to: now, calendar: calendar) >= minimumDaysOfUse else { return false }
        if let lastRequestedVersion, lastRequestedVersion == version { return false }
        if let lastRequest, days(from: lastRequest, to: now, calendar: calendar) < minimumDaysBetweenRequests {
            return false
        }
        return true
    }

    private static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}

/// Remembers the dates the policy needs and answers for the running app.
@MainActor
final class ReviewRequestCoordinator {
    static let shared = ReviewRequestCoordinator()

    private enum Key {
        static let firstUse = "reviewRequest.firstUse"
        static let lastRequest = "reviewRequest.lastRequest"
        static let lastRequestedVersion = "reviewRequest.lastRequestedVersion"
    }

    private let defaults: UserDefaults
    private let version: String

    init(defaults: UserDefaults = .standard, version: String? = nil) {
        self.defaults = defaults
        self.version = version
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "0"
    }

    /// The clock starts the first time the app is opened past onboarding, so a
    /// long-time 1.0 user is treated like a new one for a few days and nobody is
    /// asked on the day they installed.
    func noteFirstUseIfNeeded(now: Date = .now) {
#if DEBUG
        // Drives the prompt by hand in the simulator: the clock reads a month old
        // whatever the container already held. Never compiled into a release.
        if ProcessInfo.processInfo.arguments.contains("-backdate-first-use") {
            defaults.set(now.addingTimeInterval(-30 * 24 * 60 * 60), forKey: Key.firstUse)
            return
        }
#endif
        guard defaults.object(forKey: Key.firstUse) == nil else { return }
        defaults.set(now, forKey: Key.firstUse)
    }

    func shouldRequestReview(takenDoses: Int, now: Date = .now) -> Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return false }
#endif
        guard let firstUse = defaults.object(forKey: Key.firstUse) as? Date else {
            noteFirstUseIfNeeded(now: now)
            return false
        }
        return ReviewRequestPolicy.shouldRequest(
            now: now,
            firstUse: firstUse,
            takenDoses: takenDoses,
            lastRequest: defaults.object(forKey: Key.lastRequest) as? Date,
            lastRequestedVersion: defaults.string(forKey: Key.lastRequestedVersion),
            version: version
        )
    }

    func recordRequest(now: Date = .now) {
        defaults.set(now, forKey: Key.lastRequest)
        defaults.set(version, forKey: Key.lastRequestedVersion)
    }
}
