import XCTest

final class MedsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testManualMedicationCriticalFlow() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-skip-onboarding",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["manual-entry"].waitForExistence(timeout: 3))
        app.buttons["manual-entry"].tap()

        let name = app.textFields["medication-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Test Medication")

        let supply = app.textFields["current-supply"]
        for _ in 0..<4 where !supply.exists {
            app.swipeUp()
        }
        XCTAssertTrue(supply.waitForExistence(timeout: 3))
        supply.tap()
        supply.typeText("30")

        app.buttons["save-medication"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Supply"].tap()
        XCTAssertTrue(app.staticTexts["Test Medication"].waitForExistence(timeout: 3))
    }

    func testOnboardingCanBeCompleted() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-show-onboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 3))
        app.buttons["Continue"].tap()
        app.buttons["Continue"].tap()
        app.buttons["Get Started"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
    }

    func testTodayAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-skip-onboarding",
            "-seed-demo-data",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL"
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: [
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
            .textClipped,
            .trait
        ])
    }

    func testMedicationEditorAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-skip-onboarding"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["manual-entry"].waitForExistence(timeout: 3))
        app.buttons["manual-entry"].tap()
        XCTAssertTrue(app.navigationBars["Add Medication"].waitForExistence(timeout: 3))

        let sampleValues = [
            (app.textFields["medication-name"], "Example"),
            (app.textFields["Strength"], "20 mg"),
            (app.textFields["Nickname"], "Morning"),
            (app.textFields["Label directions"], "Take as directed")
        ]
        for (field, value) in sampleValues where field.exists {
            field.tap()
            field.typeText(value)
        }
        app.navigationBars["Add Medication"].staticTexts["Add Medication"].tap()

        try app.performAccessibilityAudit(for: [
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
            .trait
        ])
    }

    func testMedicationEditorAtLargestAccessibilityText() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-skip-onboarding",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["manual-entry"].waitForExistence(timeout: 3))
        app.buttons["manual-entry"].tap()

        let amountLabel = app.staticTexts["Amount per dose"]
        for _ in 0..<6 where !amountLabel.exists {
            app.swipeUp()
        }
        XCTAssertTrue(amountLabel.exists)
        XCTAssertTrue(app.buttons["Sunday"].exists)
        XCTAssertTrue(app.buttons["Saturday"].exists)
    }

    /// The tip entry point must never vanish. When StoreKit returns nothing — the
    /// usual situation in the simulator and a common sandbox hiccup during review —
    /// the row has to stay put and say so, or App Review reports that it could not
    /// locate the in-app purchases.
    func testTipEntryPointIsAlwaysPresentInSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-skip-onboarding"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        XCTAssertTrue(
            app.staticTexts["Support Meds Ahead"].waitForExistence(timeout: 5),
            "the tip section header is missing entirely"
        )

        // Exactly one of the three states must be on screen, never none of them.
        let offer = app.buttons["Leave an Optional Tip"]
        let loading = app.staticTexts["Leave an Optional Tip"]
        let unavailable = app.staticTexts["Tips Are Unavailable"]

        let resolved = offer.waitForExistence(timeout: 8)
            || unavailable.waitForExistence(timeout: 8)
            || loading.exists
        XCTAssertTrue(resolved, "no tip row of any kind was shown in Settings")
    }

    func testOverdueDoseStateIsVisibleAndAccessible() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-skip-onboarding",
            "-seed-demo-data",
            "-force-overdue-dose-state"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        let overdueState = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Overdue")
        ).firstMatch
        XCTAssertTrue(overdueState.waitForExistence(timeout: 3))
    }
}
