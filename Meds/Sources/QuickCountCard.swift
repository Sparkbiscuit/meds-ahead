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

    /// The count check's target, from the same candidates and the same
    /// forecasts the notification planner weighs, unless Not Now set it
    /// aside. Only the target: a card that moved on to the next medication
    /// the moment one was set aside would not be hiding anything.
    static func make(
        medications: [Medication],
        schedules: [DoseSchedule],
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent],
        setAside: [UUID: Date],
        lastAsked: Date?,
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
        guard let target = CountCheckPolicy.target(from: candidates, now: now, calendar: calendar),
              let asked = forecasts.first(where: { $0.0.id == target.medicationID }),
              !isSetAside(target.medicationID, in: setAside, lastAsked: lastAsked, now: now, calendar: calendar) else { return nil }
        return QuickCountPrompt(medication: asked.0, forecast: asked.1)
    }

    /// Not Now holds for three days, unless the weekly reminder asks about a
    /// count after it: whoever taps that reminder is looking for this card.
    static func isSetAside(_ medicationID: UUID, in setAside: [UUID: Date], lastAsked: Date?, now: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard let at = setAside[medicationID],
              let until = calendar.date(byAdding: .day, value: setAsideDays, to: at) else { return false }
        if let lastAsked, lastAsked > at { return false }
        return now < until
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
