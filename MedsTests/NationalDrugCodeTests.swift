import XCTest
@testable import Meds

final class NationalDrugCodeTests: XCTestCase {
    // MARK: - Renderings

    func testEachNativeLayoutPadsToTheElevenDigitForm() {
        XCTAssertEqual(canonical("0093-1039-01"), ["00093-1039-01"], "4-4-2")
        XCTAssertEqual(canonical("64406-006-02"), ["64406-0006-02"], "5-3-2")
        XCTAssertEqual(canonical("12345-6789-0"), ["12345-6789-00"], "5-4-1")
        XCTAssertEqual(canonical("00093-1039-01"), ["00093-1039-01"], "already 5-4-2")
        XCTAssertEqual(canonical("00093103901"), ["00093-1039-01"], "eleven bare digits")
    }

    func testTenBareDigitsOfferEveryLayout() {
        XCTAssertEqual(
            canonical("6440600602"),
            ["06440-6006-02", "64406-0006-02", "64406-0060-02"]
        )
    }

    func testMalformedRenderingsAreNotCodes() {
        for rendering in ["1234-567-8", "123456-789-01", "12345-67890-1", "123456789", "123456789012", "0093-10A9-01", ""] {
            XCTAssertTrue(NationalDrugCode.candidates(fromRendering: rendering).isEmpty, rendering)
        }
    }

    func testProductKeyDropsThePackage() {
        let code = try? XCTUnwrap(NationalDrugCode(canonicalDigits: "00093103901"))
        XCTAssertEqual(code?.productKey, "000931039")
        XCTAssertEqual(code?.hyphenated, "00093-1039-01")
    }

    // MARK: - Printed text

    func testPrintedCodesAreFoundInTheirCommonSpellings() {
        for text in [
            "NDC 0093-1039-01",
            "NDC: 0093-1039-01",
            "NDC# 0093-1039-01",
            "NDC No. 0093-1039-01",
            "ndc 00093103901",
            "MFR: TEVA   NDC 00093-1039-01   QTY 30"
        ] {
            let readings = NationalDrugCode.readings(inLabelText: text)
            XCTAssertEqual(readings.count, 1, text)
            XCTAssertEqual(readings.first?.candidates.map(\.hyphenated), ["00093-1039-01"], text)
            XCTAssertEqual(readings.first?.source, .printedText)
        }
    }

    /// Vision reads a zero as O and a one as I or l often enough to matter.
    func testCommonOCRLetterConfusionsAreRepaired() {
        let readings = NationalDrugCode.readings(inLabelText: "NDC OO93-1O39-Ol")
        XCTAssertEqual(readings.first?.candidates.map(\.hyphenated), ["00093-1039-01"])
        XCTAssertEqual(readings.first?.raw, "0093-1039-01")
    }

    func testEveryPrintedCodeIsReportedOnce() {
        let readings = NationalDrugCode.readings(inLabelText: "NDC 0093-1039-01\nLOT 1234\nNDC 0093-1039-01\nNDC 64406-006-02")
        XCTAssertEqual(readings.map { $0.candidates.first?.hyphenated }, ["00093-1039-01", "64406-0006-02"])
    }

    func testTextWithoutACodeYieldsNothing() {
        XCTAssertTrue(NationalDrugCode.readings(inLabelText: "RX# 8842197 QTY 30 NDC").isEmpty)
        XCTAssertTrue(NationalDrugCode.readings(inLabelText: "NDC 0093-1039-012").isEmpty, "an extra digit is not a code")
    }

    // MARK: - Barcodes

    func testGS1ElementStringYieldsTheEmbeddedCode() {
        let readings = NationalDrugCode.readings(inBarcode: "0100364406006029")
        XCTAssertEqual(readings.count, 1)
        XCTAssertEqual(readings.first?.source, .barcode)
        XCTAssertEqual(
            readings.first?.candidates.map(\.hyphenated),
            ["06440-6006-02", "64406-0006-02", "64406-0060-02"]
        )
    }

    func testUPCAAndEAN13OfADrugPackageDecode() {
        // 3 + 0093103901 + check digit, as a UPC-A on a manufacturer's bottle.
        let upc = "3" + "0093103901" + "9"
        XCTAssertTrue(NationalDrugCode.hasValidGS1CheckDigit("00" + upc))
        XCTAssertEqual(NationalDrugCode.readings(inBarcode: upc).first?.candidates.map(\.hyphenated),
                       ["00093-1039-01", "00931-0039-01", "00931-0390-01"])
        XCTAssertEqual(NationalDrugCode.readings(inBarcode: "0" + upc).first?.candidates.count, 3, "EAN-13 form")
        XCTAssertEqual(NationalDrugCode.readings(inBarcode: "(01)00" + upc).first?.candidates.count, 3, "bracketed AI")
    }

    func testBarcodesThatAreNotDrugGTINsYieldNothing() {
        XCTAssertTrue(NationalDrugCode.readings(inBarcode: "0036800401044").isEmpty, "a supplement's UPC has no NDC")
        XCTAssertTrue(NationalDrugCode.readings(inBarcode: "323615013").isEmpty, "a pharmacy Rx number")
        XCTAssertTrue(NationalDrugCode.readings(inBarcode: "https://example.invalid/private").isEmpty)
        XCTAssertTrue(NationalDrugCode.readings(inBarcode: "0100364406006020").isEmpty, "wrong check digit")
    }

    private func canonical(_ rendering: String) -> [String] {
        NationalDrugCode.candidates(fromRendering: rendering).map(\.hyphenated)
    }
}
