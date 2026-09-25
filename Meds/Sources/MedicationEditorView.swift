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
    private let draftCaptureNote: String
    private let draftLabelQuantity: Double?
    private let draftLabelQuantityNote: String?
    /// The draft as it arrived, for which fields its label read.
    private let reviewedDraft: MedicationDraft
    /// Called with the medication once it is saved, so the add flow can say
    /// what went in.
    private let onSaved: ((Medication) -> Void)?
    /// Offered a bottle of a medication already tracked, to add to that one
    /// instead of saving a second. Without it the review offers nothing.
    private let onAddBottle: ((AddBottleRequest) -> Void)?
    /// Called after a save that changed what past days were scheduled to hold
    /// while the forecast was assuming unlogged doses: only a count can say
    /// what those doses took, so the presenter asks for one.
    private let onAskForCount: (() -> Void)?
    /// Called in place of closing the review when it is thrown away, so the
    /// add flow can move on from the scanner that read it.
    private let onDiscard: (() -> Void)?

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
    @State private var personName: String
    @State private var pharmacyName: String
    @State private var pharmacyPhone: String
    @State private var rxNumber: String
    @State private var isAsNeeded: Bool
    @State private var remindersEnabled: Bool
    @State private var refillRemindersEnabled: Bool
    @State private var detailedNotifications: Bool
    @State private var editableSchedules: [EditableDoseSchedule]
    @State private var courseEnds = false
    @State private var courseLastDay = Date.now
    /// The course's last day as stored, saved back untouched unless another
    /// day is picked.
    @State private var storedCourseEnd: Date?
    @State private var importsDoseHistory = true
    @State private var didLoadExistingSchedules = false
    @State private var showingValidation = false
    @State private var validationMessage = ""
    @State private var showingDiscardConfirmation = false
    @FocusState private var focusedNameField: NameField?

    init(
        medication: Medication? = nil,
        draft: MedicationDraft = MedicationDraft(),
        onSaved: ((Medication) -> Void)? = nil,
        onAddBottle: ((AddBottleRequest) -> Void)? = nil,
        onAskForCount: (() -> Void)? = nil,
        onDiscard: (() -> Void)? = nil
    ) {
        self.medication = medication
        self.draftEvidence = draft.evidence
        self.draftSource = medication?.source ?? draft.source
        self.draftIdentification = draft.identification
        self.draftImportedDoses = draft.importedDoses
        self.draftCaptureNote = draft.captureNote
        self.draftLabelQuantity = draft.labelDispensedQuantity
        self.draftLabelQuantityNote = draft.labelDispensedNote
        self.reviewedDraft = draft
        self.onSaved = onSaved
        self.onAddBottle = onAddBottle
        self.onAskForCount = onAskForCount
        self.onDiscard = onDiscard
        let resolvedForm = medication?.form ?? draft.form
        _name = State(initialValue: medication?.name ?? draft.name)
        _nickname = State(initialValue: medication?.nickname ?? draft.nickname)
        let resolvedBrandName = medication?.brandName ?? draft.brandName
        _brandName = State(initialValue: resolvedBrandName)
        _isBrandNameVisible = State(initialValue: !resolvedBrandName.isEmpty)
        _strength = State(initialValue: medication?.strength ?? draft.strength)
        _form = State(initialValue: resolvedForm)
        _directions = State(initialValue: medication?.directions ?? draft.directions)
        _currentSupplyText = State(initialValue: draft.initialCurrentAmountText)
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
        _personName = State(initialValue: medication?.personName ?? "")
        _pharmacyName = State(initialValue: medication?.pharmacyName ?? draft.pharmacyName)
        _pharmacyPhone = State(initialValue: medication?.pharmacyPhone ?? draft.pharmacyPhone)
        _rxNumber = State(initialValue: medication?.rxNumber ?? draft.rxNumber)
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
            if let problem = Self.courseLastDayProblem(courseEnds: courseEnds, lastDay: courseLastDay, stored: storedCourseEnd) {
                return problem
            }
        }
        return nil
    }

    var body: some View {
        Form {
            let duplicates = duplicateMatches
            if !duplicates.isEmpty {
                duplicateSection(duplicates)
            }
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
                    MedicationFieldTitle("Who takes this")
                    TextField("Person (optional)", text: $personName)
                        .textInputAutocapitalization(.words)
                        .accessibilityHint("Optional; groups Today, Supply and the shared list by person")
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
                        Text(form.unitText(for: Double.medicationQuantity(from: currentSupplyText) ?? 0))
                            .foregroundStyle(.secondary)
                    }
                    if let draftLabelQuantity, let draftLabelQuantityNote {
                        labelQuantityRow(quantity: draftLabelQuantity, note: draftLabelQuantityNote)
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
                                form: form,
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
                    Toggle("Course ends", isOn: $courseEnds.animation(.medsSpring))
                        .accessibilityIdentifier("course-ends")
                        .accessibilityHint("For a medication taken until a set day, such as an antibiotic")
                        .onChange(of: courseEnds) { _, isOn in
                            // From today as it is now: the editor may have
                            // opened before midnight, and a picker shows a day
                            // before its range as today while it keeps the old.
                            if isOn, storedCourseEnd == nil { courseLastDay = .now }
                        }
                    if courseEnds {
                        DatePicker(
                            "Last day",
                            selection: $courseLastDay,
                            in: Self.earliestCourseLastDay(stored: storedCourseEnd)...,
                            displayedComponents: .date
                        )
                        .accessibilityIdentifier("course-last-day")
                    }
                }
            } header: {
                Text("Schedule")
            } footer: {
                Text(isAsNeeded ? "As-needed forecasts require at least three recent logged doses." : Self.scheduleFooter(courseEnds: courseEnds, storedCourseEnd: storedCourseEnd))
            }

            Section {
                Toggle("Dose reminders", isOn: $remindersEnabled)
                    .disabled(isAsNeeded)
                Toggle("Refill reminders", isOn: $refillRemindersEnabled)
                Toggle("Show medication name", isOn: $detailedNotifications)
                    .disabled((!remindersEnabled || isAsNeeded) && !refillRemindersEnabled)
                Stepper("Low supply: \(refillLeadDays.dayCountText) before", value: $refillLeadDays, in: 1...30)
                    .disabled(!refillRemindersEnabled)
            } header: {
                Text("Reminders")
            } footer: {
                if let note = SupplyAttention.lengthenedLeadNote(
                    refillLeadDays: refillLeadDays,
                    refillsRemaining: Int(refillsText.trimmingCharacters(in: .whitespacesAndNewlines))
                ) {
                    Text(note)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    MedicationFieldTitle("Pharmacy")
                    TextField("Pharmacy (optional)", text: $pharmacyName)
                        .textInputAutocapitalization(.words)
                }
                .padding(.vertical, 3)
                VStack(alignment: .leading, spacing: 4) {
                    MedicationFieldTitle("Pharmacy phone")
                    TextField("Phone (optional)", text: $pharmacyPhone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                .padding(.vertical, 3)
                VStack(alignment: .leading, spacing: 4) {
                    MedicationFieldTitle("Rx number")
                    TextField("Rx number (optional)", text: $rxNumber)
                        .keyboardType(.numbersAndPunctuation)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.vertical, 3)
            } header: {
                Text("Pharmacy")
            } footer: {
                Text("For the call a low-supply reminder leads to. A scanned label fills in what it prints.")
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
                        discard()
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
            Button("Discard", role: .destructive) { discard() }
        } message: {
            Text("The information you reviewed or entered will not be saved.")
        }
        .onChange(of: focusedNameField) { oldValue, _ in
            guard let oldValue else { return }
            reconcileNames(after: oldValue)
        }
        .task { loadExistingSchedulesIfNeeded() }
    }

    private func discard() {
        if let onDiscard { onDiscard() } else { dismiss() }
    }

    /// Worked out from the fields as they stand, so a manual entry meets the
    /// banner as its name and strength are typed, and a code chosen under Use
    /// This Product counts once it is chosen. Health drafts are left out: the
    /// Health list already says which are here, and a Health entry is not a
    /// bottle to add.
    private var duplicateMatches: [Medication] {
        guard !isEditing, draftSource != .appleHealth, onAddBottle != nil else { return [] }
        let identity = DuplicateMedicationMatcher.Identity(
            name: name,
            strength: strength,
            brandName: brandName,
            productIdentifier: productIdentifier,
            productIdentifierType: productIdentifierType,
            rxNormCode: rxNormCode,
            nameProvenance: nameProvenance
        )
        return DuplicateMedicationMatcher.matches(for: identity, among: allMedications, schedules: allSchedules)
    }

    /// Above everything else on the screen, because it decides whether the rest
    /// is needed: a bottle added to a medication already here needs no name,
    /// schedule or reminders of its own.
    private func duplicateSection(_ matches: [Medication]) -> some View {
        Section {
            ForEach(matches) { match in
                VStack(alignment: .leading, spacing: 10) {
                    Label {
                        Text("Already in Meds Ahead: \(DuplicateMedicationMatcher.description(of: match))")
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "square.stack.3d.up.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("duplicate-banner")
                    Button {
                        onAddBottle?(AddBottleRequest(
                            medication: match,
                            labelQuantity: draftLabelQuantity,
                            labelQuantityNote: draftLabelQuantityNote,
                            labelUpdates: AddBottleRecord.LabelUpdates.reviewed(
                                draft: reviewedDraft,
                                refillsText: refillsText,
                                expirationDate: hasExpirationDate ? expirationDate : nil,
                                rxNumber: rxNumber
                            )
                        ))
                    } label: {
                        Text("Add this bottle to \(match.displayName)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(AppTheme.onAccent)
                    .controlSize(.large)
                    .accessibilityIdentifier("add-to-existing")
                }
                .padding(.vertical, 4)
            }
        } footer: {
            Text("Adding it there keeps one count and one set of reminders. If this bottle is someone else's, review below and tap Add.")
        }
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
            // A code kept without its package segment looks misread next to the
            // bottle's; saying why stops someone from "correcting" it.
            let packageWithheld = productIdentifierType == "NDC" && productIdentifier.split(separator: "-").count == 2
            summaryNote(
                title: "Identified by its NDC",
                symbol: "checkmark.seal.fill",
                tint: AppTheme.accent,
                message: "The name, strength and form come from the FDA directory entry for the code on this label. Check that they match the bottle."
                    + (packageWithheld ? " The code’s last digits were read more than one way, so only the product part is kept." : "")
            )
        } else {
            switch draftIdentification {
            case let .uncorroborated(code, product):
                summaryNote(
                    title: "Code read, not used yet",
                    symbol: "questionmark.circle.fill",
                    tint: .orange,
                    message: "The label prints \(code), which the FDA directory lists as \(product). The label did not confirm it, so no field was filled from it. If the bottle agrees, use it under Prescription & package."
                )
            case let .contradicted(code, product):
                summaryNote(
                    title: "Code read, but the label disagrees",
                    symbol: "exclamationmark.triangle.fill",
                    tint: .orange,
                    message: "The label prints \(code), which the FDA directory lists as \(product), but the name, brand, strength, form or release (such as ER or XL) printed on the label says otherwise. Nothing was filled from the code. Check the bottle before saving."
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
            (name, brandName) = NDCIdentification.identity(of: product)
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

    /// The label's count, one tap from Current amount but never in it unasked.
    private func labelQuantityRow(quantity: Double, note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Label(note, systemImage: "doc.text.viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("That is the count before any were taken, not what is left. Use it for an unopened bottle; otherwise enter what you count now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("label-quantity-note")
            // Once used, the button stays and says so rather than vanishing: at
            // the largest text sizes the field is scrolled away and this is the
            // only sign the tap did anything, and a vanishing button would take
            // VoiceOver's focus with it.
            let quantityText = quantity.medicationQuantityText
            let isInUse = Double.medicationQuantity(from: currentSupplyText) == quantity
            Button {
                // Written ungrouped, as the field's prefill is, so a label's
                // 1497.5 cannot be half-edited from "1.497,5" into 1.497.
                currentSupplyText = SupplyChangeQuantity.text(for: quantity)
            } label: {
                // The checkmark sits inline in the text: as a Label's icon it
                // broke "Using" mid-word at the largest text sizes.
                Text(isInUse ? "\(Image(systemName: "checkmark")) Using \(quantityText)" : "Use \(quantityText)")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isInUse)
            .accessibilityLabel(isInUse ? "Using \(quantityText) as the current amount" : "Use \(quantityText) as the current amount")
            .accessibilityIdentifier("use-label-quantity")
        }
        .padding(.vertical, 3)
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
        return "Import \(count.counted("dose", plural: "doses")) logged in Health since \(earliest.formatted(date: .abbreviated, time: .omitted))"
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
        // A course taken up again keeps its ended schedules as history; the
        // editor shows only the ones an edit changes.
        let existing = ScheduleReconciler.currentSchedules(allSchedules, medicationID: medication.id)
            .sorted { $0.minutesAfterMidnight < $1.minutesAfterMidnight }
        if !existing.isEmpty {
            editableSchedules = existing.map {
                EditableDoseSchedule(
                    time: Self.date(minutes: $0.minutesAfterMidnight),
                    doseQuantity: $0.doseQuantity,
                    weekdayMask: $0.weekdayMask
                )
            }
        }
        if let end = ScheduleEngine.courseEnd(schedules: existing, medicationID: medication.id) {
            storedCourseEnd = end
            courseLastDay = end
            courseEnds = true
        }
        didLoadExistingSchedules = true
    }

    /// The first day the Last day picker offers: today, or a finished
    /// course's own last day, which a picker starting at today would show as
    /// today. The days between that one and today stay on offer only because
    /// a range cannot skip them; `courseLastDayProblem` refuses them.
    static func earliestCourseLastDay(stored: Date?, now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let today = calendar.startOfDay(for: now)
        guard let stored else { return today }
        return min(today, calendar.startOfDay(for: stored))
    }

    /// The end every schedule is saved with. A day left as it was keeps the
    /// stored moment: read abroad, noon at home can fall on the next day, and
    /// normalised again there it would move the course's last day with it.
    static func savedCourseEnd(
        courseEnds: Bool,
        lastDay: Date,
        stored: Date?,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        guard courseEnds else { return nil }
        if let stored, calendar.isDate(stored, inSameDayAs: lastDay) { return stored }
        return ScheduleEngine.normalizedEndDate(forDay: lastDay, calendar: calendar)
    }

    /// Why the last day cannot be saved, or nil. A day picked must be today
    /// or later; only a finished course's own last day, left as it was, may
    /// be past. A day before today saved as new would be a course already
    /// over, with no reminders at all, or would stretch a finished course
    /// over days nobody was asked to take a dose on. And the picker cannot
    /// be trusted to prevent it: a compact picker shows a day before its
    /// range as the first day it offers while it keeps the earlier one.
    static func courseLastDayProblem(
        courseEnds: Bool,
        lastDay: Date,
        stored: Date?,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String? {
        guard courseEnds else { return nil }
        if let stored, calendar.isDate(stored, inSameDayAs: lastDay) { return nil }
        let today = calendar.startOfDay(for: now)
        guard calendar.startOfDay(for: lastDay) < today else { return nil }
        if let stored, calendar.startOfDay(for: stored) < today {
            return "Choose today or a later day to start this course again, or \(ForecastEngine.dayText(stored, calendar: calendar)) to keep its last day."
        }
        return "Choose today or a later day for the course's last day."
    }

    /// Under the Schedule section of a scheduled medication.
    static func scheduleFooter(
        courseEnds: Bool,
        storedCourseEnd: Date?,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        var footer = "This schedule drives reminders and the supply forecast. Confirm it against the current label or clinician instructions. Half doses are fine — enter 2.5 for two and a half tablets."
        if courseEnds { footer += " Reminders stop after the last day." }
        // Saving a finished course with a new last day, or none, starts it
        // again today rather than filling in the days since, so the footer
        // says so before the person saves. Its last day, not "finished": a
        // course whose supply ran out first is not called finished anywhere.
        if let storedCourseEnd, calendar.startOfDay(for: storedCourseEnd) < calendar.startOfDay(for: now) {
            footer += " This course's last day was \(ForecastEngine.dayText(storedCourseEnd, calendar: calendar))."
            footer += courseEnds ? " Choosing today or a later day starts it again from today." : " Saved without a last day, it starts again from today."
        }
        return footer
    }

    private func save() {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Taken before anything below changes the medication or its schedules.
        let assumedBefore = medication.map {
            ForecastEngine.forecast(medication: $0, schedules: allSchedules, inventoryEvents: allInventoryEvents, doseEvents: allDoseEvents).assumedDoses
        } ?? 0
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
        }

        target.refillsRemaining = Int(refillsText.trimmingCharacters(in: .whitespacesAndNewlines))
        target.refillLeadDays = refillLeadDays
        target.expirationDate = hasExpirationDate ? expirationDate : nil
        target.lotNumber = lotNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        target.productIdentifier = productIdentifier
        target.productIdentifierType = productIdentifierType
        target.rxNormCode = rxNormCode
        target.personName = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.pharmacyName = pharmacyName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.pharmacyPhone = pharmacyPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        target.rxNumber = rxNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        target.isAsNeeded = isAsNeeded
        target.remindersEnabled = remindersEnabled && !isAsNeeded
        target.refillRemindersEnabled = refillRemindersEnabled
        target.detailedNotifications = detailedNotifications

        let courseEnd = Self.savedCourseEnd(courseEnds: courseEnds, lastDay: courseLastDay, stored: storedCourseEnd)
        let scheduleDefinitions: [ScheduleDefinition] = if isAsNeeded {
            []
        } else {
            editableSchedules.map { schedule in
                let components = Calendar.current.dateComponents([.hour, .minute], from: schedule.time)
                let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                return ScheduleDefinition(
                    minutesAfterMidnight: minutes,
                    doseQuantity: schedule.doseQuantity,
                    weekdayMask: schedule.weekdayMask,
                    endDate: courseEnd
                )
            }
        }
        let existingSchedules = allSchedules.filter { $0.medicationID == target.id }
        // What the edit changes, as the editor showed it; a reopened course's
        // ended schedules are history the edit leaves alone.
        let scheduledBefore = ScheduleReconciler.snapshot(ScheduleReconciler.currentSchedules(existingSchedules, medicationID: target.id))
        let newSchedules = ScheduleReconciler.reconcile(
            medicationID: target.id,
            definitions: scheduleDefinitions,
            existing: existingSchedules,
            in: modelContext
        )
        let asksForCount = ScheduleReconciler.asksForCount(assumedDoses: assumedBefore, before: scheduledBefore, after: newSchedules)

        do {
            try modelContext.save()
            let medicationsForNotifications = allMedications.filter { $0.id != target.id } + [target]
            // As saved, with any history a course taken up again keeps: the
            // forecast behind the refill alert weighs those days too.
            let targetID = target.id
            let savedSchedules = (try? modelContext.fetch(FetchDescriptor<DoseSchedule>(predicate: #Predicate { $0.medicationID == targetID })))
                ?? newSchedules
            let schedulesForNotifications = allSchedules.filter { $0.medicationID != target.id } + savedSchedules
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
            if asksForCount { onAskForCount?() }
            if let onSaved {
                onSaved(target)
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

/// A label's quantity is what the bottle held when full, not the amount in it
/// now. Filled in as the current amount, a bottle two weeks into a twice-daily
/// fill read 28 doses high, and a count that is too high is the one that lets
/// someone run out. So a scanned count is offered, never filled in. The words
/// say "when full" rather than "dispensed" because the parser also reads a
/// stock bottle's printed count ("120 TABLETS"), which no pharmacy filled.
extension MedicationDraft {
    /// The count a scanned label printed, when it printed one, as the number the
    /// Use button writes into the field. A label can print more decimals than a
    /// quantity shows ("QTY: 473.176"), and the note, the button's Using state
    /// and the saved amount must all be the one number the person sees.
    var labelDispensedQuantity: Double? {
        guard source == .scanned, let currentSupply, currentSupply.isFinite,
              let shown = Double.medicationQuantity(from: currentSupply.medicationQuantityText),
              shown > 0 else { return nil }
        return shown
    }

    /// The line under Current amount on a scanned label's review screen.
    var labelDispensedNote: String? {
        labelDispensedQuantity.map { "Label says \($0.medicationQuantityText) when full" }
    }

    /// What Current amount starts as. A scanned draft's number is the label's,
    /// so that field starts blank. Otherwise it opens as the supply sheets do,
    /// ungrouped: a region that groups with "." showed 1497.5 as "1.497,5", and
    /// deleting only the fraction saved 1.497.
    var initialCurrentAmountText: String {
        guard source != .scanned else { return "" }
        return currentSupply.map { SupplyChangeQuantity.text(for: $0) } ?? ""
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
                    .foregroundStyle(mask & (1 << index) != 0 ? AppTheme.onAccent : .primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Calendar.current.weekdaySymbols[index])
            .accessibilityValue(mask & (1 << index) != 0 ? "Selected" : "Not selected")
        }
    }
}

private struct ScheduleDoseQuantityField: View {
    @Binding var quantity: Double
    let form: MedicationForm
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
                    .accessibilityValue(form.quantityText(quantity))
                Stepper(value: $quantity, in: Self.minimumQuantity...999, step: step) {
                    Text("Amount per dose")
                }
                .labelsHidden()
                Text(form.unitText(for: quantity))
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
    @State private var navigation = Navigation()
    @State private var bottleRequest: AddBottleRequest?
    /// The review a bottle request came from, and the medication's name once
    /// the bottle is in. The flow moves on only when the sheet is gone.
    @State private var bottleDraft: MedicationDraft?
    @State private var bottleAddedTo: String?

    /// The reviewed draft travels inside the path value rather than in separate
    /// state the destination closure reads later. Two earlier shapes both lost a
    /// scanned draft on the way to review: separate
    /// `navigationDestination(isPresented:)` modifiers on one view, and a payload-free
    /// `.editor` case, which is one unchanging value, so SwiftUI could rebuild the
    /// editor from a stale draft or reuse the previous view's state outright.
    /// Carrying the draft makes each review screen a distinct destination.
    enum Step: Hashable {
        /// Numbered, and never reused within a flow: see `Navigation`.
        case scanner(Int)
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
        // Read here, in the body, and not inside the destination closure: the
        // stack builds a destination with the closure from the body's last
        // run, and a tally read inside it came back as it was then, leaving
        // the next scanner without the bottle just added.
        let tally = navigation.tally
        NavigationStack(path: $navigation.path) {
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
                            navigation.scan()
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
                            navigation.path.append(.editor(MedicationDraft()))
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
                                navigation.path.append(.healthImport)
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
                let arguments = ProcessInfo.processInfo.arguments
                guard arguments.contains("-simulate-scan-result"),
                      navigation.path.isEmpty else { return }
                navigation.path.append(.editor(SimulatedScan.draft(for: SimulatedScan.bottles(from: arguments).first ?? .standard)))
            }
#endif
            .navigationDestination(for: Step.self) { step in
                switch step {
                case let .scanner(session):
                    ScannerScreen(tally: tally, onDone: { dismiss() }) { scannedDraft in
                        navigation.path.append(.editor(scannedDraft))
                    }
                    // A new path puts its scanner in the stack's first place,
                    // and the stack kept the screen already there, state and
                    // all: the step's number alone left the last bottle's
                    // evidence behind the next Review button.
                    .id(session)
                case let .editor(draft):
                    MedicationEditorView(
                        draft: draft,
                        onSaved: { medication in finish(.added(medication.displayName), from: draft) },
                        onAddBottle: { request in
                            bottleDraft = draft
                            bottleRequest = request
                        },
                        onDiscard: draft.source == .scanned ? { navigation.discard() } : nil
                    )
                case .healthImport:
                    if #available(iOS 26.0, *) {
                        HealthImportView { draft in
                            navigation.path.append(.healthReview(draft))
                        }
                    }
                case let .healthReview(draft):
                    MedicationEditorView(draft: draft, onSaved: { _ in navigation.path.removeLast() })
                }
            }
        }
        // Presented from here rather than from the review, because the review
        // leaves the path once the bottle is in: the sheet belongs to a screen
        // that stays, and the flow moves on only once the sheet has closed.
        .sheet(item: $bottleRequest, onDismiss: finishAddingBottle) { request in
            AddBottleSheet(request: request) { medication in
                bottleAddedTo = medication.displayName
            }
        }
    }

    private func finish(_ outcome: Navigation.Outcome, from draft: MedicationDraft) {
        if navigation.finish(outcome, from: draft) == .close { dismiss() }
    }

    private func finishAddingBottle() {
        defer {
            bottleDraft = nil
            bottleAddedTo = nil
        }
        guard let bottleAddedTo, let bottleDraft else { return }
        finish(.addedTo(bottleAddedTo), from: bottleDraft)
    }
}

extension AddMedicationFlow {
    /// The flow's path and tally as plain values, so what one bottle leaves
    /// behind for the next can be tested without a screen.
    ///
    /// A caregiver home from the hospital with a bag of bottles scans them one
    /// after another, and a flow that closed after every save sent them back
    /// through Today, Add and Scan for each. A bottle from the scanner now
    /// returns to a scanner. It must be a new one: the scanner keeps what it
    /// read in its own state, and a scanner SwiftUI had seen before would hand
    /// the last bottle's text to the next bottle's review.
    struct Navigation: Hashable {
        enum Outcome: Hashable {
            /// Saved as a new medication, under this name.
            case added(String)
            /// Added to a medication already tracked, by that one's name.
            case addedTo(String)
        }

        enum Next: Hashable {
            case scanNext
            case close
        }

        var path: [Step] = []
        private(set) var tally = SetupSessionTally()
        /// Every scanner shown so far. Its count numbers the next one, so no
        /// two scanners in a flow are ever the same destination.
        private(set) var scannersShown = 0

        mutating func scan() {
            path.append(.scanner(scannersShown))
            scannersShown += 1
        }

        /// A bottle from the scanner goes on the tally, and a new scanner
        /// replaces the whole path, its review and that review's evidence with
        /// it. Anything entered by hand closes the flow, as it always has.
        mutating func finish(_ outcome: Outcome, from draft: MedicationDraft) -> Next {
            guard draft.source == .scanned else { return .close }
            switch outcome {
            case let .added(name): tally.recordAdded(name)
            case let .addedTo(name): tally.recordAddedTo(name)
            }
            path = [.scanner(scannersShown)]
            scannersShown += 1
            return .scanNext
        }

        /// A scanned review thrown away is followed by a new scanner too,
        /// with nothing added to the tally. The scanner it came from still
        /// holds the discarded bottle's text, and would read the next bottle
        /// together with it: a tacrolimus label set aside as already counted
        /// named the prednisone bottle after it, and offered to add its count
        /// to tacrolimus. The back button still returns to that scanner, to
        /// add another photo of the same label.
        mutating func discard() {
            path = [.scanner(scannersShown)]
            scannersShown += 1
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

#if DEBUG
/// Labels for the UI tests to scan, since the simulator has no camera. Each
/// `-simulate-scan-name` starts a bottle, and the `-simulate-scan-strength` and
/// `-simulate-scan-quantity` after it describe that bottle.
enum SimulatedScan {
    struct Bottle: Hashable {
        var name: String
        var strength = ""
        var quantity: Double = 0

        static let standard = Bottle(name: "Amphetamine", strength: "20 mg", quantity: 60)
    }

    static func bottles(from arguments: [String]) -> [Bottle] {
        var bottles: [Bottle] = []
        for (key, value) in zip(arguments, arguments.dropFirst()) {
            switch key {
            case "-simulate-scan-name":
                bottles.append(Bottle(name: value))
            case "-simulate-scan-strength" where !bottles.isEmpty:
                bottles[bottles.count - 1].strength = value
            case "-simulate-scan-quantity" where !bottles.isEmpty:
                bottles[bottles.count - 1].quantity = Double(value) ?? 0
            default:
                break
            }
        }
        return bottles
    }

    /// The review `-simulate-scan-result` opens on, as the scanner hands one over.
    static func draft(for bottle: Bottle) -> MedicationDraft {
        MedicationDraft(
            name: bottle.name,
            strength: bottle.strength,
            form: .tablet,
            directions: "Take one tablet by mouth twice daily",
            currentSupply: bottle.quantity,
            source: .scanned,
            evidence: [ScanEvidence(kind: .text, value: "\(bottle.name) \(bottle.strength)".uppercased(), confidence: 0.9)]
        )
    }

    /// Under `-simulate-scanner` the scanner offers a button that reads the
    /// next bottle's label into its evidence, as a chosen photo would, so the
    /// review goes through the scanner's own Review.
    static var isScannerButtonEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-simulate-scanner")
    }

    static func evidence(for bottle: Bottle) -> [ScanEvidence] {
        let capture = UUID()
        let lines = ["\(bottle.name) \(bottle.strength)".uppercased(), "QTY: \(bottle.quantity.medicationQuantityText)"]
        return lines.enumerated().map { index, line in
            ScanEvidence(kind: .text, value: line, confidence: 0.95, origin: .photoLibrary, captureID: capture, lineIndex: index)
        }
    }

    /// Bottles read so far this launch, so each scanner reads the next one.
    @MainActor private static var bottlesRead = 0

    @MainActor
    static func nextEvidence() -> [ScanEvidence] {
        let bottles = bottles(from: ProcessInfo.processInfo.arguments)
        guard !bottles.isEmpty else { return evidence(for: .standard) }
        defer { bottlesRead += 1 }
        return evidence(for: bottles[bottlesRead % bottles.count])
    }
}
#endif
