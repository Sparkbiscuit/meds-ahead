import SwiftUI

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

    /// The number Correct Count opens with: the ledger's, or nothing while the
    /// forecast assumes unlogged doses were taken, whether or not they use up
    /// the ledger yet. Prefilled then, one tap on Save would record a count
    /// nobody made, clear the doses the forecast had to assume, and move the
    /// run-out date later.
    static func countPrefill(for forecast: SupplyForecast) -> Double? {
        forecast.needsCount || forecast.assumedDoses > 0 ? nil : forecast.currentSupply
    }

    static func value(
        from text: String,
        prefilled: Double?,
        requiresMoreThanZero: Bool,
        locale: Locale = .autoupdatingCurrent
    ) -> Double? {
        let value: Double
        if let prefilled, text == Self.text(for: prefilled, locale: locale) {
            // The prefilled text is rounded to two places. Left untouched it stands
            // for the exact number it was made from, so an unchanged count is
            // recorded as a zero correction ("Count confirmed") rather than as
            // the rounding's difference.
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

struct SupplyChangeSheet: View {
    let title: String
    let message: String
    let form: MedicationForm
    /// Nil opens the field empty.
    let initialValue: Double?
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
        form: MedicationForm,
        initialValue: Double?,
        actionTitle: String,
        onSave: @escaping (Double, String) -> Void
    ) {
        self.title = title
        self.message = message
        self.form = form
        self.initialValue = initialValue
        self.actionTitle = actionTitle
        self.onSave = onSave
        _text = State(initialValue: initialValue.map { SupplyChangeQuantity.text(for: $0) } ?? "")
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
                        Text(form.unitText(for: quantity ?? 0))
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
