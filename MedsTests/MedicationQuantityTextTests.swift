import XCTest
@testable import Meds

final class MedicationQuantityTextTests: XCTestCase {
    func testWholeNumbersPrintWithoutADecimalPoint() {
        XCTAssertEqual(Double(30).medicationQuantityText, "30")
        XCTAssertEqual(Double(0).medicationQuantityText, "0")
    }

    func testFractionalDosesKeepTheirPrecision() {
        XCTAssertEqual(Double(0.5).medicationQuantityText, "0.5")
    }

    /// The count fields take as many digits as a person can hold a key down for, and
    /// converting one of those to `Int` used to end the app rather than print it.
    func testAnAbsurdlyLargeCountPrintsInsteadOfTrapping() {
        XCTAssertFalse(Double(1e20).medicationQuantityText.isEmpty)
        XCTAssertFalse(Double.greatestFiniteMagnitude.medicationQuantityText.isEmpty)
    }

    /// Add Refill and Correct Current Count read their number from the text as
    /// typed. A comma-decimal region's decimal pad types "2,5", which is two and
    /// a half, not the number the sheet opened with.
    func testASupplySheetReadsACommaDecimalInACommaLocale() {
        let german = Locale(identifier: "de_DE")
        XCTAssertEqual(SupplyChangeQuantity.value(from: "2,5", prefilled: 30, requiresMoreThanZero: true, locale: german), 2.5)
        XCTAssertEqual(SupplyChangeQuantity.value(from: "90", prefilled: 30, requiresMoreThanZero: true, locale: german), 90)
    }

    func testACountMayBeZeroButARefillMayNot() {
        XCTAssertEqual(SupplyChangeQuantity.value(from: "0", prefilled: 28, requiresMoreThanZero: false), 0)
        XCTAssertNil(SupplyChangeQuantity.value(from: "0", prefilled: 30, requiresMoreThanZero: true))
        XCTAssertNil(SupplyChangeQuantity.value(from: "-3", prefilled: 28, requiresMoreThanZero: false))
    }

    /// The lenient parse reads "2..8" as 2, and the sheet closes on the tap, so a
    /// slipped key would have recorded a count nobody typed.
    func testTextThatIsNotOneNumberLeavesTheSheetDisabled() {
        let english = Locale(identifier: "en_US")
        for text in ["", "   ", "tablets", "2..8", "1.5.5"] {
            XCTAssertNil(SupplyChangeQuantity.value(from: text, prefilled: 30, requiresMoreThanZero: false, locale: english), text)
        }
        XCTAssertNil(SupplyChangeQuantity.value(from: "1,5,5", prefilled: 30, requiresMoreThanZero: false, locale: Locale(identifier: "de_DE")))
    }

    /// The prefilled text is rounded to two places; saving it unchanged must not
    /// record a correction of the rounding.
    func testUntouchedPrefilledTextRecordsTheExactNumber() {
        let supply = 27.125
        XCTAssertEqual(SupplyChangeQuantity.value(from: SupplyChangeQuantity.text(for: supply), prefilled: supply, requiresMoreThanZero: false), supply)
    }

    /// A region that groups with "." would prefill 1497.5 mL as "1.497,5", and
    /// deleting only the fraction left "1.497", which recorded 1.497.
    func testAGroupedNumberIsNeitherPrefilledNorGuessedAt() {
        let german = Locale(identifier: "de_DE")
        XCTAssertEqual(SupplyChangeQuantity.text(for: 1497.5, locale: german), "1497,5")
        XCTAssertEqual(SupplyChangeQuantity.value(from: "1497", prefilled: 1497.5, requiresMoreThanZero: false, locale: german), 1497)
        XCTAssertNil(SupplyChangeQuantity.value(from: "1.497", prefilled: 1497.5, requiresMoreThanZero: false, locale: german))
        XCTAssertNil(SupplyChangeQuantity.value(from: "1,000", prefilled: 30, requiresMoreThanZero: true, locale: Locale(identifier: "en_US")))
        XCTAssertEqual(SupplyChangeQuantity.value(from: "1000.5", prefilled: 30, requiresMoreThanZero: true, locale: Locale(identifier: "en_US")), 1000.5)
    }

    // MARK: - Plurals

    /// Every surface used to add "s" to the form's unit, which printed
    /// "30 patchs on hand" and "150 mLs".
    func testEveryFormReadsInTheSingularAndThePlural() {
        let cases: [(form: MedicationForm, one: String, many: Double, manyText: String)] = [
            (.tablet, "1 tablet", 30, "30 tablets"),
            (.capsule, "1 capsule", 30, "30 capsules"),
            (.liquid, "1 mL", 150, "150 mL"),
            (.injection, "1 dose", 2, "2 doses"),
            (.inhaler, "1 puff", 2, "2 puffs"),
            (.patch, "1 patch", 30, "30 patches"),
            (.drops, "1 drop", 2, "2 drops"),
            (.topical, "1 application", 2, "2 applications"),
            (.other, "1 unit", 2, "2 units")
        ]
        XCTAssertEqual(Set(cases.map(\.form)), Set(MedicationForm.allCases), "a new form needs its plural written out")
        for (form, one, many, manyText) in cases {
            XCTAssertEqual(form.quantityText(1), one)
            XCTAssertEqual(form.quantityText(many), manyText)
            XCTAssertEqual(form.unitText(for: 1), form.unitName, "the singular is the model's own unit name")
            XCTAssertEqual(form.quantityText(0), "0 \(form.unitText(for: 2))", "nothing takes the plural")
        }
    }

    func testAFractionTakesThePluralAndMillilitresNeverDo() {
        XCTAssertEqual(MedicationForm.tablet.quantityText(0.5), "0.5 tablets")
        XCTAssertEqual(MedicationForm.patch.quantityText(1.5), "1.5 patches")
        XCTAssertEqual(MedicationForm.liquid.quantityText(0.5), "0.5 mL")
        XCTAssertEqual(MedicationForm.liquid.quantityText(2.5), "2.5 mL")
    }

    /// The singular follows the number as printed: 1.004 prints as "1", and
    /// "1 tablets" beside it reads as a mistake.
    func testTheSingularFollowsThePrintedNumber() {
        XCTAssertEqual(MedicationForm.tablet.quantityText(1.004), "1 tablet")
        XCTAssertEqual(MedicationForm.tablet.quantityText(0.996), "1 tablet")
        XCTAssertEqual(MedicationForm.tablet.unitText(for: 1.004), "tablet")
        XCTAssertEqual(MedicationForm.tablet.quantityText(1.01), "1.01 tablets")
        XCTAssertEqual(MedicationForm.tablet.quantityText(0.99), "0.99 tablets")
        XCTAssertEqual(MedicationForm.tablet.unitText(for: -1), "tablets")
    }

    func testDayAndThingCounts() {
        XCTAssertEqual(1.dayCountText, "1 day")
        XCTAssertEqual(0.dayCountText, "0 days")
        XCTAssertEqual(2.dayCountText, "2 days")
        XCTAssertEqual(30.dayCountText, "30 days")
        XCTAssertEqual(1.counted("reminder", plural: "reminders"), "1 reminder")
        XCTAssertEqual(3.counted("reminder", plural: "reminders"), "3 reminders")
    }

    /// The low-supply stepper starts at 1, and a gauge can reach a single day.
    func testASingleDayReadsAsADay() {
        XCTAssertEqual(SupplyGauge(daysRemaining: 1, leadDays: 7).accessibilityText, "1 day of supply remaining")
        XCTAssertEqual(SupplyGauge(daysRemaining: 12, leadDays: 7).accessibilityText, "12 days of supply remaining")
        let lastDay = SupplyForecast(currentSupply: 2, depletionDate: .now, daysRemaining: 1, confidence: .high, explanation: "")
        XCTAssertEqual(MedicationDetailView.forecastTitle(for: lastDay), "About 1 day left")
    }

    /// A reminder's body, the widget's dose line and the printed list each
    /// built their own plural.
    func testRemindersWidgetsAndTheListSayPatchesAndMillilitres() throws {
        func plan(_ form: MedicationForm, quantity: Double, hour: Int) -> MedicationNotificationPlan {
            MedicationNotificationPlan(
                medicationID: UUID(),
                displayName: "Example",
                form: form,
                isAsNeeded: false,
                isArchived: false,
                doseRemindersEnabled: true,
                refillRemindersEnabled: false,
                detailedNotifications: true,
                refillLeadDays: 7,
                refillsRemaining: nil,
                depletionDate: nil,
                schedules: [ScheduleNotificationPlan(id: UUID(), minutesAfterMidnight: hour * 60, doseQuantity: quantity, weekdayMask: 0b1111111)]
            )
        }
        let bodies = NotificationPlanner.plan(for: [
            plan(.patch, quantity: 1, hour: 8),
            plan(.patch, quantity: 2, hour: 12),
            plan(.liquid, quantity: 15, hour: 20)
        ]).notifications.filter { $0.kind == .dose }.map(\.body)
        XCTAssertEqual(bodies.sorted(), [
            "Touch and hold to log 1 patch, or open Meds Ahead to review.",
            "Touch and hold to log 15 mL, or open Meds Ahead to review.",
            "Touch and hold to log 2 patches, or open Meds Ahead to review."
        ])

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US")
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 13)))
        let patch = Medication(name: "Estradiol", form: .patch, refillsRemaining: 1, createdAt: start)
        let syrup = Medication(name: "Lactulose", form: .liquid, createdAt: start)
        let schedules = [
            DoseSchedule(medicationID: patch.id, minutesAfterMidnight: 8 * 60, doseQuantity: 1, startDate: start),
            DoseSchedule(medicationID: syrup.id, minutesAfterMidnight: 9 * 60, doseQuantity: 2.5, startDate: start)
        ]

        let morning = try XCTUnwrap(calendar.date(byAdding: .hour, value: 7, to: start))
        let snapshot = NextDoseSnapshot.make(medications: [patch], schedules: schedules, doseEvents: [], now: morning, calendar: calendar)
        guard case let .next(_, items) = snapshot.state else { return XCTFail("\(snapshot.state)") }
        XCTAssertEqual(items.map(\.quantityText), ["1 patch"])
        let later = NextDoseSnapshot.make(medications: [syrup], schedules: schedules, doseEvents: [], now: morning, calendar: calendar)
        guard case let .next(_, syrupItems) = later.state else { return XCTFail("\(later.state)") }
        XCTAssertEqual(syrupItems.map(\.quantityText), ["2.5 mL"])

        let entries = MedicationListDocument.entries(
            medications: [patch, syrup],
            schedules: schedules,
            inventoryEvents: [
                InventoryEvent(medicationID: patch.id, date: start, delta: 30, reason: .openingCount),
                InventoryEvent(medicationID: syrup.id, date: start, delta: 150, reason: .openingCount)
            ],
            doseEvents: [],
            now: morning,
            calendar: calendar
        )
        let patchEntry = try XCTUnwrap(entries.first { $0.title == "Estradiol" })
        XCTAssertTrue(try XCTUnwrap(patchEntry.scheduleLines.first).contains("— 1 patch ·"), patchEntry.scheduleLines.joined())
        XCTAssertTrue(patchEntry.supplyLine.hasPrefix("30 patches on hand"), patchEntry.supplyLine)
        XCTAssertEqual(patchEntry.detailLine, "1 refill remaining")
        let syrupEntry = try XCTUnwrap(entries.first { $0.title == "Lactulose" })
        XCTAssertTrue(try XCTUnwrap(syrupEntry.scheduleLines.first).contains("— 2.5 mL ·"), syrupEntry.scheduleLines.joined())
        XCTAssertTrue(syrupEntry.supplyLine.hasPrefix("150 mL on hand"), syrupEntry.supplyLine)
    }

    /// The editor's Current amount opened on grouped text: "1.497,5" in a region
    /// that groups with ".", which one deleted fraction turned into 1.497. It
    /// now opens on the supply sheets' ungrouped text.
    func testTheEditorsCurrentAmountOpensUngrouped() {
        let draft = MedicationDraft(name: "Lactulose", currentSupply: 1497.5, source: .manual)
        XCTAssertEqual(draft.initialCurrentAmountText, SupplyChangeQuantity.text(for: 1497.5))
        if let grouping = Locale.autoupdatingCurrent.groupingSeparator, !grouping.isEmpty {
            XCTAssertFalse(draft.initialCurrentAmountText.contains(grouping), draft.initialCurrentAmountText)
        }
        XCTAssertEqual(Double.medicationQuantity(from: draft.initialCurrentAmountText), 1497.5)
        XCTAssertEqual(MedicationDraft(name: "Lactulose", currentSupply: 30, source: .manual).initialCurrentAmountText, "30")
    }
}
