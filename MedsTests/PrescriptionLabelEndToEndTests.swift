import XCTest
@testable import Meds

/// Whole-label checks against the shapes real pharmacy labels take. Individual
/// parser rules can each look correct while the assembled draft still reaches the
/// review screen empty, which is the failure that actually costs someone time.
final class PrescriptionLabelEndToEndTests: XCTestCase {
    private func evidence(_ lines: [String]) -> [ScanEvidence] {
        let capture = UUID()
        return lines.enumerated().map { index, value in
            ScanEvidence(kind: .text, value: value, confidence: 0.9,
                         origin: .cameraCapture, captureID: capture, lineIndex: index)
        }
    }

    /// A pharmacy prints its own wording, not RxNorm's canonical name. Requiring a
    /// vocabulary match emptied the name field on labels like this one.
    func testStimulantLabelFillsEveryFieldItPrints() {
        let draft = MedicationLabelInterpreter.offlineDraft(evidence([
            "WALGREENS #04821", "1200 MAIN ST", "SPRINGFIELD MA 01103",
            "RX# 8842197", "DOE, JOHN",
            "AMPHETAMINE SALT COMBO 20 MG TAB",
            "TAKE 1 TABLET BY MOUTH TWICE DAILY",
            "QTY: 60", "NO REFILLS REMAINING",
            "DR. A. GREENE", "EXP 04/28"
        ]))

        XCTAssertEqual(draft.name, "Amphetamine Salt Combo")
        XCTAssertEqual(draft.strength, "20 mg")
        XCTAssertEqual(draft.directions, "TAKE 1 TABLET BY MOUTH TWICE DAILY")
        XCTAssertEqual(draft.currentSupply, 60)
        XCTAssertEqual(draft.refillsRemaining, 0)
        XCTAssertEqual(draft.form, .tablet)
    }

    /// A name the vocabulary does recognise is still normalised to its spelling.
    func testVocabularyStillCorrectsARecognisedName() {
        let draft = MedicationLabelInterpreter.offlineDraft(evidence([
            "FUROSEMIDE 20 MG TABLET",
            "TAKE ONE TABLET TWICE DAILY",
            "QTY: 60"
        ]))

        XCTAssertEqual(draft.name, "Furosemide")
        XCTAssertEqual(draft.strength, "20 mg")
        XCTAssertEqual(draft.currentSupply, 60)
    }

    func testNameProvenanceGatesTheFallback() {
        let anchored = ScanParser.parse(evidence([
            "ATORVASTATIN CALCIUM 40 MG TAB", "TAKE ONE TABLET AT BEDTIME"
        ]))
        XCTAssertEqual(anchored.nameProvenance, .strengthAnchored)

        // No strength on the label, so the only name-shaped line is a guess.
        let loose = ScanParser.parse(evidence([
            "SPRINGFIELD FAMILY PHARMACY", "OPEN 9 TO 6", "CALL FOR REFILLS"
        ]))
        XCTAssertEqual(loose.nameProvenance, .soleCandidate)
        XCTAssertFalse(loose.name.isEmpty, "parser should still report its guess")
        // ...and the interpreter must refuse to promote that guess to the name field.
        XCTAssertTrue(MedicationLabelInterpreter.offlineDraft(evidence([
            "SPRINGFIELD FAMILY PHARMACY", "OPEN 9 TO 6", "CALL FOR REFILLS"
        ])).name.isEmpty)
    }

    func testNameResidueIsTidiedNotMangled() {
        XCTAssertEqual(ScanParser.tidiedNameResidue("AMPHETAMINE SALT COMBO  TAB"), "AMPHETAMINE SALT COMBO")
        XCTAssertEqual(ScanParser.tidiedNameResidue("Lisinopril   tabs"), "Lisinopril")
        // Word boundaries: these merely contain the abbreviations.
        XCTAssertEqual(ScanParser.tidiedNameResidue("Acetabular"), "Acetabular")
        XCTAssertEqual(ScanParser.tidiedNameResidue("Capsaicin"), "Capsaicin")
        XCTAssertEqual(ScanParser.tidiedNameResidue("Solifenacin"), "Solifenacin")
    }

    /// An ambiguous line must still yield nothing rather than a guess at a drug name.
    func testAmbiguousLabelDoesNotInventAName() {
        let draft = MedicationLabelInterpreter.offlineDraft(evidence([
            "SPRINGFIELD FAMILY PHARMACY", "OPEN 9 TO 6", "CALL FOR REFILLS"
        ]))
        XCTAssertTrue(draft.name.isEmpty, "invented a name from label furniture: \(draft.name)")
    }
}
