import XCTest
@testable import Meds

final class AppThemeTests: XCTestCase {
    func testAccentIndexIgnoresCase() {
        XCTAssertEqual(
            AppTheme.accentIndex(for: "Furosemide"),
            AppTheme.accentIndex(for: "FUROSEMIDE")
        )
    }

    func testAccentIndexAlwaysAddressesThePalette() {
        let names = ["", "A", "Furosemide", "Dimethyl fumarate", "Melatonin", String(repeating: "z", count: 300)]
        for name in names {
            let index = AppTheme.accentIndex(for: name)
            XCTAssertTrue(
                AppTheme.medicationColors.indices.contains(index),
                "\(name) produced out-of-range index \(index)"
            )
        }
    }

    func testColorLookupSurvivesExtremeStoredIndex() {
        // The previous implementation used abs(), which traps on Int.min.
        for stored in [Int.min, -1, 0, Int.max] {
            let medication = Medication(name: "Probe", accentIndex: stored)
            _ = AppTheme.color(for: medication)
        }
    }
}
