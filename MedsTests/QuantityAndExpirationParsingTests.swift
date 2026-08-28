import XCTest
@testable import Meds

final class QuantityAndExpirationParsingTests: XCTestCase {
    private var calendar: Calendar { Calendar(identifier: .gregorian) }

    private func expirationComponents(from text: String) -> DateComponents? {
        let draft = ScanParser.parse([ScanEvidence(kind: .text, value: text)])
        guard let date = draft.expirationDate else { return nil }
        return calendar.dateComponents([.year, .month, .day], from: date)
    }

    func testMonthYearExpirationUsesLastDayOfMonth() {
        let parts = expirationComponents(from: "EXP 05/2029")
        XCTAssertEqual(parts?.year, 2029)
        XCTAssertEqual(parts?.month, 5)
        XCTAssertEqual(parts?.day, 31)
    }

    func testDecemberMonthYearExpirationStaysWithinItsYear() {
        let parts = expirationComponents(from: "EXP 12/2026")
        XCTAssertEqual(parts?.year, 2026)
        XCTAssertEqual(parts?.month, 12)
        XCTAssertEqual(parts?.day, 31)
    }

    func testFullDateExpirationKeepsPrintedDay() {
        // "EXP 10/01/25" previously parsed as month 10 of year 2001.
        let parts = expirationComponents(from: "EXP 10/01/25")
        XCTAssertEqual(parts?.year, 2025)
        XCTAssertEqual(parts?.month, 10)
        XCTAssertEqual(parts?.day, 1)
    }

    func testFullDateExpirationWithFourDigitYearAndDashes() {
        let parts = expirationComponents(from: "Expires: 3-26-2027")
        XCTAssertEqual(parts?.year, 2027)
        XCTAssertEqual(parts?.month, 3)
        XCTAssertEqual(parts?.day, 26)
    }

    func testImpossiblePrintedDayFallsBackToEndOfMonth() {
        let parts = expirationComponents(from: "EXP 02/31/27")
        XCTAssertEqual(parts?.year, 2027)
        XCTAssertEqual(parts?.month, 2)
        XCTAssertEqual(parts?.day, 28)
    }

    func testTwoDigitYearMonthOnlyExpiration() {
        let parts = expirationComponents(from: "EXP 11/26")
        XCTAssertEqual(parts?.year, 2026)
        XCTAssertEqual(parts?.month, 11)
        XCTAssertEqual(parts?.day, 30)
    }

    func testImplausibleYearIsNotPrefilled() {
        XCTAssertNil(expirationComponents(from: "EXP 05/202"))
    }

    func testPharmacyDiscardAfterDateParses() {
        // Amber pharmacy vials print "DISCARD AFTER", not "EXP".
        let parts = expirationComponents(from: "DISCARD AFTER 07/14/26")
        XCTAssertEqual(parts?.year, 2026)
        XCTAssertEqual(parts?.month, 7)
        XCTAssertEqual(parts?.day, 14)
    }

    func testOCRPipeMisreadOfDateSlashStillParses() {
        // Vision reads a printed slash as a pipe often enough that a rendered
        // label in LabelPhotoRecognitionTests hit exactly this.
        let parts = expirationComponents(from: "DISCARD AFTER 07|14/26")
        XCTAssertEqual(parts?.year, 2026)
        XCTAssertEqual(parts?.month, 7)
        XCTAssertEqual(parts?.day, 14)
    }

    func testDottedDateSeparatorParses() {
        let parts = expirationComponents(from: "EXP 05.2029")
        XCTAssertEqual(parts?.year, 2029)
        XCTAssertEqual(parts?.month, 5)
        XCTAssertEqual(parts?.day, 31)
    }

    func testUseByMonthYearParses() {
        let parts = expirationComponents(from: "USE BY 08/27")
        XCTAssertEqual(parts?.year, 2027)
        XCTAssertEqual(parts?.month, 8)
        XCTAssertEqual(parts?.day, 31)
    }

    func testDoNotUseAfterParses() {
        let parts = expirationComponents(from: "Do not use after 06/2027")
        XCTAssertEqual(parts?.year, 2027)
        XCTAssertEqual(parts?.month, 6)
        XCTAssertEqual(parts?.day, 30)
    }

    func testNamedMonthExpirationParses() {
        let parts = expirationComponents(from: "EXP MAY 2029")
        XCTAssertEqual(parts?.year, 2029)
        XCTAssertEqual(parts?.month, 5)
        XCTAssertEqual(parts?.day, 31)
    }

    func testCompactBlisterPackDayMonthYearParses() {
        let parts = expirationComponents(from: "EXP 01MAY29")
        XCTAssertEqual(parts?.year, 2029)
        XCTAssertEqual(parts?.month, 5)
        XCTAssertEqual(parts?.day, 1)
    }

    func testSpelledOutMonthDayYearParses() {
        let parts = expirationComponents(from: "Expires January 3, 2027")
        XCTAssertEqual(parts?.year, 2027)
        XCTAssertEqual(parts?.month, 1)
        XCTAssertEqual(parts?.day, 3)
    }

    func testBestByNamedMonthTwoDigitYearParses() {
        let parts = expirationComponents(from: "Best by SEP 26")
        XCTAssertEqual(parts?.year, 2026)
        XCTAssertEqual(parts?.month, 9)
        XCTAssertEqual(parts?.day, 30)
    }

    func testQuantityParsingAcceptsPlainDecimalsEverywhere() {
        XCTAssertEqual(Double.medicationQuantity(from: "30"), 30)
        XCTAssertEqual(Double.medicationQuantity(from: "1.5"), 1.5)
        XCTAssertEqual(Double.medicationQuantity(from: " 2 "), 2)
    }

    func testQuantityParsingAcceptsCommaDecimalLocaleInput() {
        XCTAssertEqual(Double.medicationQuantity(from: "1,5", locale: Locale(identifier: "de_DE")), 1.5)
        XCTAssertEqual(Double.medicationQuantity(from: "0,25", locale: Locale(identifier: "fr_FR")), 0.25)
    }

    func testQuantityParsingRoundTripsFormattedDraftText() {
        // A scanned draft prefills the field with locale-formatted text; that text
        // must parse back in the same locale.
        let text = 1.5.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "de_DE")))
        XCTAssertEqual(Double.medicationQuantity(from: text, locale: Locale(identifier: "de_DE")), 1.5)
    }

    func testQuantityParsingRejectsUnusableInput() {
        XCTAssertNil(Double.medicationQuantity(from: ""))
        XCTAssertNil(Double.medicationQuantity(from: "   "))
        XCTAssertNil(Double.medicationQuantity(from: "tablets"))
        XCTAssertNil(Double.medicationQuantity(from: "inf"))
    }
}
