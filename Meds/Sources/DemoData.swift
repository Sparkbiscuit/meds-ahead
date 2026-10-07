#if DEBUG
import Foundation
import SwiftData

enum DemoData {
    /// `backdatingSchedulesByDays` starts the demo schedules in the past so the
    /// unlogged-dose state has something to show. Left at zero the demo store looks
    /// exactly as it always has, which is what the UI tests expect of it.
    /// `countedWhenSchedulesStart` dates the opening counts back with them, so the
    /// forecast has that many days of unlogged doses since the count to assume.
    @MainActor
    static func seed(in context: ModelContext, backdatingSchedulesByDays days: Int = 0, countedWhenSchedulesStart: Bool = false) throws {
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

        // From the start of the day, not the moment of seeding: a schedule offers
        // no dose whose time had passed when it was saved, and the UI tests need
        // today's 08:00 and 20:00 doses whatever time of day they run.
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -days, to: .now) ?? .now)
        let countedAt = countedWhenSchedulesStart ? start : .now

        [furosemide, dimethyl, melatonin].forEach(context.insert)
        context.insert(InventoryEvent(medicationID: furosemide.id, date: countedAt, delta: 28, reason: .openingCount))
        context.insert(InventoryEvent(medicationID: dimethyl.id, date: countedAt, delta: 12, reason: .openingCount))
        context.insert(InventoryEvent(medicationID: melatonin.id, date: countedAt, delta: 118, reason: .openingCount))
        for medication in [furosemide, dimethyl] {
            context.insert(DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 8 * 60, doseQuantity: 1, startDate: start))
            context.insert(DoseSchedule(medicationID: medication.id, minutesAfterMidnight: 20 * 60, doseQuantity: 1, startDate: start))
        }
        try context.save()
    }

    /// A fictional antibiotic course beside the demo household: a capsule
    /// three times a day, its last day `lastDayInDays` from today. Running,
    /// it starts today with enough counted to see it through, so Supply,
    /// the detail screen and the editor show a course with an end. Given a
    /// last day already past, it ran five days with every dose logged, so
    /// Today offers the finished course's card.
    @MainActor
    static func seedCourse(in context: ModelContext, lastDayInDays: Int = 3) throws {
        let name = "Amoxicillin"
        guard try !context.fetch(FetchDescriptor<Medication>()).contains(where: { $0.name == name }) else { return }

        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        let lastDay = calendar.date(byAdding: .day, value: lastDayInDays, to: today) ?? today
        let finished = lastDay < today
        let start = finished ? calendar.date(byAdding: .day, value: -4, to: lastDay) ?? lastDay : today
        let amoxicillin = Medication(
            name: name,
            strength: "500 mg",
            form: .capsule,
            directions: "Take one capsule three times daily until finished",
            refillLeadDays: 3,
            accentIndex: 3,
            createdAt: start
        )
        context.insert(amoxicillin)
        // Counted now for the running course, as the demo's own counts are,
        // so the doses before now today are not assumed taken from it.
        context.insert(InventoryEvent(medicationID: amoxicillin.id, date: finished ? start : .now, delta: finished ? 18 : 15, reason: .openingCount))
        let end = ScheduleEngine.normalizedEndDate(forDay: lastDay, calendar: calendar)
        let schedules = [8, 14, 20].map {
            DoseSchedule(medicationID: amoxicillin.id, minutesAfterMidnight: $0 * 60, doseQuantity: 1, startDate: start, endDate: end)
        }
        schedules.forEach(context.insert)
        if finished {
            for dose in ScheduleEngine.doses(schedules: schedules, medicationID: amoxicillin.id, from: start,
                                             through: ScheduleEngine.courseLastMoment(end, calendar: calendar), calendar: calendar) {
                context.insert(DoseEvent(medicationID: amoxicillin.id, scheduleID: dose.scheduleID, scheduledAt: dose.date,
                                         recordedAt: dose.date, doseQuantity: dose.quantity, status: .taken))
            }
        }
        try context.save()
    }
}
#endif
