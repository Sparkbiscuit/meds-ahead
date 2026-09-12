import XCTest
@testable import Meds

final class ReviewRequestPolicyTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now)!
    }

    private func shouldRequest(
        firstUse: Date? = nil,
        takenDoses: Int = 10,
        lastRequest: Date? = nil,
        lastRequestedVersion: String? = nil,
        version: String = "1.1"
    ) -> Bool {
        ReviewRequestPolicy.shouldRequest(
            now: now,
            firstUse: firstUse ?? daysAgo(3),
            takenDoses: takenDoses,
            lastRequest: lastRequest,
            lastRequestedVersion: lastRequestedVersion,
            version: version,
            calendar: calendar
        )
    }

    func testAsksOnceTheThresholdsAreMet() {
        XCTAssertTrue(shouldRequest())
        XCTAssertTrue(shouldRequest(firstUse: daysAgo(400), takenDoses: 500))
    }

    func testNotBeforeAFewDaysOfUse() {
        XCTAssertFalse(shouldRequest(firstUse: now))
        XCTAssertFalse(shouldRequest(firstUse: daysAgo(2)))
        XCTAssertTrue(shouldRequest(firstUse: daysAgo(3)))
    }

    func testNotBeforeEnoughDosesWereLogged() {
        XCTAssertFalse(shouldRequest(takenDoses: 0))
        XCTAssertFalse(shouldRequest(takenDoses: 9))
        XCTAssertTrue(shouldRequest(takenDoses: 10))
    }

    func testNeverTwiceForOneVersion() {
        XCTAssertFalse(shouldRequest(lastRequest: daysAgo(300), lastRequestedVersion: "1.1"))
        XCTAssertTrue(shouldRequest(lastRequest: daysAgo(300), lastRequestedVersion: "1.0"))
    }

    func testNotMoreThanOnceASeason() {
        XCTAssertFalse(shouldRequest(lastRequest: daysAgo(119), lastRequestedVersion: "1.0"))
        XCTAssertTrue(shouldRequest(lastRequest: daysAgo(120), lastRequestedVersion: "1.0"))
    }

    @MainActor
    func testTheCoordinatorStartsItsClockOnFirstUseAndRemembersAnAsk() {
        let suite = "ReviewRequestPolicyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = ReviewRequestCoordinator(defaults: defaults, version: "1.1")

        XCTAssertFalse(coordinator.shouldRequestReview(takenDoses: 50, now: daysAgo(10)), "the first check only starts the clock")
        XCTAssertFalse(coordinator.shouldRequestReview(takenDoses: 50, now: daysAgo(9)))
        XCTAssertTrue(coordinator.shouldRequestReview(takenDoses: 50, now: daysAgo(7)))

        coordinator.recordRequest(now: daysAgo(7))
        XCTAssertFalse(coordinator.shouldRequestReview(takenDoses: 80, now: now), "same version, already asked")

        let nextVersion = ReviewRequestCoordinator(defaults: defaults, version: "1.2")
        XCTAssertFalse(nextVersion.shouldRequestReview(takenDoses: 80, now: now), "only a week has passed")
        XCTAssertTrue(nextVersion.shouldRequestReview(takenDoses: 80, now: calendar.date(byAdding: .day, value: 120, to: now)!))
    }
}
