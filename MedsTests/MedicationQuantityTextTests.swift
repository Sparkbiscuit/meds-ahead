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
}
