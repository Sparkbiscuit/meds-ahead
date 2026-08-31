import XCTest
@testable import Meds

final class TimeOfDayGreetingTests: XCTestCase {
    func testGreetingChangesAcrossTheDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let expectations: [(hour: Int, greeting: String)] = [
            // The small hours are their own band. They used to fall through to the
            // evening branch, so opening the app at three in the morning to log a
            // dose was greeted with "Good evening".
            (0, "Good night"),
            (3, "Good night"),
            (4, "Good night"),
            (5, "Good morning"),
            (11, "Good morning"),
            (12, "Good afternoon"),
            (17, "Good afternoon"),
            (18, "Good evening"),
            (21, "Good evening"),
            (22, "Good night"),
            (23, "Good night")
        ]

        for expectation in expectations {
            let date = try XCTUnwrap(
                calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: expectation.hour))
            )
            XCTAssertEqual(
                TimeOfDayGreeting.text(for: date, calendar: calendar),
                expectation.greeting,
                "Unexpected greeting at hour \(expectation.hour)"
            )
        }
    }
}
