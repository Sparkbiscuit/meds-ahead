import Foundation
import UserNotifications

/// Whether the reminders this app promises are actually going to arrive.
///
/// Scheduling fails quietly by design: iOS reports a denied authorization by simply
/// declining to hold the requests, and `UNUserNotificationCenter.add` reports trouble
/// through an error nobody was reading. For an app whose whole promise is remembering
/// a dose on someone's behalf, silence is the one failure that must never be silent,
/// so the outcome of every scheduling pass is recorded here and shown on Today.
@MainActor
@Observable
final class NotificationHealth {
    static let shared = NotificationHealth()

    enum State: Equatable {
        /// Reminders are scheduled, or none were wanted.
        case fine
        /// Permission has never been asked for, and there are reminders waiting on it.
        case unasked
        /// Permission was refused or has since been withdrawn in Settings.
        case blocked
        /// Permission is granted but iOS refused some of the requests.
        case partlyScheduled(failed: Int)
    }

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var plannedCount = 0
    private(set) var failedCount = 0
    private var hasReported = false

    private init() {}

    /// Nothing is claimed before the first scheduling pass has actually run, so the
    /// banner cannot flash on launch while the real answer is still being fetched.
    var state: State {
        guard hasReported, plannedCount > 0 else { return .fine }
        switch authorization {
        case .denied:
            return .blocked
        case .notDetermined:
            return .unasked
        default:
            return failedCount > 0 ? .partlyScheduled(failed: failedCount) : .fine
        }
    }

    func record(authorization: UNAuthorizationStatus, planned: Int, failed: Int) {
        self.authorization = authorization
        plannedCount = planned
        failedCount = failed
        hasReported = true
    }
}
