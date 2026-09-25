import SwiftData
import SwiftUI

struct MedicationDetailView: View {
    @Bindable var medication: Medication
    @Query private var allMedications: [Medication]
    @Query private var allSchedules: [DoseSchedule]
    @Query private var allDoseEvents: [DoseEvent]
    @Query private var allInventoryEvents: [InventoryEvent]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showingEditor = false
    @State private var showingRefill = false
    @State private var showingCountCorrection = false
    @State private var refillStatusToSet: RefillStatus?
    @State private var showingDeleteConfirmation = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showingAlreadyLogged = false

    private var schedules: [DoseSchedule] {
        allSchedules.filter { $0.medicationID == medication.id }.sorted { $0.minutesAfterMidnight < $1.minutesAfterMidnight }
    }

    private var doseEvents: [DoseEvent] {
        allDoseEvents.filter { $0.medicationID == medication.id }.sorted { $0.recordedAt > $1.recordedAt }
    }

    private var inventoryEvents: [InventoryEvent] {
        allInventoryEvents.filter { $0.medicationID == medication.id }.sorted { $0.date > $1.date }
    }

    /// The last refill is the best guess for the next one; the opening count is
    /// the fallback for a first refill. 30 covers a brand-new history.
    private var suggestedRefillQuantity: Double {
        if let lastRefill = inventoryEvents.first(where: { $0.reason == .refill && $0.delta > 0 }) {
            return lastRefill.delta
        }
        if let opening = inventoryEvents.last(where: { $0.reason == .openingCount && $0.delta > 0 }) {
            return opening.delta
        }
        return 30
    }

    private func forecast(now: Date) -> SupplyForecast {
        ForecastEngine.forecast(
            medication: medication,
            schedules: allSchedules,
            inventoryEvents: allInventoryEvents,
            doseEvents: allDoseEvents,
            now: now
        )
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(forecast: forecast(now: context.date))
        }
    }

    private func content(forecast: SupplyForecast) -> some View {
        return ZStack {
            CanvasBackground()
            ScrollView {
                VStack(spacing: 18) {
                    identityHeader
                    forecastCard(forecast: forecast)
                    quickActions
                    pharmacyCard
                    scheduleCard
                    AdherenceCalendarCard(medication: medication, schedules: allSchedules, doseEvents: allDoseEvents)
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
                            // Nothing could be logged while it was archived, and the
                            // forecast would assume every dose of that stretch was
                            // taken, so a restore asks what is on hand now.
                            if willArchive { dismiss() } else { showingCountCorrection = true }
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
                initialValue: suggestedRefillQuantity,
                actionTitle: "Add Refill"
            ) { quantity, note in
                let event = InventoryEvent(medicationID: medication.id, delta: quantity, reason: .refill, note: note)
                modelContext.insert(event)
                if let remaining = medication.refillsRemaining, remaining > 0 {
                    medication.refillsRemaining = remaining - 1
                }
                // The refill has arrived; whatever was in progress is done.
                medication.refillStatus = .none
                medication.refillStatusDate = nil
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
                // A count that matches the ledger is still recorded: the forecast
                // assumes unlogged doses were taken only until the last count, and
                // a count with no event behind it could never end "Count needed".
                let event = InventoryEvent(medicationID: medication.id, delta: abs(difference) > 0.000_001 ? difference : 0, reason: .correction, note: note)
                modelContext.insert(event)
                medication.updatedAt = .now
                if saveChanges() {
                    refreshNotifications(inventoryEvents: allInventoryEvents.filter { $0.id != event.id } + [event])
                }
            }
        }
        .sheet(item: $refillStatusToSet) { status in
            RefillStatusSheet(status: status, initialDate: medication.refillStatusDate ?? .now) { date in
                medication.refillStatus = status
                medication.refillStatusDate = date
                medication.updatedAt = .now
                if saveChanges() { refreshNotifications() }
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
        .alert("Already Logged", isPresented: $showingAlreadyLogged) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The widget or a reminder has already logged this dose. Nothing more was recorded.")
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

    private func forecastCard(forecast: SupplyForecast) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SUPPLY RUNWAY")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(forecastTitle(forecast: forecast))
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
            if let status = refillStatusText {
                Label(status, systemImage: medication.refillStatus == .ready ? "bag.fill" : "phone.arrow.up.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    /// Where the refill stands, in the words Today and Supply use too.
    private var refillStatusText: String? {
        RefillStatusText.line(for: medication)
    }

    private func forecastTitle(forecast: SupplyForecast) -> String {
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
            .foregroundStyle(AppTheme.onAccent)
            .controlSize(.large)

            Menu {
                Button("Add Refill", systemImage: "plus.circle") { showingRefill = true }
                Button("Correct Count", systemImage: "number") { showingCountCorrection = true }
                Divider()
                Button("Refill Requested…", systemImage: "phone.arrow.up.right") { refillStatusToSet = .requested }
                Button("Ready for Pickup…", systemImage: "bag") { refillStatusToSet = .ready }
                if medication.refillStatus != .none {
                    Button("Clear Refill Status", systemImage: "xmark.circle") {
                        medication.refillStatus = .none
                        medication.refillStatusDate = nil
                        medication.updatedAt = .now
                        if saveChanges() { refreshNotifications() }
                    }
                }
            } label: {
                Label("Supply", systemImage: "shippingbox")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("supply-actions")
        }
    }

    /// The call a low-supply warning leads to, with the number the pharmacy asks
    /// for large enough to read aloud.
    @ViewBuilder
    private var pharmacyCard: some View {
        if !medication.pharmacyName.isEmpty || !medication.pharmacyPhone.isEmpty || !medication.rxNumber.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                Label("Pharmacy", systemImage: "cross.case.fill")
                    .font(.headline)
                if !medication.pharmacyName.isEmpty {
                    Text(medication.pharmacyName)
                        .font(.subheadline.weight(.semibold))
                }
                if !medication.rxNumber.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rx number")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(medication.rxNumber)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let url = pharmacyCallURL {
                    Button {
                        openURL(url)
                    } label: {
                        Label(medication.pharmacyName.isEmpty ? "Call \(medication.pharmacyPhone)" : "Call \(medication.pharmacyName)", systemImage: "phone.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityHint(medication.pharmacyPhone)
                } else if !medication.pharmacyPhone.isEmpty {
                    Text(medication.pharmacyPhone)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .cardSurface()
        }
    }

    private var pharmacyCallURL: URL? {
        let digits = medication.pharmacyPhone.filter { $0.isNumber || $0 == "+" }
        guard digits.filter(\.isNumber).count >= 7 else { return nil }
        return URL(string: "tel:\(digits)")
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
                let calendar = Calendar.autoupdatingCurrent
                let isExpired = calendar.startOfDay(for: expirationDate) < calendar.startOfDay(for: .now)
                DetailLine(
                    label: "Package expiration",
                    value: expirationDate.formatted(date: .abbreviated, time: .omitted) + (isExpired ? " · Expired" : ""),
                    isWarning: isExpired
                )
            }
            if !medication.lotNumber.isEmpty {
                DetailLine(label: "Lot", value: medication.lotNumber)
            }
            if !medication.productIdentifier.isEmpty {
                DetailLine(label: medication.productIdentifierType.isEmpty ? "Product code" : medication.productIdentifierType, value: medication.productIdentifier)
            }
            if !medication.rxNormCode.isEmpty, medication.productIdentifier != medication.rxNormCode {
                DetailLine(label: "RxNorm", value: medication.rxNormCode)
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
                let recent = Array(activity.prefix(8))
                ForEach(recent) { item in
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
                                if item.isHealthMirrored {
                                    // A copy of Health's sample deleted here came back on
                                    // the next sync as a new, supply-charging dose. Health
                                    // owns it; an undo there is mirrored here.
                                    Text("Logged in Apple Health. Undo it there and it will be removed here.")
                                } else {
                                    Button("Delete Dose Log", systemImage: "trash", role: .destructive) {
                                        deleteDoseActivity(item)
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, height: 32)
                            }
                            .accessibilityLabel("Actions for \(item.title)")
                        }
                    }
                    if item.id != recent.last?.id { Divider() }
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
                title: (event.status == .taken ? "Took \(event.doseQuantity.medicationQuantityText)" : "Skipped dose")
                    + (event.note.isEmpty ? "" : " · \(event.note)"),
                symbol: event.status == .taken ? "checkmark.circle.fill" : "forward.end.circle.fill",
                color: event.status == .taken ? AppTheme.accent : .secondary,
                source: .dose,
                isHealthMirrored: event.healthSampleID != nil
            )
        }
        let inventory = inventoryEvents.map { event in
            ActivityItem(
                id: event.id,
                date: event.date,
                title: event.reason == .correction && event.delta == 0
                    ? "Count confirmed"
                    : "\(event.reason.displayName): \(event.delta >= 0 ? "+" : "")\(event.delta.medicationQuantityText)",
                symbol: event.delta >= 0 ? "plus.circle.fill" : "minus.circle.fill",
                color: event.delta >= 0 ? AppTheme.accent : .orange,
                source: .inventory,
                isHealthMirrored: false
            )
        }
        return (doses + inventory).sorted { $0.date > $1.date }
    }

    /// Take Now claims the dose Today is already offering, when there is one, so the
    /// same dose cannot be logged once here and once there — an unattached log stayed
    /// invisible to Today's cards, which left the dose showing as due and invited a
    /// second tap that spent the supply twice. With no dose to claim this records an
    /// unscheduled one, at the amount belonging to the nearest time of day.
    private func recordNow() {
        let now = Date.now
        var claimed = ScheduleEngine.actionableDose(
            schedules: allSchedules,
            medicationID: medication.id,
            doseEvents: allDoseEvents,
            now: now
        )
        if claimed != nil {
            // The widget may have logged the dose these arrays offer where they
            // cannot see it yet, so the store chooses the dose: the next one
            // still due, as a screen that had caught up would offer. When the
            // store has every due dose logged, a tap made while this screen still
            // shows one as due is that same dose, not an extra one: nothing more
            // is written, and the alert says why.
            do {
                claimed = try DoseLogGuard.actionableDose(
                    schedules: allSchedules,
                    medicationID: medication.id,
                    in: modelContext,
                    now: now
                )
            } catch {
                saveErrorMessage = "Your change wasn't saved. Try again."
                showingSaveError = true
                return
            }
            guard claimed != nil else {
                showingAlreadyLogged = true
                return
            }
        }
        let quantity = claimed?.quantity
            ?? ScheduleEngine.nearestScheduledQuantity(
                schedules: allSchedules,
                medicationID: medication.id,
                now: now
            )
            ?? 1
        let event = DoseEvent(
            medicationID: medication.id,
            scheduleID: claimed?.scheduleID,
            scheduledAt: claimed?.date,
            doseQuantity: quantity,
            status: .taken
        )
        modelContext.insert(event)
        medication.updatedAt = .now
        if saveChanges() {
            refreshNotifications(doseEvents: allDoseEvents.filter { $0.id != event.id } + [event])
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func deleteMedication() {
        let medicationID = medication.id
        let remainingMedications = allMedications.filter { $0.id != medicationID }
        let remainingSchedules = allSchedules.filter { $0.medicationID != medicationID }
        let remainingDoseEvents = allDoseEvents.filter { $0.medicationID != medicationID }
        let remainingInventoryEvents = allInventoryEvents.filter { $0.medicationID != medicationID }
        allSchedules.filter { $0.medicationID == medicationID }.forEach(modelContext.delete)
        allDoseEvents.filter { $0.medicationID == medicationID }.forEach(modelContext.delete)
        allInventoryEvents.filter { $0.medicationID == medicationID }.forEach(modelContext.delete)
        modelContext.delete(medication)
        if saveChanges() {
            let plans = NotificationPlanBuilder.makeAll(
                medications: remainingMedications,
                schedules: remainingSchedules,
                inventoryEvents: remainingInventoryEvents,
                doseEvents: remainingDoseEvents
            )
            Task { await NotificationService.shared.replaceAllNotifications(for: plans) }
            dismiss()
        }
    }

    private func deleteDoseActivity(_ item: ActivityItem) {
        guard item.source == .dose, !item.isHealthMirrored,
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
        let plans = NotificationPlanBuilder.makeAll(
            medications: allMedications,
            schedules: allSchedules,
            inventoryEvents: inventoryEvents ?? allInventoryEvents,
            doseEvents: doseEvents ?? allDoseEvents
        )
        Task { await NotificationService.shared.replaceAllNotifications(for: plans) }
    }

    private func timeText(minutes: Int) -> String {
        let date = Calendar.autoupdatingCurrent.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct RefillStatusSheet: View {
    let status: RefillStatus
    let initialDate: Date
    let onSave: (Date) -> Void
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss

    init(status: RefillStatus, initialDate: Date, onSave: @escaping (Date) -> Void) {
        self.status = status
        self.initialDate = initialDate
        self.onSave = onSave
        _date = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(status == .ready ? "Ready on" : "Expected", selection: $date, displayedComponents: .date)
                } footer: {
                    Text(status == .ready
                         ? "Today says to pick it up. The low-supply reminder pauses until the refill is added, and comes back if it waits two days or supply gets very low."
                         : "The low-supply reminder pauses while the refill is on its way, and comes back if it runs two days late or supply gets very low. Add the refill when it arrives.")
                }
            }
            .navigationTitle(status.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(date)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct DetailLine: View {
    let label: String
    let value: String
    var isWarning = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 18)
            Text(value)
                .foregroundStyle(isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
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
    /// Health's copy, which Health takes back, not this app.
    let isHealthMirrored: Bool
}

/// The number a supply sheet records for the text in its field, or nil when the
/// sheet's button must stay disabled. A count may be zero, since an empty bottle
/// is a real count; a refill must be more than nothing.
enum SupplyChangeQuantity {
    /// The text a sheet opens with, never grouped. A region that groups with "."
    /// shows 1497.5 as "1.497,5"; deleting only the fraction would leave "1.497",
    /// which the shared parser reads as 1.497, not 1497.
    static func text(for value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        if value.rounded() == value { return value.medicationQuantityText }
        return value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)).locale(locale))
    }

    static func value(
        from text: String,
        prefilled: Double,
        requiresMoreThanZero: Bool,
        locale: Locale = .autoupdatingCurrent
    ) -> Double? {
        let value: Double
        if text == Self.text(for: prefilled, locale: locale) {
            // The prefilled text is rounded to two places. Left untouched it stands
            // for the exact number it was made from, so saving an unchanged count
            // records no correction.
            value = prefilled
        } else {
            // A second decimal separator is a slipped key, not a number: the
            // lenient parse reads "2..8" as 2 and "1.5.5" as 1.5, and the sheet
            // closes on the tap without showing the number it read.
            let separators = text.filter { $0 == "." || String($0) == locale.decimalSeparator }.count
            // Neither the prefill nor the decimal pad writes a grouping separator,
            // so one here was pasted or typed on a keyboard, and it is ambiguous:
            // "1.497" is 1497 to a German reader and 1.497 to the parser.
            let grouped = locale.groupingSeparator.map { !$0.isEmpty && text.contains($0) } ?? false
            guard separators <= 1, !grouped,
                  let parsed = Double.medicationQuantity(from: text, locale: locale) else { return nil }
            value = parsed
        }
        guard value.isFinite, value >= 0, !(requiresMoreThanZero && value <= 0) else { return nil }
        return value
    }
}

private struct SupplyChangeSheet: View {
    let title: String
    let message: String
    let unit: String
    let initialValue: Double
    let actionTitle: String
    let onSave: (Double, String) -> Void
    @State private var text: String
    @State private var note = ""
    @Environment(\.dismiss) private var dismiss

    /// Read from the text on every change, as the editor's dose field is, never
    /// from a value a formatted field writes back: on a phone the editor's
    /// formatted field wrote back only when it lost focus, and here the decimal
    /// pad has no Return key and the toolbar button does not end editing, so the
    /// sheet could record the number it opened with instead of the one typed.
    private var quantity: Double? {
        SupplyChangeQuantity.value(from: text, prefilled: initialValue, requiresMoreThanZero: actionTitle == "Add Refill")
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
        self.initialValue = initialValue
        self.actionTitle = actionTitle
        self.onSave = onSave
        _text = State(initialValue: SupplyChangeQuantity.text(for: initialValue))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Quantity", text: $text)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.semibold))
                            .accessibilityIdentifier("supply-quantity")
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
                        guard let quantity else { return }
                        onSave(quantity, note.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(quantity == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
