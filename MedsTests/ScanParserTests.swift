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

    func testParsesCommonLabeledRefillFormats() {
        for value in ["Refills: 3", "REFILLS REMAINING 3", "Rfls #3", "3 refills"] {
            let evidence = [ScanEvidence(kind: .text, value: value)]
            XCTAssertEqual(ScanParser.parse(evidence).refillsRemaining, 3, value)
        }
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

    func testLiveEvidenceMergeRetainsLowConfidenceTextForSemanticReview() {
        let liveText = ScanEvidence(
            kind: .text,
            value: "AMPHETAMINE",
            confidence: 0.12,
            origin: .liveCamera
        )

        let merged = ScanEvidenceQuality.mergingBest(
            existing: [],
            additions: [liveText]
        )

        XCTAssertEqual(merged.map(\.value), ["AMPHETAMINE"])
    }

    func testHighResolutionCaptureRetainsLowConfidenceDrugFragmentForVocabularyRepair() {
        let captured = ScanEvidence(
            kind: .text,
            value: "AMPHETAMINE - DEXTROAMPHET",
            confidence: 0.27,
            origin: .cameraCapture
        )

        let merged = ScanEvidenceQuality.mergingBest(existing: [], additions: [captured])

        XCTAssertEqual(merged.map(\.value), ["AMPHETAMINE - DEXTROAMPHET"])
        XCTAssertEqual(
            MedicationLabelInterpreter.offlineDraft(merged).name,
            "Amphetamine - dextroamphetamine"
        )
    }

    func testLiveCameraConfidenceDoesNotSuppressStructuredLabelFields() {
        let evidence = [
            ScanEvidence(kind: .text, value: "FUROSEMIDE", confidence: 0.12),
            ScanEvidence(kind: .text, value: "20 mg tablet", confidence: 0.16),
            ScanEvidence(kind: .text, value: "TAKE ONE TABLET DAILY", confidence: 0.14),
            ScanEvidence(kind: .text, value: "Qty: 30", confidence: 0.11),
            ScanEvidence(kind: .text, value: "Refills: 2", confidence: 0.10)
        ]

        let draft = ScanParser.parse(evidence)

        XCTAssertEqual(draft.name, "Furosemide")
        XCTAssertEqual(draft.strength.lowercased(), "20 mg")
        XCTAssertEqual(draft.form, .tablet)
        XCTAssertEqual(draft.directions, "TAKE ONE TABLET DAILY")
        XCTAssertEqual(draft.currentSupply, 30)
        XCTAssertEqual(draft.refillsRemaining, 2)
    }

    func testEvidenceMergeKeepsBestConfidenceForEquivalentReading() throws {
        let earlier = ScanEvidence(kind: .text, value: "FUROSEMIDE", confidence: 0.62)
        let corrected = ScanEvidence(kind: .text, value: "  furosemide. ", confidence: 0.96)

        let merged = ScanEvidenceQuality.mergingBest(existing: [earlier], additions: [corrected])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(try XCTUnwrap(merged.first).id, corrected.id)
    }

    func testEvidenceMergeReplacesMissingFirstLetterWithCompleteReading() throws {
        let fragment = ScanEvidence(kind: .text, value: "elatonin", confidence: 0.84)
        let complete = ScanEvidence(kind: .text, value: "Melatonin", confidence: 0.84)

        let merged = ScanEvidenceQuality.mergingBest(existing: [fragment], additions: [complete])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(try XCTUnwrap(merged.first).value, "Melatonin")
    }

    func testEvidenceMergeCollapsesOCRSpellingAlternatives() throws {
        let primary = ScanEvidence(kind: .text, value: "Melatonin", confidence: 1)
        let alternate = ScanEvidence(kind: .text, value: "Meltonin", confidence: 0.5)

        let merged = ScanEvidenceQuality.mergingBest(existing: [], additions: [primary, alternate])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(try XCTUnwrap(merged.first).value, "Melatonin")
    }

    func testIncompleteDirectionsFromCurvedLabelAreNotAutofilled() {
        let evidence = [ScanEvidence(kind: .text, value: "TAKE ONE TABLET BY MO.")]

        XCTAssertEqual(ScanParser.parse(evidence).directions, "")
    }

    func testPackageCountParsesAsCurrentSupply() {
        let evidence = [ScanEvidence(kind: .text, value: "120 TABLETS")]

        XCTAssertEqual(ScanParser.parse(evidence).currentSupply, 120)
    }

    func testNameOnStrengthLineDropsDosageFormWords() {
        let evidence = [
            ScanEvidence(kind: .text, value: "FUROSEMIDE 20 MG TABLETS", confidence: 0.92),
            ScanEvidence(kind: .text, value: "TAKE ONE TABLET DAILY", confidence: 0.97)
        ]

        let draft = ScanParser.parse(evidence)

        XCTAssertEqual(draft.name, "Furosemide")
        XCTAssertEqual(draft.strength.lowercased(), "20 mg")
    }

    func testPatientNameIsNotChosenAsMedicationName() {
        let evidence = [
            ScanEvidence(kind: .text, value: "Patient", confidence: 0.99),
            ScanEvidence(kind: .text, value: "Alex Morgan", confidence: 0.99),
            ScanEvidence(kind: .text, value: "Furosemide", confidence: 0.86)
        ]

        XCTAssertEqual(ScanParser.parse(evidence).name, "Furosemide")
    }

    func testAmbiguousPackagingTextLeavesMedicationNameBlank() {
        let evidence = [
            ScanEvidence(kind: .text, value: "Natural Cherry", confidence: 0.98),
            ScanEvidence(kind: .text, value: "May Help Support Sleep", confidence: 0.97),
            ScanEvidence(kind: .text, value: "Store in a cool dry place", confidence: 0.96)
        ]

        XCTAssertEqual(ScanParser.parse(evidence).name, "")
    }

    func testPrintedNDCIsUsedWhenNoBarcodeDecodes() {
        let evidence = [
            ScanEvidence(kind: .text, value: "NDC 00054-8179-25", confidence: 0.96)
        ]

        let draft = ScanParser.parse(evidence)

        XCTAssertEqual(draft.productIdentifier, "00054-8179-25")
        XCTAssertEqual(draft.productIdentifierType, "NDC")
    }

    func testDirectionsIgnoreExpirationAndSupplementFragments() {
        let evidence = [
            ScanEvidence(kind: .text, value: "Furosemide", confidence: 0.92),
            ScanEvidence(kind: .text, value: "20 mg", confidence: 0.96),
            ScanEvidence(kind: .text, value: "USE BY 05/2029", confidence: 0.99),
            ScanEvidence(kind: .text, value: "% DAILY VALUE", confidence: 0.99),
            ScanEvidence(kind: .text, value: "TAKE ONE TABLET DAILY", confidence: 0.84)
        ]

        XCTAssertEqual(ScanParser.parse(evidence).directions, "TAKE ONE TABLET DAILY")
    }

    func testDirectionsAcceptDoseFrequencyWithoutVerb() {
        let evidence = [
            ScanEvidence(kind: .text, value: "ONE CAPSULE TWICE DAILY", confidence: 0.88)
        ]

        XCTAssertEqual(ScanParser.parse(evidence).directions, "ONE CAPSULE TWICE DAILY")
    }

    func testNonLatinOCRFragmentsNeverReachParser() {
        let evidence = [
            ScanEvidence(kind: .text, value: "Мелатонин", confidence: 0.99),
            ScanEvidence(kind: .text, value: "褪黑素", confidence: 0.99),
            ScanEvidence(kind: .text, value: "Melatonin", confidence: 0.90),
            ScanEvidence(kind: .text, value: "5 mg", confidence: 0.90)
        ]

        let draft = ScanParser.parse(evidence)

        XCTAssertEqual(draft.name, "Melatonin")
        XCTAssertEqual(draft.evidence.map(\.value), ["Melatonin", "5 mg"])
    }
}
