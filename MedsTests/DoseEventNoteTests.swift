import XCTest
@testable import Meds

/// These words are in people's ledgers already, and the Health sync tells a dose
/// logged here from Health's copy by them. A reworded note would leave every
/// stored event on the old words, so each one is pinned exactly.
final class DoseEventNoteTests: XCTestCase {
    func testStoredDoseNotesNeverChange() {
        XCTAssertEqual(DoseEvent.appleHealthNote, "Logged in Apple Health")
        XCTAssertEqual(DoseEventNote.reminder, "Logged from reminder")
        XCTAssertEqual(DoseEventNote.widget, "Logged from widget")
    }
}
