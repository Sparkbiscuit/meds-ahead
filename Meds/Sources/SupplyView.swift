import SwiftData
import SwiftUI

struct SupplyView: View {
    @Query(sort: \Medication.createdAt) private var medications: [Medication]
    @Query private var schedules: [DoseSchedule]
    @Query private var inventoryEvents: [InventoryEvent]
    @Query private var doseEvents: [DoseEvent]
    let onAdd: () -> Void

    private var active: [Medication] { medications.filter { !$0.isArchived } }

    private var ranked: [(Medication, SupplyForecast)] {
        active.map { medication in
            (
                medication,
                ForecastEngine.forecast(
                    medication: medication,
                    schedules: schedules,
                    inventoryEvents: inventoryEvents,
                    doseEvents: doseEvents
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

    private var attentionCount: Int {
        ranked.filter { item in
            guard let days = item.1.daysRemaining else { return false }
            return days <= item.0.refillLeadDays
        }.count
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    header
                    if ranked.isEmpty {
                        EmptyStateCard(
                            symbol: "chart.bar.doc.horizontal",
                            title: "Your supply runway will appear here",
                            message: "Add a medication with a current count and schedule to see what needs attention next.",
                            actionTitle: "Add Medication",
                            action: onAdd
                        )
                    } else {
                        ForEach(ranked, id: \.0.id) { medication, forecast in
                            NavigationLink {
                                MedicationDetailView(medication: medication)
                            } label: {
                                SupplyRow(medication: medication, forecast: forecast)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 104)
            }
        }
        .navigationTitle("Supply")
    }

    private var header: some View {
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

    private var isLow: Bool {
        forecast.daysRemaining.map { $0 <= medication.refillLeadDays } ?? false
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
        if let date = forecast.depletionDate {
            return isLow ? "Act soon · around \(date.formatted(.dateTime.month(.abbreviated).day()))" : "Runs out around \(date.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return forecast.explanation
    }
}
