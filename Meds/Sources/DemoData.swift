#if DEBUG
import Foundation
import SwiftData

enum DemoData {
    @MainActor
    static func seed(in context: ModelContext) throws {
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

        for medication in [furosemide, dimethyl] {
            context.insert(DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, doseQuantity: 1))
            context.insert(DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 20 * 60, doseQuantity: 1))
        }
        try context.save()
    }
}
#endif
