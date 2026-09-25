#if DEBUG
import XCTest
@testable import Meds

/// What a launch for a UI test clears first. The simulator keeps
/// UserDefaults between runs, so a choice or a set-aside card one run left
/// behind would decide what the next run's test sees.
final class UITestingLaunchTests: XCTestCase {
    func testAUITestLaunchStartsFromWhatANewInstallHas() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "UITestingLaunchTests.\(UUID().uuidString)"))
        let medicationID = UUID()
        let now = Date.now
        // What a run stopped midway can leave: both reminder choices turned
        // away from where they start, a count check planned and asked, and
        // each of Today's cards set aside or tapped through.
        defaults.set(true, forKey: NotificationPlanOptions.followUpRemindersKey)
        defaults.set(false, forKey: NotificationPlanOptions.weeklyCountCheckKey)
        CountCheckPolicy.remember(planned: now.addingTimeInterval(-60), now: now, in: defaults)
        CountCheckPolicy.remember(planned: now.addingTimeInterval(3600), now: now, in: defaults)
        defaults.set(FinishedCourseNotice.adding(FinishedCourseNotice.key(medicationID: medicationID, end: now), to: "", now: now),
                     forKey: FinishedCourseNotice.setAsideKey)
        defaults.set(QuickCountPrompt.encodeSetAside([medicationID: now]), forKey: QuickCountPrompt.setAsideKey)
        QuickCountPrompt.rememberTap(of: medicationID, at: now, in: defaults)
        // The quick count's UI tests need the missed-doses card it points at.
        defaults.set("2026-9-25", forKey: TodayView.missedDosesSetAsideKey)
        defaults.set(true, forKey: "hasCompletedOnboarding")
        for key in MedsAppDelegate.uiTestingDefaultsKeys {
            XCTAssertNotNil(defaults.object(forKey: key), "why: \(key) was left by the run before")
        }

        MedsAppDelegate.clearUITestingDefaults(in: defaults)

        for key in MedsAppDelegate.uiTestingDefaultsKeys {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
        let options = NotificationPlanOptions.stored(in: defaults, now: now)
        XCTAssertFalse(options.followUpReminders, "follow-ups start off")
        XCTAssertTrue(options.weeklyCountCheck, "the weekly count check starts on")
        XCTAssertNil(options.lastCountCheck)
        XCTAssertTrue(FinishedCourseNotice.setAside(in: defaults.string(forKey: FinishedCourseNotice.setAsideKey) ?? "").isEmpty)
        XCTAssertTrue(QuickCountPrompt.decodeSetAside(defaults.data(forKey: QuickCountPrompt.setAsideKey) ?? Data()).isEmpty)
        XCTAssertNil(QuickCountPrompt.decodeTap(defaults.data(forKey: QuickCountPrompt.tapKey) ?? Data()))
        XCTAssertNil(defaults.string(forKey: TodayView.missedDosesSetAsideKey), "the missed doses are not set aside")
        XCTAssertTrue(defaults.bool(forKey: "hasCompletedOnboarding"), "only what a test run can change is cleared")
    }
}
#endif
