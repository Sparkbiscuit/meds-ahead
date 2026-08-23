import XCTest

final class MedsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testManualMedicationCriticalFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-skip-onboarding"]
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
        app.launchArguments = ["-ui-testing", "-skip-onboarding", "-seed-demo-data"]
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
}
