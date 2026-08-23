import Foundation

struct ScheduledDose: Identifiable, Equatable {
    let id: String
    let medicationID: UUID
    let scheduleID: UUID
    let date: Date
    let quantity: Double

    init(medicationID: UUID, scheduleID: UUID, date: Date, quantity: Double) {
        self.medicationID = medicationID
        self.scheduleID = scheduleID
        self.date = date
        self.quantity = quantity
        self.id = "\(scheduleID.uuidString)-\(date.timeIntervalSince1970)"
    }
}

enum DoseTimingState: Equatable {
    case upcoming
    case due
    case overdue
}

enum ScheduleEngine {
    static func timingState(
        for scheduledAt: Date,
        now: Date = .now,
        dueWindow: TimeInterval = 30 * 60
    ) -> DoseTimingState {
        if scheduledAt < now.addingTimeInterval(-dueWindow) {
            return .overdue
        }
        if scheduledAt <= now.addingTimeInterval(dueWindow) {
            return .due
        }
        return .upcoming
    }

    static func isActive(
        _ schedule: DoseSchedule,
        on day: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        let start = calendar.startOfDay(for: schedule.startDate)
        let target = calendar.startOfDay(for: day)
        guard target >= start else { return false }
        if let endDate = schedule.endDate,
           target > calendar.startOfDay(for: endDate) {
            return false
        }
        let weekday = calendar.component(.weekday, from: target) - 1
        return schedule.weekdayMask & (1 << weekday) != 0
    }

    static func scheduledDate(
        for schedule: DoseSchedule,
        on day: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        guard isActive(schedule, on: day, calendar: calendar) else { return nil }
        let hour = schedule.minutesAfterMidnight / 60
        let minute = schedule.minutesAfterMidnight % 60
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    static func doses(
        schedules: [DoseSchedule],
        medicationID: UUID,
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [ScheduledDose] {
        guard startDate <= endDate else { return [] }
        var results: [ScheduledDose] = []
        var day = calendar.startOfDay(for: startDate)
        let lastDay = calendar.startOfDay(for: endDate)

        while day <= lastDay {
            for schedule in schedules where schedule.medicationID == medicationID {
                guard let date = scheduledDate(for: schedule, on: day, calendar: calendar),
                      date >= startDate,
                      date <= endDate else { continue }
                results.append(
                    ScheduledDose(
                        medicationID: medicationID,
                        scheduleID: schedule.id,
                        date: date,
                        quantity: schedule.doseQuantity
                    )
                )
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return results.sorted { $0.date < $1.date }
    }
}
