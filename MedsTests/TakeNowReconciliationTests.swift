import XCTest
@testable import Meds

/// Take Now on a medication and Taken on Today's card must be able to claim the same
/// dose, or the same dose gets logged twice and the supply is spent twice over.
final class TakeNowReconciliationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func morningAndEvening(medicationID: UUID, day: Date) -> [DoseSchedule] {
        [
            DoseSchedule(
                medicationID: medicationID,
                minutesAfterMidnight: 8 * 60,
                doseQuantity: 1,
                startDate: day
            ),
            DoseSchedule(
                medicationID: medicationID,
                minutesAfterMidnight: 21 * 60,
                doseQuantity: 2,
                startDate: day
            )
        ]
    }

    func testTakeNowClaimsTheDoseTodayIsOffering() throws {
        let medicationID = UUID()
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 24)))
        let now = try XCTUnwrap(calendar.date(byAdding: .minute, value: 8 * 60 + 2, to: day))
        let schedules = morningAndEvening(medicationID: medicationID, day: day)

        let claimed = try XCTUnwrap(
            ScheduleEngine.actionableDose(
                schedules: schedules,
                medicationID: medicationID,
                doseEvents: [],
                now: now,
                calendar: calendar
            )
        )

        XCTAssertEqual(claimed.scheduleID, schedules[0].id)
        XCTAssertEqual(claimed.quantity, 1)
        XCTAssertEqual(calendar.component(.hour, from: claimed.date), 8)
    }

    func testAClaimedDoseIsNotOfferedTwice() throws {
        let medicationID = UUID()
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 24)))
        let now = try XCTUnwrap(calendar.date(byAdding: .minute, value: 8 * 60 + 2, to: day))
        let schedules = morningAndEvening(medicationID: medicationID, day: day)
        let claimed = try XCTUnwrap(
            ScheduleEngine.actionableDose(
                schedules: schedules,
                medicationID: medicationID,
                doseEvents: [],
                now: now,
                calendar: calendar
            )
        )
        let logged = DoseEvent(
            medicationID: medicationID,
            scheduleID: claimed.scheduleID,
            scheduledAt: claimed.date,
            doseQuantity: claimed.quantity,
            status: .taken
        )

        XCTAssertEqual(ScheduleEngine.loggedStatus(for: claimed, in: [logged]), .taken)
        XCTAssertNil(
            ScheduleEngine.actionableDose(
                schedules: schedules,
                medicationID: medicationID,
                doseEvents: [logged],
                now: now,
                calendar: calendar
            ),
            "the evening dose is still upcoming, so nothing else is actionable yet"
        )
    }

    func testAnUnscheduledLogUsesTheNearestScheduleAmount() throws {
        let medicationID = UUID()
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 24)))
        let schedules = morningAndEvening(medicationID: medicationID, day: day)
        let evening = try XCTUnwrap(calendar.date(byAdding: .minute, value: 20 * 60 + 45, to: day))
        let morning = try XCTUnwrap(calendar.date(byAdding: .minute, value: 7 * 60 + 50, to: day))

        XCTAssertEqual(
            ScheduleEngine.nearestScheduledQuantity(
                schedules: schedules,
                medicationID: medicationID,
                now: evening,
                calendar: calendar
            ),
            2,
            "reaching for the first schedule would log the morning's single tablet"
        )
        XCTAssertEqual(
            ScheduleEngine.nearestScheduledQuantity(
                schedules: schedules,
                medicationID: medicationID,
                now: morning,
                calendar: calendar
            ),
            1
        )
    }

    func testNearestScheduleMeasuresTheShortWayAroundMidnight() throws {
        let medicationID = UUID()
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 24)))
        let schedules = [
            DoseSchedule(medicationID: medicationID, minutesAfterMidnight: 23 * 60 + 30, doseQuantity: 3, startDate: day),
            DoseSchedule(medicationID: medicationID, minutesAfterMidnight: 9 * 60, doseQuantity: 1, startDate: day)
        ]
        let justAfterMidnight = try XCTUnwrap(calendar.date(byAdding: .minute, value: 10, to: day))

        XCTAssertEqual(
            ScheduleEngine.nearestScheduledQuantity(
                schedules: schedules,
                medicationID: medicationID,
                now: justAfterMidnight,
                calendar: calendar
            ),
            3,
            "00:10 is forty minutes from 23:30 and nine hours from 09:00"
        )
    }

    func testMissedDosesFromEarlierDaysAreStillFindable() throws {
        let medicationID = UUID()
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 22)))
        let schedule = DoseSchedule(
            medicationID: medicationID,
            minutesAfterMidnight: 21 * 60,
            doseQuantity: 1,
            startDate: start
        )
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 7)))
        let startOfToday = calendar.startOfDay(for: today)
        let lookback = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: startOfToday))

        let earlier = ScheduleEngine.doses(
            schedules: [schedule],
            medicationID: medicationID,
            from: lookback,
            through: startOfToday.addingTimeInterval(-1),
            calendar: calendar
        )

        XCTAssertEqual(earlier.count, 2, "the two evenings before today")
        XCTAssertTrue(earlier.allSatisfy { ScheduleEngine.loggedStatus(for: $0, in: []) == nil })
    }
}
