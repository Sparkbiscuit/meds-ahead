import XCTest
@testable import Meds

final class ScanPreviewTests: XCTestCase {
    private func evidence(_ lines: [String]) -> [ScanEvidence] {
        let capture = UUID()
        return lines.enumerated().map { index, value in
            ScanEvidence(kind: .text, value: value, confidence: 0.9,
                         origin: .cameraCapture, captureID: capture, lineIndex: index)
        }
    }

    func testEmptyEvidenceProducesNoProgress() {
        let preview = ScanPreview.make(from: [])
        XCTAssertFalse(preview.hasUsefulProgress)
        XCTAssertTrue(preview.medicationName.isEmpty)
    }

    func testPreviewReportsRecognisedFields() {
        let preview = ScanPreview.make(from: evidence([
            "FUROSEMIDE 20 MG",
            "TAKE ONE TABLET TWICE DAILY",
            "QTY: 60 TABLETS"
        ]))

        XCTAssertEqual(preview.medicationName, "Furosemide")
        XCTAssertTrue(preview.hasStrength)
        XCTAssertTrue(preview.hasQuantity)
        XCTAssertTrue(preview.hasUsefulProgress)
    }

    func testPreviewMatchesTheDraftTheReviewScreenWillReceive() {
        let lines = evidence([
            "DIMETHYL FUMARATE 240 MG",
            "DELAYED-RELEASE CAPSULES",
            "TAKE ONE CAPSULE BY MOUTH TWICE DAILY",
            "QTY: 60 CAPSULES"
        ])
        let preview = ScanPreview.make(from: lines)
        let draft = MedicationLabelInterpreter.offlineDraft(lines)

        XCTAssertEqual(preview.medicationName, draft.name)
        XCTAssertEqual(preview.hasStrength, !draft.strength.isEmpty)
        XCTAssertEqual(preview.hasQuantity, draft.currentSupply != nil)
        XCTAssertEqual(preview.hasProductIdentifier, !draft.productIdentifier.isEmpty)
    }

    func testUnreadableEvidenceProducesNoName() {
        XCTAssertTrue(ScanPreview.make(from: evidence(["....", "!!"])).medicationName.isEmpty)
    }

    func testPreviewReportsWhetherRefillsWereCaptured() {
        let withRefills = ScanPreview.make(from: evidence(["Refills: 2"]))
        let withoutRefills = ScanPreview.make(from: evidence(["FUROSEMIDE 20 MG"]))

        XCTAssertTrue(withRefills.hasRefills)
        XCTAssertFalse(withoutRefills.hasRefills)
    }

    func testRefillOnlyPreviewCountsAsUsefulProgress() {
        let preview = ScanPreview.make(from: evidence(["Refills: 2"]))

        XCTAssertTrue(preview.medicationName.isEmpty)
        XCTAssertFalse(preview.hasStrength)
        XCTAssertFalse(preview.hasQuantity)
        XCTAssertFalse(preview.hasProductIdentifier)
        XCTAssertTrue(preview.hasRefills)
        XCTAssertTrue(preview.hasUsefulProgress)
    }

    func testPreviewPinsAllCapturedFieldFlagsTogether() {
        let preview = ScanPreview.make(from: evidence([
            "FUROSEMIDE 20 MG",
            "QTY: 60 TABLETS",
            "Refills: 2",
            "NDC: 00093-1045-98"
        ]))

        XCTAssertEqual(preview.medicationName, "Furosemide")
        XCTAssertTrue(preview.hasStrength)
        XCTAssertTrue(preview.hasQuantity)
        XCTAssertTrue(preview.hasProductIdentifier)
        XCTAssertTrue(preview.hasRefills)
    }
}
