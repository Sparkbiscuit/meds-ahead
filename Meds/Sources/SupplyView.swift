import SwiftData
import SwiftUI

struct SupplyView: View {
    @Query(sort: \Medication.createdAt) private var medications: [Medication]
    @Query private var schedules: [DoseSchedule]
    @Query private var inventoryEvents: [InventoryEvent]
    @Query private var doseEvents: [DoseEvent]
    @State private var showingTripCheck = false
    let onAdd: () -> Void

    private var active: [Medication] { medications.filter { !$0.isArchived } }

    private func ranked(now: Date) -> [(Medication, SupplyForecast)] {
        Self.ordered(active.map { medication in
            (
                medication,
                ForecastEngine.forecast(
                    medication: medication,
                    schedules: schedules,
                    inventoryEvents: inventoryEvents,
                    doseEvents: doseEvents,
                    now: now
                )
            )
        })
    }

    /// Soonest run-out first; then courses, the ones still running before
    /// the ones already over, by last day; then the ones nobody can
    /// forecast. A course has no run-out date, but it is not an unknown
    /// either: its last day says exactly how long it runs.
    static func ordered(_ forecasts: [(Medication, SupplyForecast)]) -> [(Medication, SupplyForecast)] {
        func rank(_ forecast: SupplyForecast) -> Int {
            if forecast.daysRemaining != nil { return 0 }
            if forecast.courseCovered { return 1 }
            if forecast.courseFinished { return 2 }
            return 3
        }
        return forecasts.sorted { lhs, rhs in
            let (left, right) = (rank(lhs.1), rank(rhs.1))
            if left != right { return left < right }
            if let a = lhs.1.daysRemaining, let b = rhs.1.daysRemaining, a != b { return a < b }
            if let a = lhs.1.courseEndDate, let b = rhs.1.courseEndDate, a != b { return a < b }
            return lhs.0.displayName < rhs.0.displayName
        }
    }

    private func attentionCount(in forecasts: [(Medication, SupplyForecast)], now: Date) -> Int {
        forecasts.filter { SupplyAttention(medication: $0.0, forecast: $0.1, now: now).needsAttention }.count
    }

    /// Ranked forecasts grouped under the person each medication is for, when
    /// the household names more than one; one group, no headers, otherwise.
    private func groups(in forecasts: [(Medication, SupplyForecast)]) -> [(person: String, items: [(Medication, SupplyForecast)])] {
        let names = Set(forecasts.map { $0.0.personName.trimmingCharacters(in: .whitespaces) })
        guard names.count > 1 else { return [("", forecasts)] }
        let ordered = names.sorted { lhs, rhs in
            if lhs.isEmpty { return false }
            if rhs.isEmpty { return true }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        return ordered.map { person in
            (person, forecasts.filter { $0.0.personName.trimmingCharacters(in: .whitespaces) == person })
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let forecasts = ranked(now: now)
        return ZStack {
            CanvasBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    header(attentionCount: attentionCount(in: forecasts, now: now))
                    if forecasts.isEmpty {
                        EmptyStateCard(
                            symbol: "chart.bar.doc.horizontal",
                            title: "Your supply runway will appear here",
                            message: "Add a medication with a current count and schedule to see what needs attention next.",
                            actionTitle: "Add Medication",
                            action: onAdd
                        )
                    } else {
                        ForEach(groups(in: forecasts), id: \.person) { person, items in
                            if !person.isEmpty || groups(in: forecasts).count > 1 {
                                Text(person.isEmpty ? "Not assigned to anyone" : "For \(person)")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            ForEach(items, id: \.0.id) { medication, forecast in
                                NavigationLink {
                                    MedicationDetailView(medication: medication)
                                } label: {
                                    SupplyRow(medication: medication, forecast: forecast, now: now)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 104)
            }
        }
        .navigationTitle("Supply")
        .toolbar {
            if !forecasts.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingTripCheck = true
                    } label: {
                        Label("Trip Check", systemImage: "suitcase")
                    }
                    .accessibilityHint("See which medications need a refill before you travel")
                }
            }
        }
        .sheet(isPresented: $showingTripCheck) {
            TripCheckSheet(forecasts: forecasts.map { (medication: $0.0, forecast: $0.1) })
        }
    }

    private func header(attentionCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(attentionCount == 0 ? "Everything looks steady" : "\(attentionCount) need\(attentionCount == 1 ? "s" : "") attention")
                .font(.system(.title, design: .rounded, weight: .bold))
            Text("Forecasts update as you log doses, add refills, or correct a count.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }
}

private struct SupplyRow: View {
    let medication: Medication
    let forecast: SupplyForecast
    let now: Date
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var attention: SupplyAttention {
        SupplyAttention(medication: medication, forecast: forecast, now: now)
    }

    /// Low, and no refill in progress that can still answer for it.
    private var isLow: Bool { attention.needsAttention }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        gauge
                        nameLine
                        Spacer(minLength: 0)
                    }
                    supplyCopy
                }
            } else {
                HStack(spacing: 14) {
                    gauge
                    VStack(alignment: .leading, spacing: 5) {
                        nameLine
                        supplyCopy
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(17)
        .cardSurface()
        .contentShape(Rectangle())
    }

    /// A count needed is the summary's own first words. The row reads as one
    /// VoiceOver element, and the ring and the name's icon each said it too:
    /// "Count needed" three times before the reason. They stay silent then.
    private var gauge: some View {
        // A course's ring says what the summary beside it already says.
        SupplyGauge(daysRemaining: forecast.daysRemaining, leadDays: attention.leadDays, needsCount: forecast.needsCount,
                    course: SupplyGauge.Course(forecast), size: 54)
            .accessibilityHidden(forecast.needsCount || SupplyGauge.Course(forecast) != nil)
    }

    private var nameLine: some View {
        HStack(spacing: 7) {
            Text(medication.displayName)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            if isLow {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Low supply")
                    .accessibilityHidden(forecast.needsCount)
            }
        }
    }

    private var supplyCopy: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(isLow ? .orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let reason = SupplyAttention.assumedDosesReason(for: forecast) {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // A late refill is still worth naming, but under the warning, not
            // in place of it.
            if isLow, let status = RefillStatusText.line(for: medication, now: now) {
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(SupplyRowText.caption(for: forecast, form: medication.form))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summary: String {
        SupplyRowText.summary(for: forecast, isLow: isLow, refillStatus: RefillStatusText.line(for: medication, now: now))
    }
}

/// What a Supply row says, over plain values.
enum SupplyRowText {
    /// The row's first line. A course that runs out before its last day
    /// keeps the attention words; one the supply sees through, or one
    /// already over, says so rather than the explanation's longer sentence,
    /// and neither is a refill to chase.
    static func summary(
        for forecast: SupplyForecast,
        isLow: Bool,
        refillStatus: String?,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        if isLow { return SupplyAttention.line(for: forecast) }
        if forecast.courseFinished, let end = forecast.courseEndDate {
            return "Course finished \(ForecastEngine.dayText(end, calendar: calendar))"
        }
        if forecast.courseCovered, let end = forecast.courseEndDate {
            return "Enough to finish the course on \(ForecastEngine.dayText(end, calendar: calendar))"
        }
        if let refillStatus { return refillStatus }
        if let date = forecast.depletionDate {
            return "Runs out around \(date.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return forecast.explanation
    }

    /// The small line under it: what is on hand, and for a course the
    /// supply sees through, what its last dose leaves.
    static func caption(for forecast: SupplyForecast, form: MedicationForm) -> String {
        let onHand = "\(form.quantityText(forecast.currentSupply)) \(SupplyAttention.quantityWords(for: forecast))"
        guard forecast.courseCovered, let leftover = forecast.leftoverAtCourseEnd else { return onHand }
        return "\(onHand) · \(form.quantityText(max(0, leftover))) left after the last dose"
    }
}

extension TripCheck {
    /// How a "Can't say" row is marked. A count needed is something to do
    /// before leaving and wears the attention mark every other screen gives
    /// it; only a medication with no forecast at all is a plain unknown.
    static func uncertainMark(for forecast: SupplyForecast) -> (symbol: String, tint: Color) {
        forecast.needsCount
            ? ("exclamationmark.circle.fill", .orange)
            : ("questionmark.circle", .secondary)
    }
}

/// Pick the day you are back; see what runs out before then.
private struct TripCheckSheet: View {
    let forecasts: [(medication: Medication, forecast: SupplyForecast)]
    @State private var returnDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 7, to: .now) ?? .now
    @Environment(\.dismiss) private var dismiss

    private var check: TripCheck {
        TripCheck.make(returnDate: returnDate, forecasts: forecasts)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Back on", selection: $returnDate, in: Date.now..., displayedComponents: .date)
                } footer: {
                    Text("Counted from the confirmed supply and current schedules. A medication that runs out on the day you return still needs a refill before you go.")
                }
                let result = check
                Section("Refill before you go") {
                    if result.needsRefill.isEmpty {
                        Label("Nothing runs out before you're back", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                    ForEach(result.needsRefill, id: \.medicationID) { item in
                        row(item, detail: item.forecast.depletionDate.map { "Runs out around \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "", symbol: "exclamationmark.circle.fill", tint: .orange)
                    }
                }
                if !result.uncertain.isEmpty {
                    Section {
                        ForEach(result.uncertain, id: \.medicationID) { item in
                            let mark = TripCheck.uncertainMark(for: item.forecast)
                            row(item, detail: SupplyAttention.countNeededReason(for: item.forecast).map { "Count needed · \($0)" } ?? item.forecast.explanation, symbol: mark.symbol, tint: mark.tint)
                        }
                    } header: {
                        Text("Can't say")
                    } footer: {
                        Text("No forecast yet: as-needed medications need three logged doses, and a scheduled one needs a count and a schedule.")
                    }
                }
                if !result.fine.isEmpty {
                    Section("Fine through your return") {
                        ForEach(result.fine, id: \.medicationID) { item in
                            row(item, detail: item.forecast.depletionDate.map { "Runs out around \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "", symbol: "checkmark.circle", tint: AppTheme.accent)
                        }
                    }
                }
            }
            .navigationTitle("Trip Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(_ item: TripCheck.Item, detail: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.body.weight(.semibold))
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
