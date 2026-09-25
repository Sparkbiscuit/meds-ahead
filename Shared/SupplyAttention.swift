import Foundation

/// Whether a medication's supply needs someone to act, decided once over plain
/// values so Supply, Today, the detail screen, the runs-out widget and the
/// notification planner cannot disagree. They used to: the screens and the
/// alert counted different lead times, and a refill marked requested or ready
/// silenced every one of them for good, even with nothing left on hand.
struct SupplyAttention: Equatable, Sendable {
    /// The least warning worth giving when a prescription has to be renewed before it
    /// can be filled: reaching a prescriber, and their reaching the pharmacy, is not
    /// a same-day errand. A longer lead time the person chose themselves still wins.
    static let prescriberLeadDays = 10

    /// How long a refill in progress may run past its expected or pickup date and
    /// still stand in for the warning: the warning returns at the start of the
    /// second day after that date. A pharmacy a day behind is ordinary; one two
    /// days behind may not be coming, and the warning is then the only prompt.
    static let refillGraceDays = 2

    /// With this many days left or fewer, no refill in progress quiets the
    /// warning: a refill that does not arrive is then a missed dose, however
    /// recently it was asked for.
    static let refillPauseMinimumDays = 2

    /// The hour a refill check is announced, the same as every refill alert.
    static let alertHour = 9

    let daysRemaining: Int?
    let onHand: Bool
    /// The forecast's assumptions used up the ledger: its zero days are where
    /// they ran out, not a runway, and only a count can say what is left.
    let needsCount: Bool
    let refillLeadDays: Int
    let refillsRemaining: Int?
    let refillInProgress: Bool
    /// Whole days since the refill's expected or pickup date: negative while it
    /// is still ahead, nil when no date was given.
    let daysSinceRefillDate: Int?

    /// The lead time the warning actually uses.
    var leadDays: Int {
        Self.leadDays(refillLeadDays: refillLeadDays, refillsRemaining: refillsRemaining)
    }

    /// Inside the lead time, out, or not known until someone counts.
    var isLow: Bool {
        needsCount || !onHand || daysRemaining.map { $0 <= leadDays } ?? false
    }

    /// A refill in progress stands in for the warning only while it is still
    /// believable: not run late past its grace, with enough left to wait for it,
    /// due before the supply runs out, and something on hand. An unknown runway
    /// is not a short one.
    var refillPauseHolds: Bool {
        // A refill can stand in for a low count, not for a count nobody has
        // made: what is on hand now may already be nothing.
        guard refillInProgress, onHand, !needsCount else { return false }
        if let daysSinceRefillDate, daysSinceRefillDate >= Self.refillGraceDays { return false }
        if let daysRemaining, daysRemaining <= Self.refillPauseMinimumDays { return false }
        // Due on the run-out day or after it, a refill that arrives exactly when
        // promised can still leave doses with nothing to take, and the person has
        // told the app so: that is a gap to close, not a refill on its way.
        if let daysSinceRefillDate, let daysRemaining, -daysSinceRefillDate >= daysRemaining { return false }
        return true
    }

    var needsAttention: Bool {
        isLow && !refillPauseHolds
    }

    init(
        daysRemaining: Int?,
        onHand: Bool,
        needsCount: Bool,
        refillLeadDays: Int,
        refillsRemaining: Int?,
        refillInProgress: Bool,
        daysSinceRefillDate: Int?
    ) {
        self.daysRemaining = daysRemaining
        self.onHand = onHand
        self.needsCount = needsCount
        self.refillLeadDays = refillLeadDays
        self.refillsRemaining = refillsRemaining
        self.refillInProgress = refillInProgress
        self.daysSinceRefillDate = daysSinceRefillDate
    }

    init(
        medication: Medication,
        forecast: SupplyForecast,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let inProgress = medication.refillStatus != .none
        self.init(
            daysRemaining: forecast.daysRemaining,
            onHand: forecast.currentSupply > 0,
            needsCount: forecast.needsCount,
            refillLeadDays: medication.refillLeadDays,
            refillsRemaining: medication.refillsRemaining,
            refillInProgress: inProgress,
            daysSinceRefillDate: inProgress
                ? medication.refillStatusDate.map { Self.days(from: $0, to: now, calendar: calendar) }
                : nil
        )
    }

    /// No refills left means a prescriber first, so the lead is never shorter
    /// than theirs.
    static func leadDays(refillLeadDays: Int, refillsRemaining: Int?) -> Int {
        refillsRemaining == 0 ? max(refillLeadDays, prescriberLeadDays) : refillLeadDays
    }

    /// The lead time as the warning uses it: "7 days before", or the longer
    /// lead no refills left imposes, with the reason. Showing only the chosen
    /// seven days beside a warning that came on the tenth read as a fault.
    static func leadTimeText(refillLeadDays: Int, refillsRemaining: Int?) -> String {
        let lead = leadDays(refillLeadDays: refillLeadDays, refillsRemaining: refillsRemaining)
        return lead == refillLeadDays
            ? "\(lead.dayCountText) before"
            : "\(lead.dayCountText) before, because no refills are left"
    }

    /// Under the lead-time stepper, which shows the person's own choice: why
    /// the warning will come earlier than that, or nil when it will not.
    static func lengthenedLeadNote(refillLeadDays: Int, refillsRemaining: Int?) -> String? {
        let lead = leadDays(refillLeadDays: refillLeadDays, refillsRemaining: refillsRemaining)
        guard lead != refillLeadDays else { return nil }
        return "No refills are left, so the warning comes \(lead.dayCountText) before, to allow time for a new prescription."
    }

    /// Whole calendar days from the day of one moment to the day of another;
    /// negative when the second is earlier.
    static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    /// The morning a refill in progress stops standing in for the warning: the
    /// end of its grace after the refill's date, or the day the runway reaches
    /// its minimum, whichever comes first. Nil with neither date to go on.
    static func refillCheckMoment(refillStatusDate: Date?, depletionDate: Date?, calendar: Calendar) -> Date? {
        let late = refillStatusDate.flatMap {
            calendar.date(byAdding: .day, value: refillGraceDays, to: calendar.startOfDay(for: $0))
        }
        let short = depletionDate.flatMap {
            calendar.date(byAdding: .day, value: -refillPauseMinimumDays, to: calendar.startOfDay(for: $0))
        }
        guard let day = [late, short].compactMap({ $0 }).min() else { return nil }
        return calendar.date(bySettingHour: alertHour, minute: 0, second: 0, of: day)
    }

    /// The words a screen puts first when attention is needed: a count, out,
    /// or when. A count needed comes first because its date is today and its
    /// days are zero, which would otherwise read as "Act soon · around today"
    /// over medication that may still be in the bottle.
    static func line(for forecast: SupplyForecast) -> String {
        if forecast.needsCount { return "Count needed" }
        guard forecast.currentSupply > 0 else { return "No confirmed supply remains" }
        guard let date = forecast.depletionDate else { return forecast.explanation }
        return "Act soon · around \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// Why a count is needed, short enough to sit under "Count needed"; nil
    /// when none is. The forecast's own explanation is the long form.
    static func countNeededReason(for forecast: SupplyForecast) -> String? {
        forecast.needsCount ? assumedDosesReason(for: forecast) : nil
    }

    /// The doses the run-out date assumes were taken, short enough to sit
    /// beside the ledger's number; nil when it assumes none. Without it, "30
    /// on record" beside a date four days out reads as a contradiction.
    static func assumedDosesReason(for forecast: SupplyForecast) -> String? {
        guard forecast.assumedDoses > 0 else { return nil }
        let since = forecast.assumedSinceRefill ? "since the last refill" : "since the last count"
        return forecast.assumedDoses == 1
            ? "1 dose \(since) wasn't logged"
            : "\(forecast.assumedDoses) doses \(since) weren't logged"
    }

    /// What the ledger's number is called beside it. Once the forecast assumes
    /// any unlogged dose was taken, nobody knows the ledger's number is what is
    /// on hand, only that it is what was recorded; the run-out date beside it
    /// has already taken those doses out.
    static func quantityWords(for forecast: SupplyForecast) -> String {
        forecast.needsCount || forecast.assumedDoses > 0 ? "on record" : "on hand"
    }
}
