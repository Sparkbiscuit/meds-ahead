import Foundation

/// The words that follow a number. Every surface used to add "s" to the form's
/// unit, which printed "30 patchs" and "150 mLs", so the plurals live here,
/// written out once, and every screen, export, reminder and widget asks for them.
extension MedicationForm {
    /// "1 tablet", "0.5 tablets", "30 patches", "150 mL".
    func quantityText(_ quantity: Double) -> String {
        "\(quantity.medicationQuantityText) \(unitText(for: quantity))"
    }

    /// The unit alone, for a label beside a number shown in a field.
    func unitText(for quantity: Double) -> String {
        quantity.printsAsOne ? unitName : pluralUnitName
    }

    /// Written out rather than derived: "patch" takes "es", and mL is a symbol,
    /// which never takes a plural.
    private var pluralUnitName: String {
        switch self {
        case .tablet: "tablets"
        case .capsule: "capsules"
        case .liquid: "mL"
        case .injection: "doses"
        case .inhaler: "puffs"
        case .patch: "patches"
        case .drops: "drops"
        case .topical: "applications"
        case .other: "units"
        }
    }
}

private extension Double {
    /// The singular follows the number as printed, not as stored: 1.004 prints
    /// as "1", and "1 tablets" beside it would read as a mistake. The same
    /// two-place rounding `medicationQuantityText` uses decides it, in a fixed
    /// locale so the region's digits and separators cannot change the answer.
    var printsAsOne: Bool {
        self == 1 || formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US_POSIX"))) == "1"
    }
}

extension Int {
    /// "1 day", "2 days".
    var dayCountText: String { counted("day", plural: "days") }

    /// A count of whole things with its noun: "1 reminder", "3 reminders".
    func counted(_ singular: String, plural: String) -> String {
        self == 1 ? "1 \(singular)" : "\(self) \(plural)"
    }
}
