import SwiftData
import SwiftUI

/// "Why this date?": the forecast's arithmetic as a short ledger someone can
/// check against the bottle, and a count when the bottle disagrees.
struct WhyThisDateView: View {
    let medication: Medication
    @Query private var schedules: [DoseSchedule]
    @Query private var inventoryEvents: [InventoryEvent]
    @Query private var doseEvents: [DoseEvent]
    @State private var countRequest: CountCorrection.Request?
    @State private var showingSaveError = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // Minute by minute, as the screens it is opened from are: a dose
            // passing its due window moves the date, and this must explain
            // the date they now show.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                content(now: context.date)
            }
            .navigationTitle("Why This Date?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .sheet(item: $countRequest) { request in
            CorrectCountSheet(request: request) { showingSaveError = true }
        }
        .alert("Couldn't Save", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your count wasn't saved. Try again.")
        }
    }

    private func content(now: Date) -> some View {
        let breakdown = ForecastEngine.breakdown(
            medication: medication,
            schedules: schedules,
            inventoryEvents: inventoryEvents,
            doseEvents: doseEvents,
            now: now
        )
        // The permission Today's banner reports, so an alert that cannot be
        // delivered is not shown here as one that will be.
        let notifications = NotificationHealth.shared.state
        let lines = WhyThisDateLedger.lines(
            for: breakdown,
            isAsNeeded: medication.isAsNeeded,
            isArchived: medication.isArchived,
            notificationsAllowed: notifications != .blocked && notifications != .unasked,
            courseRanOutFirst: FinishedCourseNotice.ranOutFirst(
                medication: medication,
                forecast: breakdown.forecast,
                schedules: schedules,
                inventoryEvents: inventoryEvents,
                doseEvents: doseEvents,
                now: now
            )
        )
        let ledger = lines.filter { [.start, .change, .total].contains($0.kind) }
        let outlook = lines.filter { ![.start, .change, .total].contains($0.kind) }
        return List {
            Section {
                ForEach(Array(ledger.enumerated()), id: \.offset) { _, line in
                    LedgerLine(line: line)
                }
            } header: {
                Text(medication.displayName)
            }
            Section("Forecast") {
                ForEach(Array(outlook.enumerated()), id: \.offset) { _, line in
                    LedgerLine(line: line)
                }
            }
            Section {
                Button {
                    countRequest = CountCorrection.Request(medication: medication, forecast: breakdown.forecast)
                } label: {
                    Label("Count Now", systemImage: "number")
                }
                .accessibilityIdentifier("why-count-now")
            } footer: {
                Text("A count replaces the numbers above with what is really in the bottle.")
            }
        }
    }
}

private struct LedgerLine: View {
    let line: WhyThisDateLedger.Line
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Beside the words at the largest sizes, the symbol took a column the
        // reason then wrapped a word a line inside; above them, it takes none.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
        layout {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(line.isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(AppTheme.accent))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(line.text)
                    .font(font)
                    .foregroundStyle(line.isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = line.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One sentence per line: the signs and the "=" read as a column by
        // eye are read as words.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.spoken)
        .accessibilityIdentifier("why-line")
    }

    private var font: Font {
        switch line.kind {
        case .total, .conclusion: .body.weight(.semibold)
        default: .body
        }
    }

    private var symbol: String? {
        switch line.kind {
        case .conclusion: line.isWarning ? "exclamationmark.circle.fill" : "calendar"
        case .alert: line.isWarning ? "bell.slash" : "bell"
        default: nil
        }
    }
}

/// The forecast card's way in: its own sheet, so the screen it sits on keeps
/// no state for it.
struct WhyThisDateButton: View {
    let medication: Medication
    @State private var showing = false

    var body: some View {
        Button("Why this date?", systemImage: "questionmark.circle") { showing = true }
            .font(.subheadline.weight(.semibold))
            .accessibilityIdentifier("why-this-date")
            .sheet(isPresented: $showing) { WhyThisDateView(medication: medication) }
    }
}
