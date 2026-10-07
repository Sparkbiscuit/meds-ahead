import SwiftUI

/// Today's quick count: the one medication the weekly count check asks
/// about, chosen exactly as the reminder chooses it, so tapping the reminder
/// lands on a card that names the same medication.
struct QuickCountPrompt: Equatable {
    let medicationID: UUID
    let displayName: String
    /// The forecast the card was worked out from, which Count Now opens with.
    let forecast: SupplyForecast
    let title: String
    let message: String

    var needsCount: Bool { forecast.needsCount }

    /// How long Not Now hides the card for the medication it asked about.
    static let setAsideDays = 3
    /// When Not Now was last tapped, by medication.
    static let setAsideKey = "quickCountSetAside"
    /// The count-check reminder last tapped.
    static let tapKey = "quickCountTapped"

    /// A count-check reminder someone tapped: the medication it named, and
    /// when.
    struct Tap: Equatable, Codable {
        let medicationID: UUID
        let date: Date
    }

    /// Said under the question while the missed-doses card above lists this
    /// medication. A dose is taken off the supply when it is logged, so one
    /// from before a count, logged after it, comes off a number that already
    /// left it out.
    static let catchUpNote = "Log or skip its missed doses above first, so they don't come off the new count."

    init(medication: Medication, forecast: SupplyForecast) {
        medicationID = medication.id
        displayName = medication.displayName
        self.forecast = forecast
        if let reason = SupplyAttention.countNeededReason(for: forecast) {
            title = "Count needed: \(medication.displayName)"
            message = "\(reason), so only a count can say what's left."
        } else {
            title = "Quick count: \(medication.displayName)"
            message = "How many \(medication.form.unitText(for: 2)) are left? A few seconds of counting keeps the run-out date honest."
        }
    }

    /// The count check's question, from the same candidates and the same
    /// forecasts the notification planner weighs.
    ///
    /// A tapped reminder's medication comes first while it still waits for
    /// a count: the policy's pick can change between planning and the tap,
    /// and whoever tapped is looking for the one the reminder named.
    /// Otherwise it is the policy's target, once a week: a count that
    /// answered the check rests the card for a week, as the reminder rests,
    /// rather than asking about each medication due in turn. A count needed
    /// is not rested, since no low-supply alert can be planned without it.
    /// Not Now hides the card rather than moving on to the next medication,
    /// which would not be hiding anything.
    static func make(
        medications: [Medication],
        schedules: [DoseSchedule],
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent],
        setAside: [UUID: Date],
        tapped: Tap?,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> QuickCountPrompt? {
        let forecasts = medications.map { medication in
            (medication, ForecastEngine.forecast(
                medication: medication,
                schedules: schedules,
                inventoryEvents: inventoryEvents,
                doseEvents: doseEvents,
                now: now,
                calendar: calendar
            ))
        }
        let candidates = forecasts.map { medication, forecast in
            CountCheckPolicy.candidate(
                for: medication,
                schedules: schedules,
                inventoryEvents: inventoryEvents,
                forecast: forecast,
                now: now,
                calendar: calendar
            )
        }
        let named = tapped.flatMap { tap in
            candidates.first {
                $0.medicationID == tap.medicationID
                    && CountCheckPolicy.isDue($0, now: now, calendar: calendar)
                    && tap.date > ($0.lastCountDate ?? .distantPast)
            }
        }
        guard let target = named ?? CountCheckPolicy.target(from: candidates, now: now, calendar: calendar),
              let asked = forecasts.first(where: { $0.0.id == target.medicationID }) else { return nil }
        if named == nil, !target.needsCount,
           let answered = lastAnswer(candidates: candidates, inventoryEvents: inventoryEvents, calendar: calendar),
           SupplyAttention.days(from: answered, to: now, calendar: calendar) < CountCheckPolicy.intervalDays {
            return nil
        }
        guard !isSetAside(target.medicationID, in: setAside, tapped: tapped, now: now, calendar: calendar) else { return nil }
        return QuickCountPrompt(medication: asked.0, forecast: asked.1)
    }

    /// The last count that answered the weekly check: one of a medication
    /// the check can ask about, made once its previous count was due, from
    /// whichever screen it was made on.
    static func lastAnswer(
        candidates: [CountCheckPolicy.Candidate],
        inventoryEvents: [InventoryEvent],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        let counts = Dictionary(grouping: inventoryEvents.filter { $0.reason == .openingCount || $0.reason == .correction }, by: \.medicationID)
        return candidates.filter(\.isEligible).flatMap { candidate -> [Date] in
            let dates = (counts[candidate.medicationID] ?? []).map(\.date).sorted()
            return zip(dates, dates.dropFirst()).compactMap { previous, count in
                let before = CountCheckPolicy.Candidate(
                    medicationID: candidate.medicationID,
                    displayName: candidate.displayName,
                    isEligible: true,
                    daysRemaining: nil,
                    needsCount: false,
                    lastCountDate: previous
                )
                return CountCheckPolicy.isDue(before, now: count, calendar: calendar) ? count : nil
            }
        }
        .max()
    }

    /// Not Now holds for three days, unless the reminder naming this
    /// medication is tapped after it: whoever taps it is looking for the
    /// card. A reminder that only came, or never could, does not undo it.
    static func isSetAside(_ medicationID: UUID, in setAside: [UUID: Date], tapped: Tap?, now: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard let at = setAside[medicationID],
              let until = calendar.date(byAdding: .day, value: setAsideDays, to: at) else { return false }
        if let tapped, tapped.medicationID == medicationID, tapped.date > at { return false }
        return now < until
    }

    /// The missed-doses note for this card, when those doses are listed.
    static func catchUpNote(for medicationID: UUID, missedDoseMedicationIDs: [UUID]) -> String? {
        missedDoseMedicationIDs.contains(medicationID) ? catchUpNote : nil
    }

    static func rememberTap(of medicationID: UUID, at date: Date, in defaults: UserDefaults) {
        if let data = try? PropertyListEncoder().encode(Tap(medicationID: medicationID, date: date)) {
            defaults.set(data, forKey: tapKey)
        }
    }

    static func decodeTap(_ data: Data) -> Tap? {
        try? PropertyListDecoder().decode(Tap.self, from: data)
    }

    /// Not Now for one medication, with the set-asides that have run their
    /// three days dropped, so the stored list does not grow with every
    /// medication ever asked about.
    static func settingAside(_ medicationID: UUID, at now: Date, in setAside: [UUID: Date], calendar: Calendar = .autoupdatingCurrent) -> [UUID: Date] {
        var kept = setAside.filter { _, at in
            calendar.date(byAdding: .day, value: setAsideDays, to: at).map { now < $0 } ?? false
        }
        kept[medicationID] = now
        return kept
    }

    static func decodeSetAside(_ data: Data) -> [UUID: Date] {
        guard let stored = try? PropertyListDecoder().decode([String: Date].self, from: data) else { return [:] }
        return Dictionary(stored.compactMap { key, date in UUID(uuidString: key).map { ($0, date) } }, uniquingKeysWith: { Swift.max($0, $1) })
    }

    static func encodeSetAside(_ setAside: [UUID: Date]) -> Data {
        let stored = Dictionary(uniqueKeysWithValues: setAside.map { ($0.key.uuidString, $0.value) })
        return (try? PropertyListEncoder().encode(stored)) ?? Data()
    }
}

struct QuickCountCard: View {
    let prompt: QuickCountPrompt
    /// `QuickCountPrompt.catchUpNote`, while the missed-doses card lists
    /// this medication.
    var catchUpNote: String? = nil
    let onCount: () -> Void
    let onNotNow: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At the largest sizes the symbol sits above the words rather than
        // beside them, so the message keeps the card's width.
        let headerLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        VStack(alignment: .leading, spacing: 14) {
            headerLayout {
                Image(systemName: prompt.needsCount ? "exclamationmark.circle.fill" : "number.circle.fill")
                    .font(.title3)
                    .foregroundStyle(prompt.needsCount ? AnyShapeStyle(.orange) : AnyShapeStyle(AppTheme.accent))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(prompt.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(prompt.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let catchUpNote {
                        Text(catchUpNote)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 3)
                            .accessibilityIdentifier("quick-count-catch-up")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            let buttonLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))
            buttonLayout {
                Button(action: onNotNow) {
                    Text("Not Now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("Not now, \(prompt.displayName) count")
                .accessibilityHint("Hides this for three days")
                .accessibilityIdentifier("quick-count-not-now")

                Button(action: onCount) {
                    Label("Count Now", systemImage: "number")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(AppTheme.onAccent)
                .controlSize(.large)
                .accessibilityLabel("Count \(prompt.displayName) now")
                .accessibilityIdentifier("quick-count-now")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .contain)
    }
}
