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
        // Walk to the end however many pages there are, so adding one does not
        // silently turn this into a test of nothing.
        for _ in 0..<12 where app.buttons["Continue"].exists {
            app.buttons["Continue"].tap()
        }
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: 3))
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
        // The keyboard stays up after the last field; tapping the title never
        // lowered it. On iOS 27 the audit then reports "potentially
        // inaccessible text" without naming an element, and passes once the
        // keyboard is down: it was reading the keyboard, not the editor. So
        // the keyboard is dragged away first, as a person would.
        let form = app.collectionViews.firstMatch
        form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "the keyboard would be audited instead of the editor")

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
            "UICTContentSizeCategoryAccessibilityXXXL"
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

    /// A scanned draft must survive the hand-off into the review screen. The
    /// overlay saying it found a name, strength and quantity is worthless if the
    /// editor then opens blank. The quantity is the exception on purpose: a
    /// label's count is what the bottle held when full, so it is offered, not
    /// filled in.
    func testScannedDraftPopulatesTheReviewScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-skip-onboarding", "-simulate-scan-result"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Add"].tap()

        let name = app.textFields["medication-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "review screen never appeared")
        XCTAssertEqual(name.value as? String, "Amphetamine", "medication name did not carry over")

        let strength = app.textFields["Strength"]
        XCTAssertTrue(strength.exists)
        XCTAssertEqual(strength.value as? String, "20 mg", "strength did not carry over")

        let supply = app.textFields["current-supply"]
        let useLabelQuantity = app.buttons["use-label-quantity"]
        for _ in 0..<4 where !useLabelQuantity.isHittable { app.swipeUp() }
        let startingAmount = supply.value as? String ?? ""
        XCTAssertTrue(
            startingAmount.isEmpty || startingAmount == supply.placeholderValue,
            "the label's dispensed count was filled in as the current amount: \(startingAmount)"
        )
        let note = app.descendants(matching: .any)["label-quantity-note"]
        XCTAssertTrue(note.exists)
        XCTAssertTrue(note.label.hasPrefix("Label says 60 when full"), note.label)

        // Blank is still not zero: Add asks for the amount, as it does for any draft.
        app.buttons["save-medication"].tap()
        XCTAssertTrue(app.alerts["A little more information is needed"].waitForExistence(timeout: 3))
        app.alerts.buttons["OK"].tap()

        XCTAssertEqual(useLabelQuantity.label, "Use 60 as the current amount")
        useLabelQuantity.tap()
        XCTAssertEqual(supply.value as? String, "60", "Use 60 did not fill the current amount")
        XCTAssertEqual(useLabelQuantity.label, "Using 60 as the current amount")
        XCTAssertFalse(useLabelQuantity.isEnabled)
    }

    /// At the largest text size Current amount has scrolled away by the time the
    /// label's count is on screen, so the button, and its Using state, are the
    /// only way to fill the field and see that it worked.
    func testScannedLabelQuantityAtLargestAccessibilityText() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-skip-onboarding",
            "-simulate-scan-result",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Add"].tap()
        // At this size the scan summary fills the first screen, so the name field
        // has not been built yet; the navigation bar is what shows the review
        // screen opened.
        XCTAssertTrue(app.navigationBars["Review Medication"].waitForExistence(timeout: 5), "review screen never appeared")

        let useLabelQuantity = app.buttons["use-label-quantity"]
        for _ in 0..<10 where !useLabelQuantity.isHittable { app.swipeUp() }
        XCTAssertTrue(useLabelQuantity.isHittable, "the label's count cannot be reached at the largest text size")
        XCTAssertEqual(useLabelQuantity.label, "Use 60 as the current amount")
        try app.performAccessibilityAudit(for: [
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
            .trait
        ])

        useLabelQuantity.tap()
        XCTAssertEqual(useLabelQuantity.label, "Using 60 as the current amount")
        XCTAssertFalse(useLabelQuantity.isEnabled)
        let supply = app.textFields["current-supply"]
        for _ in 0..<4 where !supply.isHittable { app.swipeDown() }
        XCTAssertEqual(supply.value as? String, "60", "Use 60 did not fill the current amount")
    }

    func testLogAllDueRecordsEveryDueDose() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-skip-onboarding",
            "-seed-demo-data",
            "-force-overdue-dose-state"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        let logAll = app.buttons["log-all-due"]
        XCTAssertTrue(logAll.waitForExistence(timeout: 3), "the log-all shortcut never appeared")
        logAll.tap()

        let confirm = app.buttons["Mark All Taken"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3), "the confirmation dialog never appeared")
        confirm.tap()

        XCTAssertTrue(app.staticTexts["All logged"].waitForExistence(timeout: 5))
        XCTAssertFalse(logAll.exists, "the shortcut should disappear once nothing is due")
    }

    /// The number typed into a supply sheet is the number recorded, even when
    /// the sheet's button is tapped with the keyboard still up. The decimal pad
    /// has no Return key, so nothing but the button ever commits the field.
    func testRefillAndCountSheetsRecordTheTypedNumber() {
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
        app.tabBars.buttons["Supply"].tap()
        let row = app.staticTexts["Furosemide"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        XCTAssertTrue(app.staticTexts["28 on hand"].waitForExistence(timeout: 3))

        let quantity = app.textFields["supply-quantity"]
        func replaceQuantity(with text: String) {
            XCTAssertTrue(quantity.waitForExistence(timeout: 3))
            quantity.tap()
            let existing = (quantity.value as? String) ?? ""
            quantity.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 2))
            quantity.typeText(text)
        }

        app.buttons["supply-actions"].tap()
        XCTAssertTrue(app.buttons["Add Refill"].waitForExistence(timeout: 3))
        app.buttons["Add Refill"].tap()
        // The button follows the text as typed: a refill of nothing is refused.
        replaceQuantity(with: "0")
        XCTAssertFalse(app.buttons["Add Refill"].isEnabled, "a refill must be more than nothing")
        replaceQuantity(with: "90")
        app.buttons["Add Refill"].tap()
        XCTAssertTrue(app.staticTexts["118 on hand"].waitForExistence(timeout: 3), "the typed refill, not the suggested one")

        app.buttons["supply-actions"].tap()
        XCTAssertTrue(app.buttons["Correct Count"].waitForExistence(timeout: 3))
        app.buttons["Correct Count"].tap()
        replaceQuantity(with: "0")
        XCTAssertTrue(app.buttons["Save Count"].isEnabled, "an empty bottle is a real count")
        replaceQuantity(with: "100")
        app.buttons["Save Count"].tap()
        XCTAssertTrue(app.staticTexts["100 on hand"].waitForExistence(timeout: 3), "the typed count, not the one the sheet opened with")
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

    /// Counting and finding the number the app already shows is still a count:
    /// it is recorded, and it is what ends "Count needed" when doses really were
    /// not taken. Restoring an archived medication asks for a count, since
    /// nothing could be logged while it was archived.
    func testAMatchingCountIsRecordedAndARestoreAsksForOne() {
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
        app.tabBars.buttons["Supply"].tap()
        let row = app.staticTexts["Furosemide"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        XCTAssertTrue(app.staticTexts["28 on hand"].waitForExistence(timeout: 3))

        app.buttons["supply-actions"].tap()
        XCTAssertTrue(app.buttons["Correct Count"].waitForExistence(timeout: 3))
        app.buttons["Correct Count"].tap()
        XCTAssertTrue(app.buttons["Save Count"].waitForExistence(timeout: 3))
        app.buttons["Save Count"].tap()
        let confirmed = app.staticTexts["Count confirmed"]
        for _ in 0..<6 where !confirmed.exists {
            app.swipeUp()
        }
        XCTAssertTrue(confirmed.waitForExistence(timeout: 3), "the unchanged count is recorded")

        app.buttons["Medication actions"].tap()
        XCTAssertTrue(app.buttons["Archive Medication"].waitForExistence(timeout: 3))
        app.buttons["Archive Medication"].tap()
        app.tabBars.buttons["Medications"].tap()
        XCTAssertTrue(app.buttons["Show Archived"].waitForExistence(timeout: 3))
        app.buttons["Show Archived"].tap()
        let archived = app.staticTexts["Furosemide"]
        XCTAssertTrue(archived.waitForExistence(timeout: 3))
        archived.tap()
        XCTAssertTrue(app.buttons["Medication actions"].waitForExistence(timeout: 3))
        app.buttons["Medication actions"].tap()
        XCTAssertTrue(app.buttons["Restore Medication"].waitForExistence(timeout: 3))
        app.buttons["Restore Medication"].tap()
        XCTAssertTrue(app.buttons["Save Count"].waitForExistence(timeout: 3), "a restore asks what is on hand")
    }

    /// Every dose for sixteen days went unlogged, so the forecast is assuming
    /// them and the ledger's number cannot be vouched for. The Supply row that
    /// asks for a count says so to VoiceOver once, not three times.
    func testACountNeededIsSaidOnceOnItsSupplyRow() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-skip-onboarding",
            "-seed-demo-data",
            "-seed-stale-count",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Supply"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Furosemide")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertEqual(row.label.components(separatedBy: "Count needed").count - 1, 1, row.label)
        XCTAssertTrue(row.label.contains("on record"), row.label)
    }

    /// Every dose for sixteen days went unlogged, and the forecast is assuming
    /// them. Dropping a dose time rewrites what those days held, so the edit
    /// asks for a count, on an empty field, and the count is what the forecast
    /// then goes by.
    func testAScheduleEditOverUnloggedDosesAsksForACount() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-skip-onboarding",
            "-seed-demo-data",
            "-seed-stale-count",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Supply"].tap()
        let row = app.staticTexts["Furosemide"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        XCTAssertTrue(app.buttons["Medication actions"].waitForExistence(timeout: 3))
        app.buttons["Medication actions"].tap()
        XCTAssertTrue(app.buttons["Edit Medication"].waitForExistence(timeout: 3))
        app.buttons["Edit Medication"].tap()
        let remove = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Remove ")).firstMatch
        for _ in 0..<6 where !(remove.exists && remove.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(remove.isHittable)
        remove.tap()
        app.navigationBars["Edit Medication"].buttons["Save"].tap()

        XCTAssertTrue(app.navigationBars["Correct Current Count"].waitForExistence(timeout: 5), "the edit asks what is on hand")
        XCTAssertFalse(app.buttons["Save Count"].isEnabled, "nothing is filled in to confirm with one tap")
        let quantity = app.textFields["supply-quantity"]
        XCTAssertEqual((quantity.value as? String) ?? "", quantity.placeholderValue ?? "", "the field opens empty")
        quantity.tap()
        quantity.typeText("20")
        XCTAssertTrue(app.buttons["Save Count"].isEnabled)
        app.buttons["Save Count"].tap()
        XCTAssertTrue(app.staticTexts["20 on hand"].waitForExistence(timeout: 3))
    }

    /// When dated reminders run out within a few days, Today says so and says
    /// what keeps them coming, readably at the largest text sizes.
    func testThePlannedThroughNoticeIsShownAndAccessible() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-skip-onboarding",
            "-force-planned-through-notice",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXL"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        let notice = app.descendants(matching: .any)["planned-through-notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "the notice never appeared")
        XCTAssertTrue(notice.label.hasPrefix("Reminders are planned through "), notice.label)
        XCTAssertTrue(notice.label.hasSuffix("Open Meds Ahead before then to keep them coming."), notice.label)
        try app.performAccessibilityAudit(for: [
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
            .textClipped,
            .trait
        ])
    }

    /// A second reminder is opt-in, and Settings says what it does and what
    /// it cannot know about a dose given from another phone. The weekly count
    /// check is on until turned off.
    func testReminderChoicesInSettingsStartWhereTheyShould() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-skip-onboarding"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let followUps = app.switches["follow-up-reminders"]
        XCTAssertTrue(followUps.waitForExistence(timeout: 3))
        XCTAssertEqual(followUps.value as? String, "0", "off unless someone chooses it")
        let footer = app.staticTexts.matching(NSPredicate(format: "label == %@", "A second reminder 30 minutes after a dose time if it isn't logged on this phone. If more than one person gives doses, check with each other first."))
        XCTAssertEqual(footer.count, 1, "the footer says what it does and what it cannot know")

        let countCheck = app.switches["weekly-count-check"]
        XCTAssertTrue(countCheck.exists)
        XCTAssertEqual(countCheck.value as? String, "1", "on unless someone turns it off")

        // The app clears these choices when it starts for a UI test, so a run
        // stopped here leaves nothing behind for the next.
        followUps.switches.firstMatch.tap()
        XCTAssertEqual(followUps.value as? String, "1")
        followUps.switches.firstMatch.tap()
        XCTAssertEqual(followUps.value as? String, "0")
        countCheck.switches.firstMatch.tap()
        XCTAssertEqual(countCheck.value as? String, "0")
        countCheck.switches.firstMatch.tap()
        XCTAssertEqual(countCheck.value as? String, "1")
    }

    /// A second bottle of a medication already tracked goes into that one's
    /// count instead of becoming a second medication with its own reminders.
    /// The review says so, the bottle is recorded as a refill, and the flow
    /// goes back to the scanner for the next bottle.
    func testScanningABottleAlreadyTrackedAddsItToThatMedication() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-skip-onboarding",
            "-seed-demo-data",
            "-simulate-scan-result",
            "-simulate-scan-name", "Furosemide",
            "-simulate-scan-strength", "20 mg",
            "-simulate-scan-quantity", "30",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Add"].tap()
        let banner = app.descendants(matching: .any)["duplicate-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "the review never said Furosemide is already here")
        XCTAssertTrue(banner.label.contains("Already in Meds Ahead: Furosemide 20 mg"), banner.label)
        let addToExisting = app.buttons["add-to-existing"]
        XCTAssertEqual(addToExisting.label, "Add this bottle to Furosemide")
        addToExisting.tap()

        let quantity = app.textFields["bottle-quantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 3))
        XCTAssertEqual((quantity.value as? String) ?? "", quantity.placeholderValue ?? "", "the bottle's count starts empty")
        XCTAssertFalse(app.buttons["save-bottle"].isEnabled, "nothing to add yet")
        let note = app.descendants(matching: .any)["bottle-label-quantity-note"]
        XCTAssertTrue(note.label.hasPrefix("Label says 30 when full"), note.label)
        app.buttons["bottle-use-label-quantity"].tap()
        XCTAssertEqual(quantity.value as? String, "30")
        app.buttons["save-bottle"].tap()

        let tally = app.descendants(matching: .any)["setup-tally"]
        XCTAssertTrue(tally.waitForExistence(timeout: 5), "the flow did not go back to the scanner")
        XCTAssertEqual(tally.label, "Added to Furosemide")
        app.buttons["setup-done"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Supply"].tap()
        let row = app.staticTexts["Furosemide"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Furosemide").count, 1, "a second Furosemide was created")
        row.tap()
        XCTAssertTrue(app.staticTexts["58 on hand"].waitForExistence(timeout: 3), "28 on hand plus the bottle's 30")
        let refill = app.staticTexts["Refill added: +30"]
        for _ in 0..<6 where !refill.exists {
            app.swipeUp()
        }
        XCTAssertTrue(refill.exists, "the bottle is not in the activity")
    }

    /// At the largest text size the banner, its button, the bottle sheet and
    /// the bar under the camera are all still reachable and described.
    func testAddingABottleToATrackedMedicationAtLargestAccessibilityText() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-skip-onboarding",
            "-seed-demo-data",
            "-simulate-scan-result",
            "-simulate-scan-name", "Furosemide",
            "-simulate-scan-strength", "20 mg",
            "-simulate-scan-quantity", "30",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Add"].tap()
        let addToExisting = app.buttons["add-to-existing"]
        XCTAssertTrue(addToExisting.waitForExistence(timeout: 5))
        XCTAssertTrue(addToExisting.isHittable, "the banner's button is out of reach")
        try app.performAccessibilityAudit(for: [
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
            .trait
        ])

        addToExisting.tap()
        let useLabelQuantity = app.buttons["bottle-use-label-quantity"]
        XCTAssertTrue(useLabelQuantity.waitForExistence(timeout: 3))
        for _ in 0..<6 where !useLabelQuantity.isHittable { app.swipeUp() }
        XCTAssertTrue(useLabelQuantity.isHittable, "the label's count cannot be reached at the largest text size")
        useLabelQuantity.tap()
        XCTAssertEqual(useLabelQuantity.label, "Using 30 for this bottle")
        try app.performAccessibilityAudit(for: [
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
            .trait
        ])
        app.buttons["save-bottle"].tap()

        let done = app.buttons["setup-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable, "Done is out of reach")
        XCTAssertEqual(app.descendants(matching: .any)["setup-tally"].label, "Added to Furosemide")
    }

    /// Scanning one bottle after another: each save returns to a new scanner
    /// with nothing of the last bottle in it, the bar under the camera counts
    /// what has gone in, and Done closes the flow.
    func testScanningBottlesOneAfterAnother() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-skip-onboarding",
            "-simulate-scanner",
            "-simulate-scan-name", "Tacrolimus",
            "-simulate-scan-strength", "1 mg",
            "-simulate-scan-quantity", "60",
            "-simulate-scan-name", "Prednisone",
            "-simulate-scan-strength", "5 mg",
            "-simulate-scan-quantity", "30",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL"
        ]
        // Saving asks for notification permission the first time.
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            for title in ["Allow", "Don’t Allow", "Don't Allow"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["scan-label"].waitForExistence(timeout: 3))
        app.buttons["scan-label"].tap()

        func scanAndAdd(expectedName: String, labelLine: String, lastLabelLine: String? = nil) {
            let simulate = app.buttons["simulate-scan"]
            XCTAssertTrue(simulate.waitForExistence(timeout: 5))
            simulate.tap()
            let review = app.buttons["Review"]
            XCTAssertTrue(review.waitForExistence(timeout: 3))
            review.tap()
            let name = app.textFields["medication-name"]
            XCTAssertTrue(name.waitForExistence(timeout: 15), "review screen never appeared")
            XCTAssertEqual(name.value as? String, expectedName)

            app.buttons["Scan evidence"].tap()
            XCTAssertTrue(app.staticTexts[labelLine].waitForExistence(timeout: 3))
            if let lastLabelLine {
                XCTAssertFalse(app.staticTexts[lastLabelLine].exists, "the last bottle's label reached this review")
            }

            let useLabelQuantity = app.buttons["use-label-quantity"]
            for _ in 0..<6 where !useLabelQuantity.isHittable { app.swipeUp() }
            useLabelQuantity.tap()
            app.buttons["save-medication"].tap()
        }

        scanAndAdd(expectedName: "Tacrolimus", labelLine: "TACROLIMUS 1 MG")
        let tally = app.descendants(matching: .any)["setup-tally"]
        XCTAssertTrue(tally.waitForExistence(timeout: 5), "saving a scanned bottle closed the flow")
        XCTAssertEqual(tally.label, "1 added: Tacrolimus")
        // The new scanner has read nothing: the last bottle's label is not
        // waiting behind its Review button.
        XCTAssertTrue(app.buttons["Capture & Review"].exists, "the scanner still holds the last bottle's evidence")
        XCTAssertFalse(app.buttons["Clear Scan"].isEnabled)

        scanAndAdd(expectedName: "Prednisone", labelLine: "PREDNISONE 5 MG", lastLabelLine: "TACROLIMUS 1 MG")
        XCTAssertTrue(tally.waitForExistence(timeout: 5))
        XCTAssertEqual(tally.label, "2 added: Prednisone and Tacrolimus")
        app.buttons["setup-done"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Medications"].tap()
        XCTAssertTrue(app.staticTexts["Tacrolimus"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Prednisone"].exists)
    }

    /// Prograf and Astagraf XL are both tacrolimus 1 mg capsules to the FDA
    /// directory, one taken twice a day and the other once. An Astagraf XL
    /// bottle must not be offered as the Prograf already tracked; a generic
    /// Prograf bottle is, and the banner names the brand it would join.
    func testAnExtendedReleaseBottleIsNotOfferedAsTheImmediateReleaseOne() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-skip-onboarding",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL"
        ]
        // Saving asks for notification permission the first time.
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            for title in ["Allow", "Don’t Allow", "Don't Allow"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))

        // The form builds its rows as they scroll in, so a row further down
        // does not exist until it is near, and one under the keyboard exists
        // but cannot be tapped: scroll until it is both, a bounded number of
        // times, whatever an earlier test left the keyboard or the scroll
        // position doing.
        func scrollUp(to element: XCUIElement, _ description: String) {
            XCTAssertTrue(reveal(element, in: app), "\(description) cannot be reached")
        }

        func reviewByCode(_ code: String) {
            app.tabBars.buttons["Add"].tap()
            XCTAssertTrue(app.buttons["manual-entry"].waitForExistence(timeout: 3))
            app.buttons["manual-entry"].tap()
            XCTAssertTrue(app.textFields["medication-name"].waitForExistence(timeout: 3))
            let ndc = app.textFields["ndc-entry"]
            scrollUp(to: ndc, "the NDC field")
            ndc.tap()
            ndc.typeText(code)
            let use = app.buttons["use-ndc-product"]
            XCTAssertTrue(use.waitForExistence(timeout: 5))
            scrollUp(to: use, "Use This Product")
            use.tap()
            // Back to the top, where the banner sits above the name.
            let name = app.textFields["medication-name"]
            reveal(name, in: app, swipingDown: true)
            app.swipeDown()
        }

        reviewByCode("0469-0617-73")
        let supply = app.textFields["current-supply"]
        scrollUp(to: supply, "Current amount")
        supply.tap()
        supply.typeText("30")
        app.buttons["save-medication"].tap()
        // Whether this run is the first to save and be asked depends on the
        // tests before it, so the answer is looked for rather than assumed.
        answerNotificationPermissionIfAsked()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))

        reviewByCode("0469-0677-73")
        XCTAssertEqual(app.textFields["medication-brand-name"].value as? String, "Astagraf XL")
        let banner = app.descendants(matching: .any)["duplicate-banner"]
        XCTAssertFalse(banner.waitForExistence(timeout: 2), "Astagraf XL offered as the tracked Prograf: \(banner.exists ? banner.label : "")")
        app.navigationBars.buttons["Cancel"].tap()
        let discard = app.buttons["Discard"]
        if discard.waitForExistence(timeout: 2) { discard.tap() }
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))

        reviewByCode("0378-2046-01")
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "a generic Prograf bottle was not offered to the Prograf tracked")
        XCTAssertEqual(banner.label, "Already in Meds Ahead: Tacrolimus 1 mg (Prograf)")
    }

    /// Swipes until the element exists and can be tapped, at most `limit`
    /// times, and stops as soon as it can: a `for … where` loop goes on
    /// querying the screen once the element is found, which adds seconds to
    /// every row a long form scrolls to.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, swipingDown: Bool = false, limit: Int = 12) -> Bool {
        var swipes = 0
        while !(element.exists && element.isHittable), swipes < limit {
            if swipingDown { app.swipeDown() } else { app.swipeUp() }
            swipes += 1
        }
        return element.exists && element.isHittable
    }

    /// The first save asks for notification permission. The system shows
    /// the question over the app, so it is answered where it is shown.
    private func answerNotificationPermissionIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for title in ["Allow", "Don’t Allow", "Don't Allow"] {
            let button = springboard.alerts.buttons[title]
            if button.waitForExistence(timeout: title == "Allow" ? 2 : 0.5) {
                button.tap()
                return
            }
        }
    }

    /// With no refills left the low-supply alert comes earlier, and the detail
    /// screen says why. At the largest text size that sentence sat in a column
    /// beside its label and broke mid-word; it now sits under the label with
    /// the card's width.
    func testTheLowSupplyAlertsReasonHasRoomAtTheLargestText() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-skip-onboarding",
            "-seed-demo-data",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Supply"].tap()
        let row = app.staticTexts["Furosemide"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        XCTAssertTrue(app.buttons["Medication actions"].waitForExistence(timeout: 3))
        app.buttons["Medication actions"].tap()
        XCTAssertTrue(app.buttons["Edit Medication"].waitForExistence(timeout: 3))
        app.buttons["Edit Medication"].tap()

        let refills = app.textFields["Refills remaining (optional)"]
        for _ in 0..<12 where !(refills.exists && refills.isHittable) { app.swipeUp() }
        XCTAssertTrue(refills.isHittable, "the refills field cannot be reached")
        refills.tap()
        refills.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "0")
        app.navigationBars["Edit Medication"].buttons["Save"].tap()

        let label = app.staticTexts["Low-supply alert"]
        let value = app.staticTexts["10 days before, because no refills are left"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        for _ in 0..<8 where !(value.exists && value.isHittable) { app.swipeUp() }
        XCTAssertTrue(value.isHittable, "the lead time does not give its reason")
        XCTAssertGreaterThanOrEqual(value.frame.minY, label.frame.maxY - 1, "the reason sits beside its label, not under it")
        XCTAssertGreaterThan(value.frame.width, app.windows.firstMatch.frame.width * 0.6, "the reason is squeezed into a narrow column")
    }
}
