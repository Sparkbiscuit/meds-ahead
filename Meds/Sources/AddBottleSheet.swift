import SwiftData
import SwiftUI

/// What adding a bottle to a medication already tracked writes: one refill on
/// its ledger, never a second medication.
enum AddBottleRecord {
    /// What this label printed that the medication's record can take from it,
    /// as the review screen shows it now, so a digit the person corrected
    /// there is the digit written. Only fields the label read are here.
    struct LabelUpdates: Hashable {
        var refillsRemaining: Int?
        var expirationDate: Date?
        var rxNumber = ""

        var isEmpty: Bool { refillsRemaining == nil && expirationDate == nil && rxNumber.isEmpty }

        /// The review screen's values for the fields a scanned label read. A
        /// manual draft has no label to update from.
        static func reviewed(
            draft: MedicationDraft,
            refillsText: String,
            expirationDate: Date?,
            rxNumber: String
        ) -> LabelUpdates? {
            guard draft.source == .scanned else { return nil }
            var updates = LabelUpdates()
            if draft.refillsRemaining != nil,
               let refills = Int(refillsText.trimmingCharacters(in: .whitespacesAndNewlines)), refills >= 0 {
                updates.refillsRemaining = refills
            }
            if draft.expirationDate != nil { updates.expirationDate = expirationDate }
            if !draft.rxNumber.isEmpty { updates.rxNumber = rxNumber.trimmingCharacters(in: .whitespacesAndNewlines) }
            return updates.isEmpty ? nil : updates
        }

        /// "Also update refills left, expiry and Rx number from this label",
        /// naming only what the label read.
        func toggleTitle(locale: Locale = .autoupdatingCurrent) -> String {
            let fields = [
                refillsRemaining == nil ? nil : "refills left",
                expirationDate == nil ? nil : "expiry",
                rxNumber.isEmpty ? nil : "Rx number"
            ].compactMap { $0 }
            return "Also update \(fields.formatted(.list(type: .and).locale(locale))) from this label"
        }

        /// What of this label the medication takes. A later expiry and a higher
        /// refill count stay out, and so does anything already on file: the
        /// earlier bottle's pills may still be in the count, and a label from
        /// an earlier fill shows refills since used. Either would move a
        /// reminder later, and a reminder may come early but never late.
        func changes(to medication: Medication, calendar: Calendar = .autoupdatingCurrent) -> LabelUpdates {
            var changes = LabelUpdates()
            if let refillsRemaining, medication.refillsRemaining.map({ refillsRemaining < $0 }) ?? true {
                changes.refillsRemaining = refillsRemaining
            }
            if let expirationDate, medication.expirationDate.map({
                calendar.compare(expirationDate, to: $0, toGranularity: .day) == .orderedAscending
            }) ?? true {
                changes.expirationDate = expirationDate
            }
            if !rxNumber.isEmpty, rxNumber != medication.rxNumber { changes.rxNumber = rxNumber }
            return changes
        }

        /// What the label read that the medication keeps its own value for,
        /// said beside the toggle so the label's number is not simply missing.
        func kept(by medication: Medication, locale: Locale = .autoupdatingCurrent, calendar: Calendar = .autoupdatingCurrent) -> [String] {
            var lines: [String] = []
            if let refillsRemaining, let current = medication.refillsRemaining, refillsRemaining > current {
                lines.append("Refills left stay at \(current), fewer than this label's \(refillsRemaining)")
            }
            if let expirationDate, let current = medication.expirationDate,
               calendar.compare(expirationDate, to: current, toGranularity: .day) == .orderedDescending {
                lines.append("Expiry stays \(current.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))), earlier than this label's")
            }
            return lines
        }

        /// The values themselves, one per line, so the toggle says what it writes.
        func lines(locale: Locale = .autoupdatingCurrent) -> [String] {
            var lines: [String] = []
            if let refillsRemaining {
                lines.append(refillsRemaining == 0 ? "No refills left" : "\(refillsRemaining.counted("refill", plural: "refills")) left")
            }
            if let expirationDate {
                lines.append("Expires \(expirationDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)))")
            }
            if !rxNumber.isEmpty { lines.append("Rx \(rxNumber)") }
            return lines
        }
    }

    /// Records the bottle. The caller saves the context, and replans
    /// notifications once it has.
    ///
    /// Refills left changes only when the label says what it is: a bottle added
    /// here may be the second bottle of one fill rather than a new fill, so
    /// counting it as a refill used would be a guess. Only the label's values
    /// that `changes(to:)` lets through are written.
    @discardableResult
    static func record(
        quantity: Double,
        note: String,
        labelUpdates: LabelUpdates?,
        to medication: Medication,
        in context: ModelContext,
        now: Date = .now
    ) -> InventoryEvent {
        let event = InventoryEvent(medicationID: medication.id, date: now, delta: quantity, reason: .refill, note: note)
        context.insert(event)
        // The medication is in hand; whatever refill was in progress is done,
        // as Add Refill has it.
        medication.refillStatus = .none
        medication.refillStatusDate = nil
        if let changes = labelUpdates?.changes(to: medication) {
            if let refills = changes.refillsRemaining { medication.refillsRemaining = refills }
            if let expiration = changes.expirationDate { medication.expirationDate = expiration }
            if !changes.rxNumber.isEmpty { medication.rxNumber = changes.rxNumber }
        }
        medication.updatedAt = now
        return event
    }
}

/// A bottle the review screen found already tracked, with what its label can
/// bring along.
struct AddBottleRequest: Identifiable {
    let id = UUID()
    let medication: Medication
    /// The label's count when full, offered and never filled in, as on the
    /// review screen.
    let labelQuantity: Double?
    let labelQuantityNote: String?
    let labelUpdates: AddBottleRecord.LabelUpdates?
}

/// A bottle of a medication already tracked, added to its count.
struct AddBottleSheet: View {
    let request: AddBottleRequest
    /// Called once the bottle is saved, before the sheet closes.
    let onAdded: (Medication) -> Void
    @Query private var allMedications: [Medication]
    @Query private var allSchedules: [DoseSchedule]
    @Query private var allInventoryEvents: [InventoryEvent]
    @Query private var allDoseEvents: [DoseEvent]
    @Environment(\.modelContext) private var modelContext
    @State private var text = ""
    @State private var note = ""
    @State private var appliesLabelUpdates = true
    @State private var showingSaveError = false
    @State private var savedCount = 0
    /// Worked out once, as the sheet opens: saving writes these values to the
    /// medication, and the sheet should not redraw itself while it closes.
    @State private var labelChanges: AddBottleRecord.LabelUpdates?
    @State private var labelKept: [String]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(request: AddBottleRequest, onAdded: @escaping (Medication) -> Void) {
        self.request = request
        self.onAdded = onAdded
        let changes = request.labelUpdates?.changes(to: request.medication)
        _labelChanges = State(initialValue: changes?.isEmpty == false ? changes : nil)
        _labelKept = State(initialValue: request.labelUpdates?.kept(by: request.medication) ?? [])
    }

    private var medication: Medication { request.medication }

    /// Read from the text on every change, as the supply sheets are: the
    /// decimal pad has no Return key to commit a formatted field.
    private var quantity: Double? {
        SupplyChangeQuantity.value(from: text, prefilled: nil, requiresMoreThanZero: true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Quantity", text: $text)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.semibold))
                            .accessibilityLabel("Quantity in this bottle")
                            .accessibilityIdentifier("bottle-quantity")
                        Text(medication.form.unitText(for: quantity ?? 0))
                            .foregroundStyle(.secondary)
                    }
                    if let labelQuantity = request.labelQuantity, let labelQuantityNote = request.labelQuantityNote {
                        labelQuantityRow(quantity: labelQuantity, note: labelQuantityNote)
                    }
                    TextField("Optional note", text: $note, axis: .vertical)
                } header: {
                    Text("In this bottle")
                } footer: {
                    Text("Count what is in it now. It joins the count for \(medication.displayName), so skip this if the bottle was counted already.")
                }

                if let labelChanges {
                    Section {
                        Toggle(isOn: $appliesLabelUpdates) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(labelChanges.toggleTitle())
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(labelChanges.lines().joined(separator: "\n"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityIdentifier("apply-label-updates")
                    } footer: {
                        if !labelKept.isEmpty { keptText }
                    }
                } else if !labelKept.isEmpty {
                    Section { keptText.font(.subheadline) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add to \(medication.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Bottle") {
                        guard let quantity else { return }
                        if save(quantity: quantity) {
                            onAdded(medication)
                            dismiss()
                        } else {
                            showingSaveError = true
                        }
                    }
                    .disabled(quantity == nil)
                    .accessibilityIdentifier("save-bottle")
                }
            }
            .alert("Couldn't Add This Bottle", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Nothing was changed. Try again.")
            }
        }
        // At the accessibility sizes half a screen holds little more than the
        // field's title.
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .sensoryFeedback(.success, trigger: savedCount)
    }

    /// Records the bottle and replans every reminder, since a larger supply
    /// moves the low-supply date.
    private func save(quantity: Double) -> Bool {
        let event = AddBottleRecord.record(
            quantity: quantity,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            labelUpdates: appliesLabelUpdates ? request.labelUpdates : nil,
            to: medication,
            in: modelContext
        )
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return false
        }
        let plans = NotificationPlanBuilder.makeAll(
            medications: allMedications,
            schedules: allSchedules,
            inventoryEvents: allInventoryEvents.filter { $0.id != event.id } + [event],
            doseEvents: allDoseEvents
        )
        Task { await NotificationService.shared.replaceAllNotifications(for: plans) }
        savedCount += 1
        return true
    }

    private var keptText: some View {
        Text(labelKept.joined(separator: "\n"))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("label-values-kept")
    }

    /// The same offer the review screen makes: the label's count one tap away,
    /// with the reminder that it is what the bottle held when full.
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
            .accessibilityIdentifier("bottle-label-quantity-note")
            let quantityText = quantity.medicationQuantityText
            let isInUse = SupplyChangeQuantity.value(from: text, prefilled: nil, requiresMoreThanZero: true) == quantity
            Button {
                self.text = SupplyChangeQuantity.text(for: quantity)
            } label: {
                Text(isInUse ? "\(Image(systemName: "checkmark")) Using \(quantityText)" : "Use \(quantityText)")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isInUse)
            .accessibilityLabel(isInUse ? "Using \(quantityText) for this bottle" : "Use \(quantityText) for this bottle")
            .accessibilityIdentifier("bottle-use-label-quantity")
        }
        .padding(.vertical, 3)
    }
}
