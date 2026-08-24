import SwiftData
import SwiftUI

private struct EditableDoseSchedule: Identifiable {
    let id = UUID()
    var time: Date
    var doseQuantity: Double
    var weekdayMask: Int
}

struct MedicationEditorView: View {
    private let medication: Medication?
    private let draftEvidence: [ScanEvidence]
    private let onSaved: (() -> Void)?

    @Query private var allSchedules: [DoseSchedule]
    @Query private var allInventoryEvents: [InventoryEvent]
    @Query private var allDoseEvents: [DoseEvent]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var nickname: String
    @State private var strength: String
    @State private var form: MedicationForm
    @State private var directions: String
    @State private var currentSupplyText: String
    @State private var refillsText: String
    @State private var refillLeadDays: Int
    @State private var expirationDate: Date
    @State private var hasExpirationDate: Bool
    @State private var lotNumber: String
    @State private var productIdentifier: String
    @State private var productIdentifierType: String
    @State private var isAsNeeded: Bool
    @State private var remindersEnabled: Bool
    @State private var refillRemindersEnabled: Bool
    @State private var detailedNotifications: Bool
    @State private var editableSchedules: [EditableDoseSchedule]
    @State private var didLoadExistingSchedules = false
    @State private var showingValidation = false
    @State private var validationMessage = ""
    @State private var showingDiscardConfirmation = false

    init(medication: Medication? = nil, draft: MedicationDraft = MedicationDraft(), onSaved: (() -> Void)? = nil) {
        self.medication = medication
        self.draftEvidence = draft.evidence
        self.onSaved = onSaved
        let resolvedForm = medication?.form ?? draft.form
        _name = State(initialValue: medication?.name ?? draft.name)
        _nickname = State(initialValue: medication?.nickname ?? draft.nickname)
        _strength = State(initialValue: medication?.strength ?? draft.strength)
        _form = State(initialValue: resolvedForm)
        _directions = State(initialValue: medication?.directions ?? draft.directions)
        _currentSupplyText = State(initialValue: draft.currentSupply?.medicationQuantityText ?? "")
        _refillsText = State(initialValue: (medication?.refillsRemaining ?? draft.refillsRemaining).map(String.init) ?? "")
        _refillLeadDays = State(initialValue: medication?.refillLeadDays ?? 7)
        let expiration = medication?.expirationDate ?? draft.expirationDate
        _expirationDate = State(initialValue: expiration ?? .now)
        _hasExpirationDate = State(initialValue: expiration != nil)
        _lotNumber = State(initialValue: medication?.lotNumber ?? draft.lotNumber)
        _productIdentifier = State(initialValue: medication?.productIdentifier ?? draft.productIdentifier)
        _productIdentifierType = State(initialValue: medication?.productIdentifierType ?? draft.productIdentifierType)
        _isAsNeeded = State(initialValue: medication?.isAsNeeded ?? false)
        _remindersEnabled = State(initialValue: medication?.remindersEnabled ?? true)
        _refillRemindersEnabled = State(initialValue: medication?.refillRemindersEnabled ?? true)
        _detailedNotifications = State(initialValue: medication?.detailedNotifications ?? false)
        _editableSchedules = State(
            initialValue: [
                EditableDoseSchedule(
                    time: Self.date(minutes: 8 * 60),
                    doseQuantity: 1,
                    weekdayMask: 0b1111111
                )
            ]
        )
    }

    private var isEditing: Bool { medication != nil }
    private var saveValidationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter the medication name."
        }
        if !isEditing {
            guard let currentSupply = Double(currentSupplyText), currentSupply.isFinite, currentSupply >= 0 else {
                return "Enter a current amount of zero or more. Include doses already placed in pill organizers."
            }
        }
        if !refillsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           (Int(refillsText) == nil || (Int(refillsText) ?? -1) < 0) {
            return "Refills remaining must be a whole number of zero or more, or left blank."
        }
        if !isAsNeeded {
            if editableSchedules.isEmpty { return "Add at least one schedule time, or mark this medication as taken as needed." }
            if editableSchedules.contains(where: { !$0.doseQuantity.isFinite || $0.doseQuantity <= 0 }) {
                return "Every amount per dose must be greater than zero."
            }
            if editableSchedules.contains(where: { $0.weekdayMask == 0 }) {
                return "Choose at least one day for every schedule."
            }
            let minutes = editableSchedules.map { schedule in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: schedule.time)
                return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
            if Set(minutes).count != minutes.count { return "Each schedule time must be different." }
        }
        return nil
    }

    var body: some View {
        Form {
            if !draftEvidence.isEmpty {
                scanSummarySection
            }

            Section("Medication") {
                TextField("Medication name", text: $name)
                    .textInputAutocapitalization(.words)
                    .padding(.vertical, 3)
                    .accessibilityIdentifier("medication-name")
                TextField("Strength", text: $strength)
                    .textInputAutocapitalization(.never)
                    .padding(.vertical, 3)
                    .accessibilityHint("For example, 20 milligrams")
                Picker("Form", selection: $form) {
                    ForEach(MedicationForm.allCases) { form in
                        Text(form.displayName).tag(form)
                    }
                }
                TextField("Nickname", text: $nickname)
                    .padding(.vertical, 3)
                    .accessibilityHint("Optional")
                TextField("Label directions", text: $directions, axis: .vertical)
                    .lineLimit(2...5)
                    .padding(.vertical, 3)
                    .accessibilityHint("Optional; copy the current label directions")
            }

            if !isEditing {
                Section {
                    HStack {
                        TextField("Current amount", text: $currentSupplyText)
                            .keyboardType(.decimalPad)
                            .padding(.vertical, 3)
                            .accessibilityIdentifier("current-supply")
                        Text(form.unitName + (Double(currentSupplyText) == 1 ? "" : "s"))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("What you have now")
                } footer: {
                    Text("Include doses already placed in pill organizers. You can correct this count at any time.")
                }
            }

            Section {
                Toggle("Taken as needed", isOn: $isAsNeeded.animation(.medsSpring))
                if !isAsNeeded {
                    ForEach($editableSchedules) { $schedule in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                DatePicker("Time", selection: $schedule.time, displayedComponents: .hourAndMinute)
                                if editableSchedules.count > 1 {
                                    Button(role: .destructive) {
                                        editableSchedules.removeAll { $0.id == schedule.id }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove \(schedule.time.formatted(date: .omitted, time: .shortened)) schedule")
                                }
                            }
                            ScheduleDoseQuantityField(
                                quantity: $schedule.doseQuantity,
                                unitName: form.unitName
                            )
                            WeekdayPicker(mask: $schedule.weekdayMask)
                        }
                        .padding(.vertical, 4)

                        if schedule.id != editableSchedules.last?.id {
                            Divider()
                        }
                    }
                    Button("Add Another Schedule", systemImage: "plus.circle") {
                        let prior = editableSchedules.last ?? EditableDoseSchedule(
                            time: Self.date(minutes: 8 * 60),
                            doseQuantity: 1,
                            weekdayMask: 0b1111111
                        )
                        editableSchedules.append(
                            EditableDoseSchedule(
                                time: Calendar.current.date(byAdding: .hour, value: 6, to: prior.time) ?? prior.time,
                                doseQuantity: prior.doseQuantity,
                                weekdayMask: prior.weekdayMask
                            )
                        )
                    }
                }
            } header: {
                Text("Schedule")
            } footer: {
                Text(isAsNeeded ? "As-needed forecasts require at least three recent logged doses." : "This schedule drives reminders and the supply forecast. Confirm it against the current label or clinician instructions.")
            }

            Section("Reminders") {
                Toggle("Dose reminders", isOn: $remindersEnabled)
                    .disabled(isAsNeeded)
                Toggle("Refill reminders", isOn: $refillRemindersEnabled)
                Toggle("Show medication name", isOn: $detailedNotifications)
                    .disabled((!remindersEnabled || isAsNeeded) && !refillRemindersEnabled)
                Stepper("Low supply: \(refillLeadDays) days before", value: $refillLeadDays, in: 1...30)
                    .disabled(!refillRemindersEnabled)
            }

            Section("Prescription & package") {
                TextField("Refills remaining (optional)", text: $refillsText)
                    .keyboardType(.numberPad)
                    .padding(.vertical, 3)
                Toggle("Package expiration", isOn: $hasExpirationDate.animation(.medsSpring))
                if hasExpirationDate {
                    DatePicker("Expires", selection: $expirationDate, displayedComponents: .date)
                }
                TextField("Lot number (optional)", text: $lotNumber)
                    .padding(.vertical, 3)
                if !productIdentifier.isEmpty {
                    LabeledContent(productIdentifierType.isEmpty ? "Product code" : productIdentifierType) {
                        Text(productIdentifier)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section {
                Label("Meds Ahead organizes information you confirm. It does not recommend doses or determine whether a prescription can be refilled.", systemImage: "checkmark.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(isEditing ? "Edit Medication" : (draftEvidence.isEmpty ? "Add Medication" : "Review Medication"))
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(hasUnsavedRequiredData)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if !isEditing && hasUnsavedRequiredData {
                        showingDiscardConfirmation = true
                    } else {
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "Save" : "Add") {
                    if let message = saveValidationMessage {
                        validationMessage = message
                        showingValidation = true
                    } else {
                        save()
                    }
                }
                .accessibilityIdentifier("save-medication")
            }
        }
        .alert("A little more information is needed", isPresented: $showingValidation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage)
        }
        .confirmationDialog(
            "Discard this medication?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { dismiss() }
        } message: {
            Text("The information you reviewed or entered will not be saved.")
        }
        .task { loadExistingSchedulesIfNeeded() }
    }

    private var scanSummarySection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.viewfinder")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review before saving")
                        .font(.headline)
                    Text("\(draftEvidence.filter { $0.kind == .text }.count) text fields · \(draftEvidence.filter { $0.kind == .barcode }.count) codes found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            DisclosureGroup("Scan evidence") {
                ForEach(draftEvidence) { evidence in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(evidence.kind == .barcode ? (evidence.symbology ?? "Barcode") : "Label text")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(redactedEvidence(evidence))
                            .font(.caption)
                            .textSelection(.enabled)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 3)
                }
            }
        } footer: {
            Text("Codes can identify a product, prescription, or web link. Meds Ahead never assumes they contain a complete regimen.")
        }
    }

    private var hasUnsavedRequiredData: Bool {
        !name.isEmpty || !strength.isEmpty || !currentSupplyText.isEmpty
    }

    private func redactedEvidence(_ evidence: ScanEvidence) -> String {
        if evidence.kind == .barcode, evidence.value.lowercased().hasPrefix("http") {
            return "Web link detected — not opened"
        }
        return evidence.value
    }

    private func loadExistingSchedulesIfNeeded() {
        guard let medication, !didLoadExistingSchedules else { return }
        let existing = allSchedules.filter { $0.medicationID == medication.id }.sorted { $0.minutesAfterMidnight < $1.minutesAfterMidnight }
        if !existing.isEmpty {
            editableSchedules = existing.map {
                EditableDoseSchedule(
                    time: Self.date(minutes: $0.minutesAfterMidnight),
                    doseQuantity: $0.doseQuantity,
                    weekdayMask: $0.weekdayMask
                )
            }
        }
        didLoadExistingSchedules = true
    }

    private func save() {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let target: Medication
        var inventoryForNotifications = allInventoryEvents
        if let medication {
            target = medication
            target.name = cleanedName
            target.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            target.strength = strength.trimmingCharacters(in: .whitespacesAndNewlines)
            target.form = form
            target.directions = directions.trimmingCharacters(in: .whitespacesAndNewlines)
            target.updatedAt = .now
        } else {
            let newMedication = Medication(
                name: cleanedName,
                nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
                strength: strength.trimmingCharacters(in: .whitespacesAndNewlines),
                form: form,
                directions: directions.trimmingCharacters(in: .whitespacesAndNewlines),
                source: draftEvidence.isEmpty ? .manual : .scanned,
                sourceConfidence: draftEvidence.isEmpty ? 1 : draftEvidence.map(\.confidence).reduce(0, +) / Double(max(1, draftEvidence.count)),
                accentIndex: abs(cleanedName.hashValue) % AppTheme.medicationColors.count
            )
            modelContext.insert(newMedication)
            target = newMedication
            let opening = InventoryEvent(
                medicationID: target.id,
                delta: Double(currentSupplyText) ?? 0,
                reason: .openingCount
            )
            modelContext.insert(opening)
            inventoryForNotifications.removeAll { $0.id == opening.id }
            inventoryForNotifications.append(opening)
        }

        target.refillsRemaining = Int(refillsText)
        target.refillLeadDays = refillLeadDays
        target.expirationDate = hasExpirationDate ? expirationDate : nil
        target.lotNumber = lotNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        target.productIdentifier = productIdentifier
        target.productIdentifierType = productIdentifierType
        target.isAsNeeded = isAsNeeded
        target.remindersEnabled = remindersEnabled && !isAsNeeded
        target.refillRemindersEnabled = refillRemindersEnabled
        target.detailedNotifications = detailedNotifications

        let scheduleDefinitions: [ScheduleDefinition] = if isAsNeeded {
            []
        } else {
            editableSchedules.map { schedule in
                let components = Calendar.current.dateComponents([.hour, .minute], from: schedule.time)
                let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                return ScheduleDefinition(
                    minutesAfterMidnight: minutes,
                    doseQuantity: schedule.doseQuantity,
                    weekdayMask: schedule.weekdayMask
                )
            }
        }
        let newSchedules = ScheduleReconciler.reconcile(
            medicationID: target.id,
            definitions: scheduleDefinitions,
            existing: allSchedules.filter { $0.medicationID == target.id },
            in: modelContext
        )

        do {
            try modelContext.save()
            let notificationPlan = NotificationPlanBuilder.make(
                medication: target,
                schedules: newSchedules,
                inventoryEvents: inventoryForNotifications,
                doseEvents: allDoseEvents
            )
            let shouldRequestNotificationAuthorization = target.remindersEnabled || target.refillRemindersEnabled
            Task {
                await NotificationService.shared.replaceNotifications(
                    for: notificationPlan,
                    requestAuthorization: shouldRequestNotificationAuthorization
                )
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if let onSaved {
                onSaved()
            } else {
                dismiss()
            }
        } catch {
            modelContext.rollback()
            validationMessage = "Meds Ahead couldn't save this medication. Nothing was changed. Try again."
            showingValidation = true
        }
    }

    private static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }
}

private struct WeekdayPicker: View {
    @Binding var mask: Int
    private let symbols = Calendar.current.veryShortWeekdaySymbols
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Days")
                .font(.subheadline.weight(.semibold))
            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    weekdayButtons
                }
            } else {
                HStack(spacing: 7) {
                    weekdayButtons
                }
            }
        }
    }

    @ViewBuilder
    private var weekdayButtons: some View {
        ForEach(symbols.indices, id: \.self) { index in
            Button {
                if mask & (1 << index) == 0 {
                    mask |= 1 << index
                } else if mask.nonzeroBitCount > 1 {
                    mask &= ~(1 << index)
                }
            } label: {
                Text(symbols[index])
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(mask & (1 << index) != 0 ? AppTheme.accent : Color.secondary.opacity(0.12), in: Circle())
                    .foregroundStyle(mask & (1 << index) != 0 ? .white : .primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Calendar.current.weekdaySymbols[index])
            .accessibilityValue(mask & (1 << index) != 0 ? "Selected" : "Not selected")
        }
    }
}

private struct ScheduleDoseQuantityField: View {
    @Binding var quantity: Double
    let unitName: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let entry = HStack {
            TextField(
                "Dose",
                value: $quantity,
                format: .number.precision(.fractionLength(0...2))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 72)
            .padding(.vertical, 3)
            Text(unitName + (quantity == 1 ? "" : "s"))
                .foregroundStyle(.secondary)
        }

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text("Amount per dose")
                entry
            }
        } else {
            HStack {
                Text("Amount per dose")
                Spacer()
                entry
            }
        }
    }
}

struct AddMedicationFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = MedicationDraft()
    @State private var showingScanner = false
    @State private var showingEditor = false

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        VStack(spacing: 8) {
                            Image(systemName: "viewfinder")
                                .font(.system(size: 48, weight: .medium))
                                .foregroundStyle(AppTheme.accent)
                                .symbolEffect(.breathe, options: .repeat(2))
                            Text("Add a medication")
                                .font(.system(.title, design: .rounded, weight: .bold))
                            Text("Start with the label or enter the details yourself. Nothing is saved until you confirm it.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 18)

                        Button {
                            showingScanner = true
                        } label: {
                            AddOptionCard(
                                symbol: "camera.viewfinder",
                                title: "Scan a Label",
                                message: "Recognize text and every visible barcode on device.",
                                prominent: true
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("scan-label")

                        Button {
                            draft = MedicationDraft()
                            showingEditor = true
                        } label: {
                            AddOptionCard(
                                symbol: "square.and.pencil",
                                title: "Enter Manually",
                                message: "Best when the label is damaged or unavailable.",
                                prominent: false
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("manual-entry")
                    }
                    .padding(18)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .navigationDestination(isPresented: $showingScanner) {
                ScannerScreen { scannedDraft in
                    draft = scannedDraft
                    showingEditor = true
                }
            }
            .navigationDestination(isPresented: $showingEditor) {
                MedicationEditorView(draft: draft, onSaved: { dismiss() })
            }
        }
    }
}

private struct AddOptionCard: View {
    let symbol: String
    let title: String
    let message: String
    let prominent: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(AppTheme.accent.gradient) : AnyShapeStyle(Color.secondary.opacity(0.12)))
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(prominent ? .white : AppTheme.accent)
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .cardSurface()
        .contentShape(Rectangle())
    }
}
