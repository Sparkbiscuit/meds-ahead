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

    func testSertralineLabelReturnsTheCorrectDrugBrandAndStrength() {
        let draft = MedicationLabelInterpreter.offlineDraft(evidence([
            "WALGREENS PHARMACY", "1200 MAIN ST", "SPRINGFIELD MA 01103",
            "RX# 8842197", "DOE, JOHN",
            "SERTRALINE HCL 100MG TABLET",
            "TAKE 1 TABLET BY MOUTH ONCE DAILY",
            "QTY: 30"
        ]))

        XCTAssertEqual(draft.name, "Sertraline")
        XCTAssertEqual(draft.brandName, "Zoloft")
        XCTAssertEqual(draft.strength, "100 mg")
    }

    func testSertralineLabelJunkCandidateCannotBecomeRisedronate() {
        let draft = MedicationLabelInterpreter.offlineDraft(evidence([
            "WALGREENS PHARMACY", "1200 MAIN ST", "SPRINGFIELD MA 01103",
            "RX# 8842197", "DOE, JOHN",
            "SERTRALINE HCL 100MG TABLET",
            "EDRONATE",
            "TAKE 1 TABLET BY MOUTH ONCE DAILY",
            "QTY: 30"
        ]))

        XCTAssertEqual(draft.name, "Sertraline")
        XCTAssertNotEqual(draft.name, "Risedronate")
        XCTAssertEqual(draft.brandName, "Zoloft")
        XCTAssertNotEqual(draft.brandName, "Actonel")
        XCTAssertEqual(draft.strength, "100 mg")
    }

    func testHospitalPatientAddressCannotBecomeTheMedicationName() {
        let draft = MedicationLabelInterpreter.offlineDraft(evidence([
            "BOSTON CHILDREN'S HOSPITAL", "300 LONGWOOD AVENUE", "BOSTON MA 02115",
            "RX# 7719204", "CHRISTOFORAKIS, LUKAS", "41 MAPLE TERRACE",
            "AZATHIOPRINE 50 MG TABLET",
            "TAKE 1 TABLET BY MOUTH ONCE DAILY",
            "QTY: 90"
        ]))

        XCTAssertEqual(draft.name, "Azathioprine")
        XCTAssertEqual(draft.brandName, "Imuran")
        XCTAssertEqual(draft.strength, "50 mg")
        for rejectedLine in [
            "BOSTON CHILDREN'S HOSPITAL", "300 LONGWOOD AVENUE", "BOSTON MA 02115",
            "CHRISTOFORAKIS, LUKAS", "41 MAPLE TERRACE"
        ] {
            XCTAssertNotEqual(draft.name, rejectedLine, rejectedLine)
        }
    }

    func testValganciclovirLabelReturnsTheCorrectDrugBrandAndStrength() {
        let draft = MedicationLabelInterpreter.offlineDraft(evidence([
            "VALGANCICLOVIR HCL 450 MG TABLET",
            "TAKE 1 TABLET BY MOUTH ONCE DAILY"
        ]))

        XCTAssertEqual(draft.name, "Valganciclovir")
        XCTAssertEqual(draft.brandName, "Valcyte")
        XCTAssertEqual(draft.strength, "450 mg")
    }

    // MARK: - Names that must never be invented

    /// A busy label joins into dozens of synthetic candidates. `FOLIC` on one line
    /// and `ACID` on the next form an exact vocabulary match for a medication that
    /// is nowhere in the bottle, and being the label's only match used to be enough.
    func testASyntheticExactMatchCannotOutvoteTheProductLine() {
        let draft = MedicationLabelInterpreter.offlineDraft(evidence([
            "SERTRALIN 50 MG",
            "FOLIC",
            "ACID"
        ]))

        XCTAssertNotEqual(draft.name, "Folic acid")
        XCTAssertNotEqual(draft.brandName, "Folvite")
        XCTAssertEqual(draft.name, "Sertraline")
    }

    /// Vocabulary keys dropped digits, so "vitamin b12" and "vitamin b6" collided
    /// and a B12 bottle resolved as B6 — a different vitamin, stated confidently.
    func testVitaminNumbersAreNotInterchangeable() {
        let draft = MedicationLabelInterpreter.offlineDraft(evidence([
            "VITAMIN B12 1000 MCG",
            "TAKE 1 TABLET BY MOUTH DAILY"
        ]))

        XCTAssertTrue(draft.name.lowercased().contains("b12"), "got \(draft.name)")
        XCTAssertFalse(draft.name.lowercased().contains("b6"))
    }

    /// A manufacturer, a prescriber and an insurance line all sit next to the
    /// strength on a real label. Only a name printed on the strength line itself may
    /// stand without the vocabulary confirming it.
    func testLabelFurnitureBesideTheStrengthIsNotAName() {
        for furniture in ["PFIZER INC", "JOHN SMITH", "MEMBER ID: 1234", "42 ELM"] {
            let draft = MedicationLabelInterpreter.offlineDraft(evidence([
                "50 MG TABLET",
                furniture
            ]))
            XCTAssertEqual(draft.name, "", "\(furniture) reached the name field")
            XCTAssertEqual(draft.nameProvenance, .none)
        }
    }

    /// The reason the strength-anchored path exists: a pharmacy's own wording for a
    /// drug the vocabulary lists under four salt names, printed on the strength line.
    func testAPharmacysOwnWordingOnTheStrengthLineStillSurvives() {
        let draft = MedicationLabelInterpreter.offlineDraft(evidence([
            "AMPHETAMINE SALT COMBO 20 MG TAB",
            "TAKE 1 TABLET BY MOUTH TWICE DAILY"
        ]))

        XCTAssertEqual(draft.name, "Amphetamine Salt Combo")
        XCTAssertEqual(draft.nameProvenance, .strengthAnchored)
    }

    /// A name on its own line above the strength is the commonest label layout, and
    /// must keep working now that adjacent reads need confirming.
    func testANameOnTheLineAboveTheStrengthStillResolves() {
        let draft = MedicationLabelInterpreter.offlineDraft(evidence([
            "SERTRALINE HCL",
            "100 MG TABLET",
            "TAKE 1 TABLET BY MOUTH DAILY"
        ]))

        XCTAssertEqual(draft.name, "Sertraline")
        XCTAssertEqual(draft.brandName, "Zoloft")
    }

    /// A real sertraline bottle put a clipped sig into the name field: the OCR line
    /// carried the strength, so the name search treated it as the product line.
    func testASigCarryingTheStrengthIsNotTheProductLine() {
        let draft = MedicationLabelInterpreter.offlineDraft(evidence([
            "1 WEEK, THEN INCREAS EVERY EVENING 50 MG",
            "QTY: 30"
        ]))

        XCTAssertEqual(draft.name, "")
        XCTAssertEqual(draft.nameProvenance, .none)
        XCTAssertEqual(draft.strength, "50 mg")
    }

    /// The same bottle read correctly once the product line survives separately.
    func testTheProductLineStillWinsOnThatSameLabel() {
        let draft = MedicationLabelInterpreter.offlineDraft(evidence([
            "WALGREENS #04821",
            "TAKE 1/2 A TABLET BY I",
            "1 WEEK, THEN INCREAS EVERY EVENING IF TOLE",
            "SERTRALINE HCL 50 MG",
            "QTY: 30"
        ]))

        XCTAssertEqual(draft.name, "Sertraline")
        XCTAssertEqual(draft.brandName, "Zoloft")
    }

    /// The shape rule that separates a pharmacy's own wording from a clipped sig.
    func testUnconfirmedNamesMustLookLikeAName() {
        XCTAssertTrue(ScanParser.looksLikeMedicationName("Amphetamine Salt Combo"))
        XCTAssertTrue(ScanParser.looksLikeMedicationName("Sertraline HCl"))
        XCTAssertFalse(ScanParser.looksLikeMedicationName("1 Week, Then Increas Every Evening"))
        XCTAssertFalse(ScanParser.looksLikeMedicationName("Then Increas Every Evening If Tole"))
        XCTAssertFalse(ScanParser.looksLikeMedicationName("Take 1 Tablet By Mouth Daily"))
    }
}
