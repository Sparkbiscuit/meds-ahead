#if DEBUG
import Foundation
import SwiftData

enum DemoData {
    /// `backdatingSchedulesByDays` starts the demo schedules in the past so the
    /// unlogged-dose state has something to show. Left at zero the demo store looks
    /// exactly as it always has, which is what the UI tests expect of it.
    @MainActor
    static func seed(in context: ModelContext, backdatingSchedulesByDays days: Int = 0) throws {
        let descriptor = FetchDescriptor<Medication>()
        guard try context.fetchCount(descriptor) == 0 else { return }

        let furosemide = Medication(
            name: "Furosemide",
            strength: "20 mg",
            form: .tablet,
            directions: "Take one tablet twice daily",
            refillsRemaining: 2,
            refillLeadDays: 7,
            accentIndex: 0
        )
        let dimethyl = Medication(
            name: "Dimethyl fumarate",
            strength: "240 mg",
            form: .capsule,
            directions: "Take one capsule twice daily",
            refillsRemaining: 0,
            refillLeadDays: 10,
            accentIndex: 2
        )
        let melatonin = Medication(
            name: "Melatonin",
            strength: "5 mg",
            form: .tablet,
            directions: "Take as needed",
            refillLeadDays: 14,
            accentIndex: 4,
            isAsNeeded: true,
            remindersEnabled: false
        )

        [furosemide, dimethyl, melatonin].forEach(context.insert)
        context.insert(InventoryEvent(medicationID: furosemide.id, delta: 28, reason: .openingCount))
        context.insert(InventoryEvent(medicationID: dimethyl.id, delta: 12, reason: .openingCount))
        context.insert(InventoryEvent(medicationID: melatonin.id, delta: 118, reason: .openingCount))

        let start = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -days, to: .now) ?? .now
        for medication in [furosemide, dimethyl] {
            context.insert(DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, doseQuantity: 1, startDate: start))
            context.insert(DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 20 * 60, doseQuantity: 1, startDate: start))
        }
        try context.save()
    }
}
#endif
