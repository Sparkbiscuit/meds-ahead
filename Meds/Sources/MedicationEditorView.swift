import SwiftData
import SwiftUI

private struct EditableDoseSchedule: Identifiable {
    let id = UUID()
    var time: Date
    var doseQuantity: Double
    var weekdayMask: Int
}

struct MedicationEditorView: View {
    private enum NameField: Hashable {
        case medication
        case brand
    }

    private let medication: Medication?
    private let draftEvidence: [ScanEvidence]
    private let draftSource: MedicationSource
    private let draftIdentification: NDCIdentificationOutcome?
    private let draftImportedDoses: [ImportedDose]
    private let draftPharmacyName: String
    private let draftPharmacyPhone: String
    private let draftRxNumber: String
    private let draftCaptureNote: String
    private let onSaved: (() -> Void)?

    @Query private var allMedications: [Medication]
    @Query private var allSchedules: [DoseSchedule]
    @Query private var allInventoryEvents: [InventoryEvent]
    @Query private var allDoseEvents: [DoseEvent]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var nickname: String
    @State private var brandName: String
    @State private var isBrandNameVisible: Bool
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
    @State private var nameProvenance: MedicationNameProvenance
    @State private var ndcEntry: String
    @State private var rxNormCode: String
    @State private var isAsNeeded: Bool
    @State private var remindersEnabled: Bool
    @State private var refillRemindersEnabled: Bool
    @State private var detailedNotifications: Bool
    @State private var editableSchedules: [EditableDoseSchedule]
    @State private var importsDoseHistory = true
    @State private var didLoadExistingSchedules = false
    @State private var showingValidation = false
    @State private var validationMessage = ""
    @State private var showingDiscardConfirmation = false
    @FocusState private var focusedNameField: NameField?

    init(medication: Medication? = nil, draft: MedicationDraft = MedicationDraft(), onSaved: (() -> Void)? = nil) {
        self.medication = medication
        self.draftEvidence = draft.evidence
        self.draftSource = medication?.source ?? draft.source
        self.draftIdentification = draft.identification
        self.draftImportedDoses = draft.importedDoses
        self.draftPharmacyName = draft.pharmacyName
        self.draftPharmacyPhone = draft.pharmacyPhone
        self.draftRxNumber = draft.rxNumber
        self.draftCaptureNote = draft.captureNote
        self.onSaved = onSaved
        let resolvedForm = medication?.form ?? draft.form
        _name = State(initialValue: medication?.name ?? draft.name)
        _nickname = State(initialValue: medication?.nickname ?? draft.nickname)
        let resolvedBrandName = medication?.brandName ?? draft.brandName
        _brandName = State(initialValue: resolvedBrandName)
        _isBrandNameVisible = State(initialValue: !resolvedBrandName.isEmpty)
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
        _nameProvenance = State(initialValue: medication == nil ? draft.nameProvenance : .none)
        _rxNormCode = State(initialValue: medication?.rxNormCode ?? draft.rxNormCode)
        // A code that was read but filled nothing is offered back for checking,
        // digit by digit against the bottle, rather than left in the evidence list.
        _ndcEntry = State(initialValue: draft.identification?.codeToCheck ?? "")
        _isAsNeeded = State(initialValue: medication?.isAsNeeded ?? draft.isAsNeeded)
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
            guard let currentSupply = Double.medicationQuantity(from: currentSupplyText), currentSupply >= 0 else {
                return "Enter a current amount of zero or more. Include doses already placed in pill organizers."
            }
        }
        let refills = refillsText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !refills.isEmpty, (Int(refills).map { $0 < 0 } ?? true) {
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
            // Two schedules may share a clock time on different days — a Monday
            // dose and a Tuesday dose at 8:00 with different amounts is a promised
            // configuration. Only a same-day collision is a genuine duplicate.
            var masksByMinute: [Int: Int] = [:]
            for schedule in editableSchedules {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: schedule.time)
                let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                if masksByMinute[minutes, default: 0] & schedule.weekdayMask != 0 {
                    return "Two schedules overlap at the same time on the same day. Change one of the times or its days."
                }
                masksByMinute[minutes, default: 0] |= schedule.weekdayMask
            }
        }
        return nil
    }

    var body: some View {
        Form {
            if !draftEvidence.isEmpty {
                scanSummarySection
            } else if draftSource == .appleHealth, !isEditing {
                healthSummarySection
            }

            Section("Medication") {
                VStack(alignment: .leading, spacing: 4) {
                    MedicationFieldTitle("Medication name")
                    TextField("Medication name", text: $name)
                        .textInputAutocapitalization(.words)
                        .focused($focusedNameField, equals: .medication)
                        .accessibilityIdentifier("medication-name")
                        .onChange(of: name) { oldValue, newValue in
                            // Replace a brand this screen filled in, leave one the
                            // person typed. Renaming Sertraline to Tacrolimus used to
                            // keep Zoloft, and the shared list printed it.
                            let previousAutofill = MedicationBrandIndex.resolve(oldValue)?.brand ?? ""
                            guard brandName.isEmpty || brandName == previousAutofill else { return }
                            brandName = MedicationBrandIndex.brandName(forGeneric: newValue) ?? ""
                            // Reveal it filled in, and leave it revealed: taking the
                            // row away again mid-edit is worse than an empty one.
                            if !brandName.isEmpty, !isBrandNameVisible {
                                withAnimation(.medsSpring) { isBrandNameVisible = true }
                            }
                        }
                }
                .padding(.vertical, 3)
                // An empty Brand name row is a field to skip past on every
                // medication that has no brand worth printing, which is most of a
                // household's list once supplements and old generics are counted.
                // It earns its place only once it has an answer.
                if isBrandNameVisible {
                    VStack(alignment: .leading, spacing: 4) {
                        MedicationFieldTitle("Brand name")
                        TextField("Brand name", text: $brandName)
                            .textInputAutocapitalization(.words)
                            .focused($focusedNameField, equals: .brand)
                            .accessibilityHint("Optional; filled in automatically for medications Meds Ahead recognises")
                            .accessibilityIdentifier("medication-brand-name")
                    }
                    .padding(.vertical, 3)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Button {
                        withAnimation(.medsSpring) { isBrandNameVisible = true }
                    } label: {
                        Label("Add brand name", systemImage: "plus.circle")
                            .font(.subheadline)
                    }
                    .accessibilityIdentifier("add-brand-name")
                    .accessibilityHint("Medications Meds Ahead recognises fill this in for you")
                }
                VStack(alignment: .leading, spacing: 4) {
                    MedicationFieldTitle("Strength")
                    TextField("Strength", text: $strength)
                        .textInputAutocapitalization(.never)
                        .accessibilityHint("For example, 20 milligrams")
                }
                .padding(.vertical, 3)
                Picker("Form", selection: $form) {
                    ForEach(MedicationForm.allCases) { form in
                        Text(form.displayName).tag(form)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    MedicationFieldTitle("Nickname")
                    TextField("Nickname", text: $nickname)
                        .accessibilityHint("Optional")
                }
                .padding(.vertical, 3)
                VStack(alignment: .leading, spacing: 4) {
                    MedicationFieldTitle("Label directions")
                    TextField("Label directions", text: $directions, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityHint("Optional; copy the current label directions")
                }
                .padding(.vertical, 3)
            }

            if !isEditing {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            MedicationFieldTitle("Current amount")
                            TextField("Current amount", text: $currentSupplyText)
                                .keyboardType(.decimalPad)
                                .accessibilityIdentifier("current-supply")
                        }
                        .padding(.vertical, 3)
                        Text(form.unitName + (Double.medicationQuantity(from: currentSupplyText) == 1 ? "" : "s"))
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
                                unitName: form.unitName,
                                allowsHalfSteps: form == .tablet || form == .capsule
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
                Text(isAsNeeded ? "As-needed forecasts require at least three recent logged doses." : "This schedule drives reminders and the supply forecast. Confirm it against the current label or clinician instructions. Half doses are fine — enter 2.5 for two and a half tablets.")
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
                VStack(alignment: .leading, spacing: 4) {
                    MedicationFieldTitle("Refills remaining")
                    TextField("Refills remaining (optional)", text: $refillsText)
                        .keyboardType(.numberPad)
                }
                .padding(.vertical, 3)
                Toggle("Package expiration", isOn: $hasExpirationDate.animation(.medsSpring))
                if hasExpirationDate {
                    DatePicker("Expires", selection: $expirationDate, displayedComponents: .date)
                }
                VStack(alignment: .leading, spacing: 4) {
                    MedicationFieldTitle("Lot number")
                    TextField("Lot number (optional)", text: $lotNumber)
                }
                .padding(.vertical, 3)
                if !productIdentifier.isEmpty {
                    LabeledContent(productIdentifierType.isEmpty ? "Product code" : productIdentifierType) {
                        Text(productIdentifier)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                }
                NDCEntryRow(code: $ndcEntry, usedCode: nameProvenance == .ndc ? productIdentifier : nil) { code, product in
                    applyDirectoryProduct(product, code: code)
                }
            }

            Section {
                Label("Meds Ahead organizes information you confirm. It does not recommend doses or determine whether a prescription can be refilled.", systemImage: "checkmark.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        // Several fields use the decimal pad, which has no return key. Without this,
        // the only way out of one is to tap another field.
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(isEditing ? "Edit Medication" : (draftSource == .manual ? "Add Medication" : "Review Medication"))
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
        .onChange(of: focusedNameField) { oldValue, _ in
            guard let oldValue else { return }
            reconcileNames(after: oldValue)
        }
        .task { loadExistingSchedulesIfNeeded() }
    }

    /// A label prints one of a medication's two names, and a person copying from it
    /// can put either one in either field. Both fields end up correct whichever way
    /// round they were entered, because the shared list a clinician reads has a
    /// column for each.
    private func reconcileNames(after field: NameField) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBrandName = brandName.trimmingCharacters(in: .whitespacesAndNewlines)

        switch field {
        case .medication:
            guard let pair = MedicationBrandIndex.resolve(trimmedName) else { return }
            name = MedicationBrandIndex.displayName(forGeneric: pair.generic)
            brandName = pair.brand
            if !pair.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !isBrandNameVisible {
                withAnimation(.medsSpring) { isBrandNameVisible = true }
            }

        case .brand:
            guard !trimmedBrandName.isEmpty,
                  let pair = MedicationBrandIndex.resolve(trimmedBrandName) else { return }
            brandName = pair.brand
            if trimmedName.isEmpty || MedicationBrandIndex.resolve(trimmedName)?.generic == pair.generic {
                name = MedicationBrandIndex.displayName(forGeneric: pair.generic)
            }
            if !pair.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !isBrandNameVisible {
                withAnimation(.medsSpring) { isBrandNameVisible = true }
            }
        }
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
            identificationNote
            DisclosureGroup("Scan evidence") {
#if DEBUG
                // Debug builds only: whether the full-resolution Review capture
                // ran, what it saw, and whether the evidence cap cut anything.
                if !draftCaptureNote.isEmpty {
                    Text(draftCaptureNote)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.vertical, 3)
                }
#endif
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
        }
    }

    /// What became of the label's code, in words. "Not read" and "read but
    /// refused" used to look the same, an empty screen, and only the second is
    /// worth a second look at the digits.
    @ViewBuilder
    private var identificationNote: some View {
        if nameProvenance == .ndc {
            summaryNote(
                title: "Identified by its NDC",
                symbol: "checkmark.seal.fill",
                tint: AppTheme.accent,
                message: "The name, strength and form come from the FDA directory entry for the code on this label. Check that they match the bottle."
            )
        } else {
            switch draftIdentification {
            case let .uncorroborated(code, product):
                summaryNote(
                    title: "Code read, not used yet",
                    symbol: "questionmark.circle.fill",
                    tint: .orange,
                    message: "The label prints \(code), which the FDA directory lists as \(product). Nothing else on the label confirmed it, so no field was filled from it. If the bottle agrees, use it under Prescription & package."
                )
            case let .contradicted(code, product):
                summaryNote(
                    title: "Code read, but the label disagrees",
                    symbol: "exclamationmark.triangle.fill",
                    tint: .orange,
                    message: "The label prints \(code), which the FDA directory lists as \(product), but the printed name, strength or form says otherwise. Nothing was filled from the code. Check the bottle before saving."
                )
            case let .unlisted(code):
                summaryNote(
                    title: "Code read, not in the directory",
                    symbol: "questionmark.circle.fill",
                    tint: .orange,
                    message: "\(code) was read as an NDC but is not in the bundled FDA directory. A digit may have been misread; it is ready to check under Prescription & package."
                )
            case .ambiguous:
                summaryNote(
                    title: "More than one code read",
                    symbol: "exclamationmark.triangle.fill",
                    tint: .orange,
                    message: "The label yielded codes for different products, so none was used. Enter the one on the bottle under Prescription & package."
                )
            case .accepted, nil:
                Text("No NDC was read from this label. If it prints one, enter it under Prescription & package for an exact match.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func summaryNote(title: String, symbol: String, tint: Color, message: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// The person has read the code off the bottle and chosen the product it
    /// names, which is the corroboration a typed code has: the directory entry
    /// fills the identity the way an accepted scan does, and every field stays
    /// theirs to change.
    private func applyDirectoryProduct(_ product: NDCProduct, code: NationalDrugCode) {
        withAnimation(.medsSpring) {
            name = NDCIdentification.displayName(for: product)
            brandName = product.brandName.isEmpty
                ? (MedicationBrandIndex.brandName(forGeneric: name) ?? "")
                : product.brandName
            if !brandName.isEmpty { isBrandNameVisible = true }
            if !product.strength.isEmpty { strength = product.strength }
            form = product.form
            productIdentifier = code.hyphenated
            productIdentifierType = "NDC"
            rxNormCode = RxNormTable.shared.product(for: code)?.rxcui ?? ""
            nameProvenance = .ndc
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private var healthSummarySection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("From Apple Health")
                        .font(.headline)
                    Text("The name is the one you chose in Health. Confirm the strength, enter what you have on hand, and set the schedule Meds Ahead should keep count of.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            if !draftImportedDoses.isEmpty {
                Toggle(isOn: $importsDoseHistory) {
                    Text(importedDosesTitle)
                }
                .accessibilityIdentifier("import-dose-history")
            }
        } footer: {
            if !draftImportedDoses.isEmpty {
                Text("Imported doses are logged at the times Health recorded them. They give an as-needed medication a usage rate from day one and do not count against the amount you enter now.")
            }
        }
    }

    private var importedDosesTitle: String {
        let count = draftImportedDoses.count
        guard let earliest = draftImportedDoses.map(\.date).min() else { return "" }
        return "Import \(count) dose\(count == 1 ? "" : "s") logged in Health since \(earliest.formatted(date: .abbreviated, time: .omitted))"
    }

    private var hasUnsavedRequiredData: Bool {
        !name.isEmpty || !brandName.isEmpty || !strength.isEmpty || !currentSupplyText.isEmpty
    }

    private func redactedEvidence(_ evidence: ScanEvidence) -> String {
        if evidence.kind == .barcode, evidence.value.lowercased().hasPrefix("http") {
            return "Web link detected, not opened"
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
            target.brandName = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
            target.strength = strength.trimmingCharacters(in: .whitespacesAndNewlines)
            target.form = form
            target.directions = directions.trimmingCharacters(in: .whitespacesAndNewlines)
            target.updatedAt = .now
        } else {
            let newMedication = Medication(
                name: cleanedName,
                nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
                brandName: brandName.trimmingCharacters(in: .whitespacesAndNewlines),
                strength: strength.trimmingCharacters(in: .whitespacesAndNewlines),
                form: form,
                directions: directions.trimmingCharacters(in: .whitespacesAndNewlines),
                source: draftSource,
                sourceConfidence: draftEvidence.isEmpty ? 1 : draftEvidence.map(\.confidence).reduce(0, +) / Double(max(1, draftEvidence.count)),
                accentIndex: AppTheme.accentIndex(for: cleanedName)
            )
            modelContext.insert(newMedication)
            target = newMedication
            let opening = InventoryEvent(
                medicationID: target.id,
                delta: Double.medicationQuantity(from: currentSupplyText) ?? 0,
                reason: .openingCount
            )
            modelContext.insert(opening)
            inventoryForNotifications.removeAll { $0.id == opening.id }
            inventoryForNotifications.append(opening)
            if importsDoseHistory {
                for dose in draftImportedDoses {
                    modelContext.insert(DoseEvent(
                        medicationID: target.id,
                        recordedAt: dose.date,
                        doseQuantity: dose.quantity,
                        status: .taken,
                        note: DoseEvent.appleHealthNote,
                        countsTowardSupply: false,
                        healthSampleID: dose.sampleID
                    ))
                }
            }
            // Facts the review screen does not edit but the draft read off the
            // label or Health: the pharmacy.
            newMedication.pharmacyName = draftPharmacyName
            newMedication.pharmacyPhone = draftPharmacyPhone
            newMedication.rxNumber = draftRxNumber
        }

        target.refillsRemaining = Int(refillsText.trimmingCharacters(in: .whitespacesAndNewlines))
        target.refillLeadDays = refillLeadDays
        target.expirationDate = hasExpirationDate ? expirationDate : nil
        target.lotNumber = lotNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        target.productIdentifier = productIdentifier
        target.productIdentifierType = productIdentifierType
        target.rxNormCode = rxNormCode
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
            let medicationsForNotifications = allMedications.filter { $0.id != target.id } + [target]
            let schedulesForNotifications = allSchedules.filter { $0.medicationID != target.id } + newSchedules
            let notificationPlans = NotificationPlanBuilder.makeAll(
                medications: medicationsForNotifications,
                schedules: schedulesForNotifications,
                inventoryEvents: inventoryForNotifications,
                doseEvents: allDoseEvents
            )
            let shouldRequestNotificationAuthorization = target.remindersEnabled || target.refillRemindersEnabled
            Task {
                await NotificationService.shared.replaceAllNotifications(
                    for: notificationPlans,
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

/// A field for the code off the bottle. Exactness should never depend on OCR
/// alone: the smallest print on a label is the line worth an exact match, and a
/// person can read it when the camera cannot.
private struct NDCEntryRow: View {
    @Binding var code: String
    /// The code the identity was filled from, when it was, so the row says so.
    let usedCode: String?
    let onUse: (NationalDrugCode, NDCProduct) -> Void
    @State private var lookup: Lookup = .empty
    @State private var lookupTask: Task<Void, Never>?

    private enum Lookup: Equatable {
        case empty
        case malformed
        case unlisted
        case ambiguous
        case found(NationalDrugCode, NDCProduct)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MedicationFieldTitle("NDC from the label")
            TextField("NDC (optional)", text: $code)
                .font(.body.monospaced())
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("ndc-entry")
                .accessibilityHint("Optional; the 10 or 11 digit code printed on the label, for an exact match")
            result
        }
        .padding(.vertical, 3)
        .task(id: code) { await resolve() }
    }

    @ViewBuilder
    private var result: some View {
        switch lookup {
        case .empty:
            EmptyView()
        case .malformed:
            note("An NDC has 10 or 11 digits, printed like 0093-1039-01.", symbol: "info.circle", tint: .secondary)
        case .unlisted:
            note("Not in the bundled FDA directory. Check each digit against the label.", symbol: "questionmark.circle", tint: .orange)
        case .ambiguous:
            note("These digits fit more than one product. Type the code with its hyphens.", symbol: "questionmark.circle", tint: .orange)
        case let .found(found, product):
            if usedCode == found.hyphenated {
                note("Name, strength and form filled from the FDA directory entry for \(found.hyphenated).", symbol: "checkmark.seal.fill", tint: AppTheme.accent)
            } else {
                note("FDA directory: \(NDCIdentification.summary(of: product)), \(product.form.displayName.lowercased()).", symbol: "text.magnifyingglass", tint: .secondary)
                Button {
                    onUse(found, product)
                } label: {
                    Label("Use This Product", systemImage: "checkmark.seal")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityIdentifier("use-ndc-product")
                .accessibilityHint("Fills the name, strength and form from the directory")
            }
        }
    }

    private func note(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }

    /// The directory's one-time load is a few hundred milliseconds of parsing,
    /// which must not land on the keyboard, so the lookup runs off the main actor
    /// and a keystroke cancels the one before it.
    @MainActor
    private func resolve() async {
        let typed = code.filter { $0.isNumber || $0 == "-" }
        guard !typed.isEmpty else {
            lookup = .empty
            return
        }
        let candidates = NationalDrugCode.candidates(fromRendering: typed)
        guard !candidates.isEmpty else {
            lookup = typed.filter(\.isNumber).count >= 6 ? .malformed : .empty
            return
        }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        let hits = await Task.detached(priority: .userInitiated) {
            candidates.compactMap { code in NDCDirectory.shared.product(for: code).map { (code, $0) } }
        }.value
        guard !Task.isCancelled else { return }
        switch Set(hits.map(\.1.productKey)).count {
        case 0: lookup = .unlisted
        case 1: lookup = .found(hits[0].0, hits[0].1)
        default: lookup = .ambiguous
        }
    }
}

private struct MedicationFieldTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct WeekdayPicker: View {
    @Binding var mask: Int
    private let symbols = Calendar.current.veryShortWeekdaySymbols
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// `veryShortWeekdaySymbols` is always Sunday-first, and bit 0 of the mask is
    /// Sunday to match `Calendar.component(.weekday)`. Only the display order
    /// rotates, so a Monday-first locale reads correctly without touching storage.
    private var displayOrder: [Int] {
        let first = Calendar.current.firstWeekday - 1
        return (0..<7).map { (first + $0) % 7 }
    }

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
        ForEach(displayOrder, id: \.self) { index in
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
    let allowsHalfSteps: Bool
    @State private var text: String = ""
    @FocusState private var focused: Bool

    private var step: Double { allowsHalfSteps ? 0.5 : 1 }

    /// The stepper's floor cannot be the step size: a 0.5 mL liquid dose already
    /// on file sits below a step of 1, and the first tap would silently round it up.
    private static let minimumQuantity = 0.25

    /// Label above control, matching the "Days" picker directly below it. A single
    /// row cannot hold the label, the field, the stepper and a unit as long as
    /// "applications" without clipping one of them at either edge.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Amount per dose")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                TextField("Dose", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 54)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Color(uiColor: .tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .focused($focused)
                    .accessibilityIdentifier("dose-quantity")
                    .accessibilityLabel("Amount per dose")
                    .accessibilityValue("\(quantity.medicationQuantityText) \(unitName)")
                Stepper(value: $quantity, in: Self.minimumQuantity...999, step: step) {
                    Text("Amount per dose")
                }
                .labelsHidden()
                Text(unitName + (quantity == 1 ? "" : "s"))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
        }
        .onAppear { text = quantity.medicationQuantityText }
        .onChange(of: text) { _, newValue in
            // Track the typing rather than waiting for the field to lose focus:
            // tapping Add with the keyboard still up saved the previous amount.
            guard focused,
                  let value = Double.medicationQuantity(from: newValue),
                  value.isFinite,
                  value > 0 else { return }
            quantity = value
        }
        .onChange(of: quantity) { _, newValue in
            // Never rewrite the field under the person typing in it.
            guard !focused else { return }
            text = newValue.medicationQuantityText
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .onSubmit { commit() }
        .toolbar {
            // Scoped to this field's own focus: an unscoped keyboard toolbar shows
            // a Done button above every other field in the form, where tapping it
            // does nothing.
            if focused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
    }

    /// The field always ends up showing the number that was actually stored. The
    /// parse is lenient — "1.5.5" reads as 1.5 — so rewriting the text only from
    /// `quantity`'s change left a rejected-looking entry on screen whenever the
    /// parsed value happened to equal what was already there.
    private func commit() {
        guard let value = Double.medicationQuantity(from: text), value.isFinite, value > 0 else {
            text = quantity.medicationQuantityText
            return
        }
        quantity = value
        text = value.medicationQuantityText
    }
}

struct AddMedicationFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Step] = []

    /// The reviewed draft travels inside the path value rather than in separate
    /// state the destination closure reads later. Two earlier shapes both lost a
    /// scanned draft on the way to review: separate
    /// `navigationDestination(isPresented:)` modifiers on one view, and a payload-free
    /// `.editor` case, which is one unchanging value, so SwiftUI could rebuild the
    /// editor from a stale draft or reuse the previous view's state outright.
    /// Carrying the draft makes each review screen a distinct destination.
    enum Step: Hashable {
        case scanner
        case editor(MedicationDraft)
        case healthImport
        /// Reviewed from the Health list rather than the scanner: saving returns
        /// to that list so the next medication can be added, instead of closing
        /// the whole flow.
        case healthReview(MedicationDraft)
    }

    private var canImportFromHealth: Bool {
        if #available(iOS 26.0, *) {
            return HealthMedicationImporter.isAvailable
        }
        return false
    }

    var body: some View {
        NavigationStack(path: $path) {
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
                            path.append(.scanner)
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
                            path.append(.editor(MedicationDraft()))
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

                        if canImportFromHealth {
                            Button {
                                path.append(.healthImport)
                            } label: {
                                AddOptionCard(
                                    symbol: "heart.text.square.fill",
                                    title: "Import from Apple Health",
                                    message: "Bring over medications you already track in Health. You choose which ones to share.",
                                    prominent: false
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("health-import")
                        }
                    }
                    .padding(18)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
#if DEBUG
            .onAppear {
                guard ProcessInfo.processInfo.arguments.contains("-simulate-scan-result"),
                      path.isEmpty else { return }
                path.append(.editor(MedicationDraft(
                    name: "Amphetamine",
                    strength: "20 mg",
                    form: .tablet,
                    directions: "Take one tablet by mouth twice daily",
                    currentSupply: 60,
                    source: .scanned,
                    evidence: [ScanEvidence(kind: .text, value: "AMPHETAMINE 20 MG", confidence: 0.9)]
                )))
            }
#endif
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .scanner:
                    ScannerScreen { scannedDraft in
                        path.append(.editor(scannedDraft))
                    }
                case let .editor(draft):
                    MedicationEditorView(draft: draft, onSaved: { dismiss() })
                case .healthImport:
                    if #available(iOS 26.0, *) {
                        HealthImportView { draft in
                            path.append(.healthReview(draft))
                        }
                    }
                case let .healthReview(draft):
                    MedicationEditorView(draft: draft, onSaved: { path.removeLast() })
                }
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
