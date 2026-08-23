import XCTest
@testable import Meds

final class ScanParserTests: XCTestCase {
    func testParsesManufacturerLabelAndGS1Code() {
        let evidence = [
            ScanEvidence(kind: .text, value: "Each capsule contains"),
            ScanEvidence(kind: .text, value: "240 mg dimethyl fumarate"),
            ScanEvidence(kind: .text, value: "LOT SH0752"),
            ScanEvidence(kind: .text, value: "EXP 05/2029"),
            ScanEvidence(kind: .barcode, value: "0100364406006029", symbology: "GS1 DataBar Limited")
        ]

        let draft = ScanParser.parse(evidence)

        XCTAssertEqual(draft.name.lowercased(), "dimethyl fumarate")
        XCTAssertEqual(draft.strength.lowercased(), "240 mg")
        XCTAssertEqual(draft.form, .capsule)
        XCTAssertEqual(draft.lotNumber, "SH0752")
        XCTAssertEqual(draft.productIdentifier, "0100364406006029")
    }

    func testParsesOTCQuantity() {
        let evidence = [
            ScanEvidence(kind: .text, value: "Melatonin"),
            ScanEvidence(kind: .text, value: "5 mg"),
            ScanEvidence(kind: .text, value: "CONTENTS\n120 TABLETS"),
            ScanEvidence(kind: .barcode, value: "0036800401044", symbology: "EAN-13")
        ]
        let draft = ScanParser.parse(evidence)

        XCTAssertEqual(draft.name, "Melatonin")
        XCTAssertEqual(draft.strength.lowercased(), "5 mg")
        XCTAssertEqual(draft.currentSupply, 120)
    }

    func testPrefersNonURLBarcode() {
        let evidence = [
            ScanEvidence(kind: .barcode, value: "https://example.invalid/private", symbology: "QR"),
            ScanEvidence(kind: .barcode, value: "323615013", symbology: "Code 128")
        ]
        XCTAssertEqual(ScanParser.parse(evidence).productIdentifier, "323615013")
    }

    func testNoRefillsLeftParsesAsZero() {
        let evidence = [ScanEvidence(kind: .text, value: "No refills left")]
        XCTAssertEqual(ScanParser.parse(evidence).refillsRemaining, 0)
    }

    func testLowConfidenceFragmentDoesNotOverrideMedicationName() {
        let evidence = [
            ScanEvidence(kind: .text, value: "Fur0 random", confidence: 0.31),
            ScanEvidence(kind: .text, value: "Furosemide", confidence: 0.94),
            ScanEvidence(kind: .text, value: "20 mg", confidence: 0.97)
        ]

        let draft = ScanParser.parse(evidence)

        XCTAssertEqual(draft.name, "Furosemide")
        XCTAssertEqual(draft.strength.lowercased(), "20 mg")
        XCTAssertEqual(draft.evidence.count, 3, "Raw evidence remains available for human review")
    }

    func testLowConfidenceContextCanStillSupplyExplicitField() {
        let evidence = [
            ScanEvidence(kind: .text, value: "Qty 30", confidence: 0.34)
        ]

        XCTAssertEqual(ScanParser.parse(evidence).currentSupply, 30)
    }

    func testEvidenceMergeKeepsBestConfidenceForEquivalentReading() throws {
        let earlier = ScanEvidence(kind: .text, value: "FUROSEMIDE", confidence: 0.62)
        let corrected = ScanEvidence(kind: .text, value: "  furosemide. ", confidence: 0.96)

        let merged = ScanEvidenceQuality.mergingBest(existing: [earlier], additions: [corrected])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(try XCTUnwrap(merged.first).id, corrected.id)
    }
}
