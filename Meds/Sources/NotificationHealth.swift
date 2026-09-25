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
    /// The last day every dated reminder is planned for, when one is wanted
    /// after it. See `NotificationPlanOutcome.plannedThrough`.
    private(set) var plannedThrough: Date?
    private var hasReported = false

    /// How close the last planned day may come before Today says so. Opening
    /// the app plans a week again, so this is only reached when the cap cut
    /// the dated reminders short.
    nonisolated static let plannedThroughNoticeDays = 3

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

    func record(authorization: UNAuthorizationStatus, planned: Int, failed: Int, plannedThrough: Date? = nil) {
        self.authorization = authorization
        plannedCount = planned
        failedCount = failed
        self.plannedThrough = plannedThrough
        hasReported = true
    }

    /// The day to name in Today's notice, when reminders can be delivered at
    /// all and the last planned day is close. A blocked or unasked permission
    /// has its own banner, which says more.
    func plannedThroughNotice(now: Date, calendar: Calendar = .autoupdatingCurrent) -> Date? {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-force-planned-through-notice") {
            return calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now))
        }
#endif
        guard hasReported, state != .blocked, state != .unasked else { return nil }
        return Self.noticeDay(plannedThrough: plannedThrough, now: now, calendar: calendar)
    }

    /// A last planned day from today through three days ahead. One already
    /// behind today means dated reminders due soon were cut, and the
    /// some-reminders-weren't-set banner already says that.
    nonisolated static func noticeDay(plannedThrough: Date?, now: Date, calendar: Calendar) -> Date? {
        guard let plannedThrough else { return nil }
        let days = SupplyAttention.days(from: now, to: plannedThrough, calendar: calendar)
        return (0...plannedThroughNoticeDays).contains(days) ? calendar.startOfDay(for: plannedThrough) : nil
    }
}
