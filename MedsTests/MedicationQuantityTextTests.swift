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
        XCTAssertEqual(SupplyChangeQuantity.value(from: supply.medicationQuantityText, prefilled: supply, requiresMoreThanZero: false), supply)
    }
}
