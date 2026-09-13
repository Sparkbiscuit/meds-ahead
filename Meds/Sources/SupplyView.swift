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
        active.map { medication in
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
        }
        .sorted { lhs, rhs in
            switch (lhs.1.daysRemaining, rhs.1.daysRemaining) {
            case let (.some(a), .some(b)): a < b
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): lhs.0.displayName < rhs.0.displayName
            }
        }
    }

    private func attentionCount(in forecasts: [(Medication, SupplyForecast)]) -> Int {
        forecasts.filter { item in
            guard let days = item.1.daysRemaining, item.0.refillStatus == .none else { return false }
            return days <= item.0.refillLeadDays
        }.count
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
                    header(attentionCount: attentionCount(in: forecasts))
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
                                    SupplyRow(medication: medication, forecast: forecast)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Low, and nothing done about it yet: a refill under way turns the alarm off.
    private var isLow: Bool {
        guard medication.refillStatus == .none else { return false }
        return forecast.daysRemaining.map { $0 <= medication.refillLeadDays } ?? false
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        SupplyGauge(daysRemaining: forecast.daysRemaining, leadDays: medication.refillLeadDays, size: 54)
                        nameLine
                        Spacer(minLength: 0)
                    }
                    supplyCopy
                }
            } else {
                HStack(spacing: 14) {
                    SupplyGauge(daysRemaining: forecast.daysRemaining, leadDays: medication.refillLeadDays, size: 54)
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
            }
        }
    }

    private var supplyCopy: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(isLow ? .orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(forecast.currentSupply.medicationQuantityText) \(medication.form.unitName)\(forecast.currentSupply == 1 ? "" : "s") on hand")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summary: String {
        if let status = RefillStatusText.line(for: medication) { return status }
        if let date = forecast.depletionDate {
            return isLow ? "Act soon · around \(date.formatted(.dateTime.month(.abbreviated).day()))" : "Runs out around \(date.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return forecast.explanation
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
                            row(item, detail: item.forecast.explanation, symbol: "questionmark.circle", tint: .secondary)
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
