import SwiftData
import SwiftUI

struct MedicationDetailView: View {
    @Bindable var medication: Medication
    @Query private var allSchedules: [DoseSchedule]
    @Query private var allDoseEvents: [DoseEvent]
    @Query private var allInventoryEvents: [InventoryEvent]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditor = false
    @State private var showingRefill = false
    @State private var showingCountCorrection = false
    @State private var showingDeleteConfirmation = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""

    private var schedules: [DoseSchedule] {
        allSchedules.filter { $0.medicationID == medication.id }.sorted { $0.minutesAfterMidnight < $1.minutesAfterMidnight }
    }

    private var doseEvents: [DoseEvent] {
        allDoseEvents.filter { $0.medicationID == medication.id }.sorted { $0.recordedAt > $1.recordedAt }
    }

    private var inventoryEvents: [InventoryEvent] {
        allInventoryEvents.filter { $0.medicationID == medication.id }.sorted { $0.date > $1.date }
    }

    private var forecast: SupplyForecast {
        ForecastEngine.forecast(
            medication: medication,
            schedules: allSchedules,
            inventoryEvents: allInventoryEvents,
            doseEvents: allDoseEvents
        )
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            ScrollView {
                VStack(spacing: 18) {
                    identityHeader
                    forecastCard
                    quickActions
                    scheduleCard
                    detailsCard
                    historyCard
                    safetyNote
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 104)
            }
        }
        .navigationTitle(medication.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit Medication", systemImage: "pencil") { showingEditor = true }
                    Button(medication.isArchived ? "Restore Medication" : "Archive Medication", systemImage: "archivebox") {
                        let willArchive = !medication.isArchived
                        medication.isArchived = willArchive
                        medication.updatedAt = .now
                        if saveChanges() {
                            refreshNotifications()
                            if willArchive { dismiss() }
                        }
                    }
                    Divider()
                    Button("Delete Medication", systemImage: "trash", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Medication actions")
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack { MedicationEditorView(medication: medication) }
        }
        .sheet(isPresented: $showingRefill) {
            SupplyChangeSheet(
                title: "Add a Refill",
                message: "Add the quantity you actually received.",
                unit: medication.form.unitName,
                initialValue: 30,
                actionTitle: "Add Refill"
            ) { quantity, note in
                let event = InventoryEvent(medicationID: medication.id, delta: quantity, reason: .refill, note: note)
                modelContext.insert(event)
                if let remaining = medication.refillsRemaining, remaining > 0 {
                    medication.refillsRemaining = remaining - 1
                }
                medication.updatedAt = .now
                if saveChanges() {
                    refreshNotifications(inventoryEvents: allInventoryEvents.filter { $0.id != event.id } + [event])
                }
            }
        }
        .sheet(isPresented: $showingCountCorrection) {
            SupplyChangeSheet(
                title: "Correct Current Count",
                message: "Count everything on hand, including doses already placed in pill organizers.",
                unit: medication.form.unitName,
                initialValue: forecast.currentSupply,
                actionTitle: "Save Count"
            ) { actualCount, note in
                let difference = ForecastEngine.correctionDelta(
                    medicationID: medication.id,
                    actualCount: actualCount,
                    inventoryEvents: allInventoryEvents,
                    doseEvents: allDoseEvents
                )
                guard abs(difference) > 0.000_001 else { return }
                let event = InventoryEvent(medicationID: medication.id, delta: difference, reason: .correction, note: note)
                modelContext.insert(event)
                medication.updatedAt = .now
                if saveChanges() {
                    refreshNotifications(inventoryEvents: allInventoryEvents.filter { $0.id != event.id } + [event])
                }
            }
        }
        .confirmationDialog(
            "Delete \(medication.displayName)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Medication and History", role: .destructive) { deleteMedication() }
        } message: {
            Text("This permanently removes its schedule, inventory ledger, and dose history from this iPhone.")
        }
        .alert("Couldn't Save", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    private var identityHeader: some View {
        HStack(spacing: 16) {
            MedicationGlyph(medication: medication, size: 68)
            VStack(alignment: .leading, spacing: 5) {
                Text(medication.displayName)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                if !medication.subtitle.isEmpty {
                    Text(medication.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(medication.form.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.color(for: medication))
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var forecastCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SUPPLY RUNWAY")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(forecastTitle)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .contentTransition(.numericText())
                }
                Spacer()
                SupplyGauge(daysRemaining: forecast.daysRemaining, leadDays: medication.refillLeadDays, size: 62)
            }
            Text(forecast.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                ConfidenceBadge(confidence: forecast.confidence)
                Spacer()
                Text("\(forecast.currentSupply.medicationQuantityText) on hand")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(19)
        .cardSurface()
    }

    private var forecastTitle: String {
        if forecast.currentSupply <= 0 { return "Out of supply" }
        if let days = forecast.daysRemaining {
            return days == 1 ? "About 1 day left" : "About \(days) days left"
        }
        return "Timing unknown"
    }

    private var quickActions: some View {
        HStack(spacing: 11) {
            Button {
                recordNow()
            } label: {
                Label("Take Now", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Menu {
                Button("Add Refill", systemImage: "plus.circle") { showingRefill = true }
                Button("Correct Count", systemImage: "number") { showingCountCorrection = true }
            } label: {
                Label("Supply", systemImage: "shippingbox")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Schedule", systemImage: "calendar")
                .font(.headline)
            if medication.isAsNeeded {
                Text("Taken as needed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if schedules.isEmpty {
                Text("No schedule configured")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(schedules) { schedule in
                    HStack {
                        Text(timeText(minutes: schedule.minutesAfterMidnight))
                            .font(.body.weight(.semibold))
                        Spacer()
                        Text("\(schedule.doseQuantity.medicationQuantityText) \(medication.form.unitName)\(schedule.doseQuantity == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                    }
                    if schedule.id != schedules.last?.id { Divider() }
                }
            }
            if !medication.directions.isEmpty {
                Text(medication.directions)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .cardSurface()
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Details", systemImage: "list.bullet.rectangle")
                .font(.headline)
            DetailLine(label: "Refills", value: medication.refillsRemaining.map(String.init) ?? "Not entered")
            DetailLine(label: "Low-supply alert", value: "\(medication.refillLeadDays) days before")
            if let expirationDate = medication.expirationDate {
                DetailLine(label: "Package expiration", value: expirationDate.formatted(date: .abbreviated, time: .omitted))
            }
            if !medication.lotNumber.isEmpty {
                DetailLine(label: "Lot", value: medication.lotNumber)
            }
            if !medication.productIdentifier.isEmpty {
                DetailLine(label: medication.productIdentifierType.isEmpty ? "Product code" : medication.productIdentifierType, value: medication.productIdentifier)
            }
        }
        .padding(18)
        .cardSurface()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Recent Activity", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
            }
            if doseEvents.isEmpty && inventoryEvents.isEmpty {
                Text("Dose logs and supply changes will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activity.prefix(8)) { item in
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: item.symbol)
                            .foregroundStyle(item.color)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if item.source == .dose {
                            Menu {
                                Button("Delete Dose Log", systemImage: "trash", role: .destructive) {
                                    deleteDoseActivity(item)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, height: 32)
                            }
                            .accessibilityLabel("Actions for \(item.title)")
                        }
                    }
                    if item.id != activity.prefix(8).last?.id { Divider() }
                }
            }
        }
        .padding(18)
        .cardSurface()
    }

    private var safetyNote: some View {
        Label("Follow the current label and your clinician’s instructions. Supply forecasts do not determine refill eligibility.", systemImage: "checkmark.shield")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var activity: [ActivityItem] {
        let doses = doseEvents.map { event in
            ActivityItem(
                id: event.id,
                date: event.recordedAt,
                title: event.status == .taken ? "Took \(event.doseQuantity.medicationQuantityText)" : "Skipped dose",
                symbol: event.status == .taken ? "checkmark.circle.fill" : "forward.end.circle.fill",
                color: event.status == .taken ? AppTheme.accent : .secondary,
                source: .dose
            )
        }
        let inventory = inventoryEvents.map { event in
            ActivityItem(
                id: event.id,
                date: event.date,
                title: "\(event.reason.displayName): \(event.delta >= 0 ? "+" : "")\(event.delta.medicationQuantityText)",
                symbol: event.delta >= 0 ? "plus.circle.fill" : "minus.circle.fill",
                color: event.delta >= 0 ? AppTheme.accent : .orange,
                source: .inventory
            )
        }
        return (doses + inventory).sorted { $0.date > $1.date }
    }

    private func recordNow() {
        let quantity = schedules.first?.doseQuantity ?? 1
        let event = DoseEvent(medicationID: medication.id, doseQuantity: quantity, status: .taken)
        modelContext.insert(event)
        medication.updatedAt = .now
        if saveChanges() {
            refreshNotifications(doseEvents: allDoseEvents.filter { $0.id != event.id } + [event])
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func deleteMedication() {
        let medicationID = medication.id
        allSchedules.filter { $0.medicationID == medicationID }.forEach(modelContext.delete)
        allDoseEvents.filter { $0.medicationID == medicationID }.forEach(modelContext.delete)
        allInventoryEvents.filter { $0.medicationID == medicationID }.forEach(modelContext.delete)
        modelContext.delete(medication)
        if saveChanges() {
            Task { await NotificationService.shared.removeNotifications(for: medicationID) }
            dismiss()
        }
    }

    private func deleteDoseActivity(_ item: ActivityItem) {
        guard item.source == .dose,
              let event = allDoseEvents.first(where: { $0.id == item.id }) else { return }
        modelContext.delete(event)
        medication.updatedAt = .now
        if saveChanges() {
            refreshNotifications(doseEvents: allDoseEvents.filter { $0.id != event.id })
        }
    }

    @discardableResult
    private func saveChanges() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            saveErrorMessage = "Your change wasn't saved. Try again."
            showingSaveError = true
            return false
        }
    }

    private func refreshNotifications(
        inventoryEvents: [InventoryEvent]? = nil,
        doseEvents: [DoseEvent]? = nil
    ) {
        let plan = NotificationPlanBuilder.make(
            medication: medication,
            schedules: allSchedules,
            inventoryEvents: inventoryEvents ?? allInventoryEvents,
            doseEvents: doseEvents ?? allDoseEvents
        )
        Task { await NotificationService.shared.replaceNotifications(for: plan) }
    }

    private func timeText(minutes: Int) -> String {
        let date = Calendar.autoupdatingCurrent.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct DetailLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 18)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }
}

private struct ActivityItem: Identifiable {
    enum Source: Equatable { case dose, inventory }
    let id: UUID
    let date: Date
    let title: String
    let symbol: String
    let color: Color
    let source: Source
}

private struct SupplyChangeSheet: View {
    let title: String
    let message: String
    let unit: String
    let actionTitle: String
    let onSave: (Double, String) -> Void
    @State private var quantity: Double
    @State private var note = ""
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        quantity.isFinite && quantity >= 0 && (actionTitle != "Add Refill" || quantity > 0)
    }

    init(
        title: String,
        message: String,
        unit: String,
        initialValue: Double,
        actionTitle: String,
        onSave: @escaping (Double, String) -> Void
    ) {
        self.title = title
        self.message = message
        self.unit = unit
        self.actionTitle = actionTitle
        self.onSave = onSave
        _quantity = State(initialValue: initialValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Quantity", value: $quantity, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.semibold))
                        Text(unit + (quantity == 1 ? "" : "s"))
                            .foregroundStyle(.secondary)
                    }
                    TextField("Optional note", text: $note, axis: .vertical)
                } footer: {
                    Text(message)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle) {
                        onSave(quantity, note.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
