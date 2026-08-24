import XCTest
@testable import Meds

final class MedicationLabelInterpreterTests: XCTestCase {
    func testCandidateBuilderJoinsAdjacentMedicationNameFragments() {
        let captureID = UUID()
        let evidence = [
            ScanEvidence(kind: .text, value: "FURO", confidence: 0.3, captureID: captureID, lineIndex: 0),
            ScanEvidence(kind: .text, value: "SEMIDE", confidence: 0.3, captureID: captureID, lineIndex: 1),
            ScanEvidence(kind: .text, value: "20 mg tablet", confidence: 0.4, captureID: captureID, lineIndex: 2)
        ]

        let candidates = LabelCandidateBuilder.build(from: evidence)

        XCTAssertTrue(candidates.medicationNames.contains { $0.value == "FUROSEMIDE" })
        XCTAssertTrue(candidates.strengths.contains { $0.value.lowercased() == "20 mg" })
    }

    func testCandidateBuilderExcludesCommonMetadataAndPackagingClaims() {
        let evidence = [
            ScanEvidence(kind: .text, value: "Patient"),
            ScanEvidence(kind: .text, value: "Alex Morgan"),
            ScanEvidence(kind: .text, value: "Walgreens Pharmacy"),
            ScanEvidence(kind: .text, value: "DIETARY SUPPLEMENT"),
            ScanEvidence(kind: .text, value: "Melatonin 5 mg")
        ]

        let values = LabelCandidateBuilder.build(from: evidence).medicationNames.map(\.value)

        XCTAssertTrue(values.contains { $0.caseInsensitiveCompare("Melatonin") == .orderedSame })
        XCTAssertFalse(values.contains { $0.localizedCaseInsensitiveContains("Walgreens") })
        XCTAssertFalse(values.contains { $0.localizedCaseInsensitiveContains("Supplement") })
    }

    @available(iOS 26.0, *)
    func testSelectionCanOnlyApplyExistingCandidateIDs() {
        let candidates = LabelInterpretationCandidates(
            medicationNames: [LabelFieldCandidate(id: 1, value: "FUROSEMIDE")],
            strengths: [LabelFieldCandidate(id: 1, value: "20 mg")],
            directions: [],
            quantities: [],
            refills: []
        )
        let selection = LabelFieldSelection(
            medicationNameID: 99,
            normalizedMedicationName: "Furomax",
            strengthID: 1,
            directionsID: 0,
            quantityID: 0,
            refillsID: 0
        )

        let result = MedicationLabelInterpreter.applying(
            selection,
            candidates: candidates,
            to: MedicationDraft(name: "Packaging slogan")
        )

        XCTAssertEqual(result.name, "")
        XCTAssertEqual(result.strength, "20 mg")
    }

    func testValidatedNameRepairsMissingFirstLetter() {
        XCTAssertEqual(
            MedicationLabelInterpreter.validatedMedicationName("Melatonin", source: "elatonin"),
            "Melatonin"
        )
    }

    func testValidatedNameCompletesBottleEdgeClipping() {
        XCTAssertEqual(
            MedicationLabelInterpreter.validatedMedicationName(
                "AMPHETAMINE - DEXTROAMPHETAMINE",
                source: "AMPHETAMINE - DEXTROAMPHET"
            ),
            "AMPHETAMINE - DEXTROAMPHETAMINE"
        )
    }

    func testValidatedNameRejectsDifferentMedication() {
        XCTAssertNil(
            MedicationLabelInterpreter.validatedMedicationName("Furosemide", source: "Furomax")
        )
    }

    func testPhotoDerivedPrescriptionCandidatesRetainDrugAndRejectDistractions() {
        let evidence = [
            ScanEvidence(kind: .text, value: "Big Y Pharmacy #013"),
            ScanEvidence(kind: .text, value: "SAMPLE PATIENT"),
            ScanEvidence(kind: .text, value: "TAKE ONE TABLET BY MO."),
            ScanEvidence(kind: .text, value: "Warning: Breastfeeding is"),
            ScanEvidence(kind: .text, value: "not recommended while"),
            ScanEvidence(kind: .text, value: "AMPHETAMINE - DEXTROAMPHET"),
            ScanEvidence(kind: .text, value: "Mog: AL VOGEN")
        ]

        let candidates = LabelCandidateBuilder.build(from: evidence)
        let values = candidates.medicationNames.map(\.value)

        XCTAssertTrue(values.contains("AMPHETAMINE - DEXTROAMPHET"))
        XCTAssertFalse(values.contains { $0.localizedCaseInsensitiveContains("Pharmacy") })
        XCTAssertTrue(candidates.directions.isEmpty)
    }

    func testUnrelatedFragmentsFromDifferentCapturesAreNotJoined() {
        let evidence = [
            ScanEvidence(kind: .text, value: "NATURAL", captureID: UUID(), lineIndex: 0),
            ScanEvidence(kind: .text, value: "MELATONIN", captureID: UUID(), lineIndex: 1)
        ]

        let values = LabelCandidateBuilder.build(from: evidence).medicationNames.map(\.value)

        XCTAssertFalse(values.contains("NATURALMELATONIN"))
        XCTAssertFalse(values.contains("NATURAL MELATONIN"))
    }

    func testOfflineDraftCompletesUniquePrescriptionNameWithoutLanguageModel() {
        let evidence = [
            ScanEvidence(kind: .text, value: "AMPHETAMINE - DEXTROAMPHET", origin: .cameraCapture),
            ScanEvidence(kind: .text, value: "NDC 47781-0174-01", origin: .cameraCapture)
        ]

        XCTAssertEqual(
            MedicationLabelInterpreter.offlineDraft(evidence).name,
            "Amphetamine - dextroamphetamine"
        )
    }

    func testOfflineDraftRepairsUserReportedCompoundFragment() {
        let evidence = [
            ScanEvidence(
                kind: .text,
                value: "amphetamine-dextroan",
                confidence: 0.71,
                origin: .cameraCapture
            )
        ]

        XCTAssertEqual(
            MedicationLabelInterpreter.offlineDraft(evidence).name,
            "Amphetamine - dextroamphetamine"
        )
    }

    @available(iOS 26.0, *)
    func testModelCannotAutofillAnUnsupportedRawNameFragment() {
        let candidates = LabelInterpretationCandidates(
            medicationNames: [LabelFieldCandidate(id: 1, value: "amphetamine-dextrzzz")],
            strengths: [],
            directions: [],
            quantities: [],
            refills: []
        )
        let selection = LabelFieldSelection(
            medicationNameID: 1,
            normalizedMedicationName: "amphetamine-dextrzzz",
            strengthID: 0,
            directionsID: 0,
            quantityID: 0,
            refillsID: 0
        )

        let result = MedicationLabelInterpreter.applying(
            selection,
            candidates: candidates,
            to: MedicationDraft()
        )

        XCTAssertEqual(result.name, "")
    }

    @available(iOS 26.0, *)
    func testZeroSelectionClearsAmbiguousStructuredCandidates() {
        let candidates = LabelInterpretationCandidates(
            medicationNames: [],
            strengths: [
                LabelFieldCandidate(id: 1, value: "5 mg"),
                LabelFieldCandidate(id: 2, value: "10 mg")
            ],
            directions: [],
            quantities: [],
            refills: []
        )
        let selection = LabelFieldSelection(
            medicationNameID: 0,
            normalizedMedicationName: "",
            strengthID: 0,
            directionsID: 0,
            quantityID: 0,
            refillsID: 0
        )

        let result = MedicationLabelInterpreter.applying(
            selection,
            candidates: candidates,
            to: MedicationDraft(strength: "5 mg")
        )

        XCTAssertEqual(result.strength, "")
    }
}
