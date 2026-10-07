import Foundation

/// The notes a dose logged away from Today carries into the ledger. They are
/// stored words, not copy: `HealthDoseReconciler` tells a dose logged here from
/// Health's copy of one by its note, and every event already saved keeps the
/// words it was saved with. Changing one is a migration of stored history.
/// Health's own note, `DoseEvent.appleHealthNote`, lives with the model.
enum DoseEventNote {
    /// A dose marked Taken or Skipped from a reminder's actions.
    static let reminder = "Logged from reminder"
    /// A dose marked Taken from the next-dose widget.
    static let widget = "Logged from widget"
}
