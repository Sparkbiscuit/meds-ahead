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
    /// The editor changed what past days were scheduled to hold while doses
    /// were being assumed, so Correct Count opens once the editor has closed,
    /// and opens empty whatever the forecast now assumes.
    @State private var askingCountAfterEdit = false
    @State private var refillStatusToSet: RefillStatus?
    @State private var showingDeleteConfirmation = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showingAlreadyLogged = false

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
            content(forecast: forecast(now: context.date), now: context.date)
        }
    }

    private func content(forecast: SupplyForecast, now: Date) -> some View {
        let ranOutFirst = FinishedCourseNotice.ranOutFirst(
            medication: medication,
            forecast: forecast,
            schedules: allSchedules,
            inventoryEvents: allInventoryEvents,
            doseEvents: allDoseEvents,
            now: now
        )
        return ZStack {
            CanvasBackground()
            ScrollView {
                VStack(spacing: 18) {
                    identityHeader
                    forecastCard(forecast: forecast, ranOutFirst: ranOutFirst, now: now)
                    quickActions
                    pharmacyCard
                    scheduleCard(now: now, ranOutFirst: ranOutFirst)
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
        .sheet(isPresented: $showingEditor, onDismiss: {
            if askingCountAfterEdit { showingCountCorrection = true }
        }) {
            NavigationStack { MedicationEditorView(medication: medication, onAskForCount: { askingCountAfterEdit = true }) }
        }
        .sheet(isPresented: $showingRefill) {
            SupplyChangeSheet(
                title: "Add a Refill",
                message: "Add the quantity you actually received.",
                form: medication.form,
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
        .sheet(isPresented: $showingCountCorrection, onDismiss: { askingCountAfterEdit = false }) {
            SupplyChangeSheet(
                title: "Correct Current Count",
                message: askingCountAfterEdit
                    ? "The schedule changed while some doses since the last count weren't logged, so what is left can't be worked out. Count everything on hand, including doses already placed in pill organizers."
                    : "Count everything on hand, including doses already placed in pill organizers.",
                form: medication.form,
                initialValue: askingCountAfterEdit ? nil : SupplyChangeQuantity.countPrefill(for: forecast),
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
            RefillStatusSheet(status: status, initialDate: Self.refillStatusInitialDate(for: status, medication: medication)) { date in
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

    private func forecastCard(forecast: SupplyForecast, ranOutFirst: Bool, now: Date) -> some View {
        let attention = SupplyAttention(medication: medication, forecast: forecast, now: now)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SUPPLY RUNWAY")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(Self.forecastTitle(for: forecast, ranOutFirst: ranOutFirst))
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .contentTransition(.numericText())
                }
                Spacer()
                SupplyGauge(daysRemaining: forecast.daysRemaining, leadDays: attention.leadDays, needsCount: forecast.needsCount,
                            course: SupplyGauge.Course(forecast, ranOutFirst: ranOutFirst), size: 62)
            }
            Text(Self.forecastDetail(for: forecast, ranOutFirst: ranOutFirst))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // In the words Today and Supply use too, and in the accent only
            // while the refill still answers for the supply: run late, due
            // after the run-out, or waited on with too little left, it takes
            // the attention colour they give it.
            if let status = RefillStatusText.line(for: medication, now: now) {
                Label(status, systemImage: attention.needsAttention
                      ? "exclamationmark.circle.fill"
                      : medication.refillStatus == .ready ? "bag.fill" : "phone.arrow.up.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(attention.needsAttention ? .orange : AppTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                // A finished course forecasts nothing, so there is nothing to
                // be sure or unsure of.
                if !forecast.courseFinished {
                    ConfidenceBadge(confidence: forecast.confidence)
                }
                Spacer()
                Text("\(forecast.currentSupply.medicationQuantityText) \(SupplyAttention.quantityWords(for: forecast))")
                    .font(.subheadline.weight(.semibold))
            }
            WhyThisDateButton(medication: medication)
        }
        .padding(19)
        .cardSurface()
    }

    /// The date a refill status sheet opens on: the one stored for that same
    /// status, or today. The date decides how long the refill quiets the
    /// low-supply warning, so Ready for Pickup opened on the day the refill
    /// was requested started a pause that had already run out, and the app
    /// said the refill needed checking the moment it was marked ready.
    static func refillStatusInitialDate(for status: RefillStatus, medication: Medication, now: Date = .now) -> Date {
        medication.refillStatus == status ? (medication.refillStatusDate ?? now) : now
    }

    /// A count needed is never "Out of supply" and never zero days: the ledger
    /// still shows medication, and only a count can say whether it is there.
    /// A course is asked about first: one finished, or one the supply sees
    /// through, has no run-out to name, and an empty bottle at its end is
    /// how a course dispensed to the tablet finishes, not "Out of supply".
    static func forecastTitle(for forecast: SupplyForecast, ranOutFirst: Bool = false, calendar: Calendar = .autoupdatingCurrent) -> String {
        if forecast.courseFinished, let end = forecast.courseEndDate {
            return FinishedCourseNotice.endedText(day: ForecastEngine.dayText(end, calendar: calendar), ranOutFirst: ranOutFirst)
        }
        if forecast.courseCovered { return "Enough to finish the course" }
        if forecast.needsCount { return "Count needed" }
        if forecast.currentSupply <= 0 { return "Out of supply" }
        if let days = forecast.daysRemaining {
            return "About \(days.dayCountText) left"
        }
        return "Timing unknown"
    }

    /// The line under the title. A finished course's own explanation would
    /// only repeat the title; one that ran out first says so here, where the
    /// title has no room for it.
    static func forecastDetail(for forecast: SupplyForecast, ranOutFirst: Bool = false) -> String {
        guard forecast.courseFinished else { return forecast.explanation }
        guard ranOutFirst else { return "No doses are scheduled after its last day." }
        return "The supply on record ran out before its last day. No doses are scheduled after it."
    }

    /// The course line under the schedule's times: its last day while it
    /// runs, the day it finished once it has. Nil for a medication that is
    /// not on a course.
    static func courseLine(
        schedules: [DoseSchedule],
        medicationID: UUID,
        now: Date,
        ranOutFirst: Bool = false,
        calendar: Calendar = .autoupdatingCurrent
    ) -> (text: String, isFinished: Bool)? {
        guard let end = ScheduleEngine.courseEnd(schedules: schedules, medicationID: medicationID) else { return nil }
        if ScheduleEngine.isCourseFinished(schedules: schedules, medicationID: medicationID, now: now, calendar: calendar) {
            return (FinishedCourseNotice.endedText(day: ForecastEngine.dayText(end, calendar: calendar), ranOutFirst: ranOutFirst), true)
        }
        let day = end.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.wide).month(.abbreviated).day())
        return ("Until \(day)", false)
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

    private func scheduleCard(now: Date, ranOutFirst: Bool) -> some View {
        // A course taken up again keeps its ended schedules for the calendar;
        // they are not the times it is taken now.
        let schedules = ScheduleReconciler.currentSchedules(allSchedules, medicationID: medication.id, now: now)
            .sorted { $0.minutesAfterMidnight < $1.minutesAfterMidnight }
        let course = Self.courseLine(schedules: schedules, medicationID: medication.id, now: now, ranOutFirst: ranOutFirst)
        let finished = course?.isFinished == true
        return VStack(alignment: .leading, spacing: 13) {
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
                            .foregroundStyle(finished ? .secondary : .primary)
                        Spacer()
                        Text(medication.form.quantityText(schedule.doseQuantity))
                            .foregroundStyle(finished ? .tertiary : .secondary)
                    }
                    if schedule.id != schedules.last?.id { Divider() }
                }
                if let course {
                    // A tick only for a course its supply saw through.
                    Label(course.text, systemImage: finished ? (ranOutFirst ? "calendar" : "checkmark.circle") : "calendar.badge.clock")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(finished ? AnyShapeStyle(.secondary) : AnyShapeStyle(AppTheme.accent))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("schedule-course-line")
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
            DetailLine(
                label: "Low-supply alert",
                value: SupplyAttention.leadTimeText(refillLeadDays: medication.refillLeadDays, refillsRemaining: medication.refillsRemaining)
            )
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let label: String
    let value: String
    var isWarning = false

    var body: some View {
        // Side by side at the largest sizes, a long value such as the low-supply
        // alert's reason squeezed into a column a word wide and broke words
        // mid-word; stacked, as Today's refill rows are, it keeps the card's width.
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        layout {
            Text(label).foregroundStyle(.secondary)
            if !stacked { Spacer(minLength: 18) }
            Text(value)
                .foregroundStyle(isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                .multilineTextAlignment(stacked ? .leading : .trailing)
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
