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

    /// "DR" on the product line is the delayed-release form. The address test
    /// read it as "Drive", and the name of every delayed-release label came out
    /// blank, a transplant patient's mycophenolic acid among them.
    func testADelayedReleaseProductLineKeepsItsName() {
        let draft = MedicationLabelInterpreter.offlineDraft(evidence([
            "RIVERSIDE PHARMACY", "RX# 5521093", "PEMBERTON, ELLIS",
            "MYCOPHENOLIC ACID DR 360 MG TABLET",
            "TAKE 2 TABLETS BY MOUTH TWICE DAILY",
            "QTY: 120"
        ]))

        XCTAssertEqual(draft.name, "Mycophenolic acid")
        XCTAssertEqual(draft.nameProvenance, .vocabulary)
        XCTAssertEqual(draft.strength, "360 mg")

        // Only the strength's own line is read that way: a street or a
        // prescriber beside the strength is still not a name.
        for line in ["450 OAK DR", "DR. A. GREENE"] {
            let beside = MedicationLabelInterpreter.offlineDraft(evidence([line, "360 MG TABLET", "QTY: 120"]))
            XCTAssertEqual(beside.name, "", line)
        }
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
            "RIVERSIDE CHILDREN'S HOSPITAL", "300 HARBOR AVENUE", "SPRINGFIELD MA 01104",
            "RX# 4402917", "PEMBERTON, ELLIS", "18 ORCHARD TERRACE",
            "AZATHIOPRINE 50 MG TABLET",
            "TAKE 1 TABLET BY MOUTH ONCE DAILY",
            "QTY: 90"
        ]))

        XCTAssertEqual(draft.name, "Azathioprine")
        XCTAssertEqual(draft.brandName, "Imuran")
        XCTAssertEqual(draft.strength, "50 mg")
        for rejectedLine in [
            "RIVERSIDE CHILDREN'S HOSPITAL", "300 HARBOR AVENUE", "SPRINGFIELD MA 01104",
            "PEMBERTON, ELLIS", "18 ORCHARD TERRACE"
        ] {
            XCTAssertNotEqual(draft.name, rejectedLine, rejectedLine)
        }
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

    // MARK: - Text-heavy labels

    /// A sig that wraps over three lines, restates the dose in parentheses and
    /// opens mid-sentence after the wrap. The restated dose used to be taken for
    /// the strength, the name search ran on that sig line, found nothing, and the
    /// product line below it was never consulted.
    func testAWrappedSigRestatingTheDoseIsNotTheProductLine() {
        let draft = MedicationLabelInterpreter.offlineDraft(evidence([
            "WALGREENS #04821", "1200 MAIN ST", "SPRINGFIELD MA 01103",
            "RX# 8842197", "DOE, JOHN",
            "TAKE 1 TABLET",
            "(25 MG) BY MOUTH EVERY 6 HOURS",
            "AS NEEDED FOR PAIN",
            "HYDROXYZINE HCL 25 MG TABLET",
            "QTY: 30", "NO REFILLS REMAINING",
            "DR. A. GREENE"
        ]))

        XCTAssertEqual(draft.name, "Hydroxyzine")
        XCTAssertEqual(draft.strength, "25 mg")
        XCTAssertEqual(draft.directions, "TAKE 1 TABLET (25 MG) BY MOUTH EVERY 6 HOURS AS NEEDED FOR PAIN")
        XCTAssertEqual(draft.currentSupply, 30)
        XCTAssertEqual(draft.refillsRemaining, 0)
    }

    /// Five lines of sig, the longest a label prints, assembled whole.
    func testAFiveLineSigAssemblesWhole() {
        let draft = MedicationLabelInterpreter.offlineDraft(evidence([
            "RX# 8842197",
            "TAKE 1 TABLET BY MOUTH",
            "EVERY MORNING WITH FOOD",
            "AND 2 TABLETS BY MOUTH",
            "EVERY EVENING WITH FOOD",
            "FOR 30 DAYS THEN STOP",
            "LISINOPRIL 10 MG TABLET",
            "QTY: 90"
        ]))

        XCTAssertEqual(draft.name, "Lisinopril")
        XCTAssertEqual(draft.strength, "10 mg")
        XCTAssertEqual(
            draft.directions,
            "TAKE 1 TABLET BY MOUTH EVERY MORNING WITH FOOD AND 2 TABLETS BY MOUTH EVERY EVENING WITH FOOD FOR 30 DAYS THEN STOP"
        )
        XCTAssertEqual(draft.currentSupply, 90)
    }

    /// A first line that passes the gate on its own is not the whole sig when
    /// the label carries on underneath it.
    func testATrustedFirstLineKeepsItsContinuation() {
        let draft = MedicationLabelInterpreter.offlineDraft(evidence([
            "TAKE 1 TABLET BY MOUTH EVERY 6 HOURS",
            "AS NEEDED FOR PAIN",
            "OXYCODONE HCL 5 MG TABLET",
            "QTY: 20"
        ]))

        XCTAssertEqual(draft.directions, "TAKE 1 TABLET BY MOUTH EVERY 6 HOURS AS NEEDED FOR PAIN")
        XCTAssertEqual(draft.name, "Oxycodone")
        XCTAssertEqual(draft.strength, "5 mg")
    }

    /// The line after the sig is often a warning sticker or the product line;
    /// neither continues the sig.
    func testASigDoesNotSwallowTheLineAfterIt() {
        let sticker = MedicationLabelInterpreter.offlineDraft(evidence([
            "TAKE 1 TABLET BY MOUTH DAILY",
            "MAY CAUSE DROWSINESS",
            "SERTRALINE HCL 50 MG TABLET"
        ]))
        XCTAssertEqual(sticker.directions, "TAKE 1 TABLET BY MOUTH DAILY")
        XCTAssertEqual(sticker.name, "Sertraline")

        let product = MedicationLabelInterpreter.offlineDraft(evidence([
            "TAKE 1 TABLET BY MOUTH DAILY",
            "SERTRALINE HCL 50 MG TABLET",
            "QTY: 30"
        ]))
        XCTAssertEqual(product.directions, "TAKE 1 TABLET BY MOUTH DAILY")
        XCTAssertEqual(product.name, "Sertraline")
        XCTAssertEqual(product.strength, "50 mg")
    }

    /// Sig vocabulary anywhere marks a line as directions for the purpose of
    /// choosing the product line; the field's own gate stays as strict as it was.
    func testSigVocabularyAnywhereMarksALineAsDirections() {
        XCTAssertTrue(ScanParser.isSigLike("(25 MG) BY MOUTH EVERY 6 HOURS"))
        XCTAssertTrue(ScanParser.isSigLike("WITH FOOD FOR 7 DAYS"))
        XCTAssertTrue(ScanParser.isSigLike("1 WEEK, THEN INCREAS EVERY EVENING 50 MG"))
        XCTAssertTrue(ScanParser.isSigLike("(2 TABLETS) AT BEDTIME"))
        XCTAssertFalse(ScanParser.isSigLike("SERTRALINE HCL 50 MG TABLET"))
        XCTAssertFalse(ScanParser.isSigLike("AMOXICILLIN 400 MG TABLETS FOR ORAL SUSPENSION"))
        XCTAssertFalse(ScanParser.isSigLike("DAILY MULTIVITAMIN 1000 IU"), "a product called Daily is a product")
    }

    // MARK: - The pharmacy card

    /// The label prints the pharmacy, its phone and the Rx number; the call a
    /// low-supply warning leads to needs all three.
    func testThePharmacyCardIsReadOffTheLabel() {
        let draft = ScanParser.parse(evidence([
            "WALGREENS #04821", "1200 MAIN ST, SPRINGFIELD MA 01103", "(413) 555-0123",
            "RX# 8842197", "DOE, JOHN",
            "SERTRALINE HCL 50 MG TABLET", "TAKE 1 TABLET BY MOUTH DAILY", "QTY: 30",
            "DR. A. GREENE 413-555-0199", "NPI 1234567890"
        ]))

        XCTAssertEqual(draft.pharmacyName, "Walgreens #04821")
        XCTAssertEqual(draft.pharmacyPhone, "(413) 555-0123", "the pharmacy's number, not the prescriber's")
        XCTAssertEqual(draft.rxNumber, "8842197")
    }

    func testAPharmacyIsNotInventedAndAFaxOrNPIIsNotItsPhone() {
        let draft = ScanParser.parse(evidence([
            "SERTRALINE HCL 50 MG TABLET", "TAKE 1 TABLET BY MOUTH DAILY",
            "FAX 413-555-0100", "NPI 1234567890", "RX 1234567-01"
        ]))
        XCTAssertEqual(draft.pharmacyName, "")
        XCTAssertEqual(draft.pharmacyPhone, "")
        XCTAssertEqual(draft.rxNumber, "1234567-01", "the fill suffix comes along")

        let hospital = ScanParser.parse(evidence(["RIVERSIDE CHILDREN'S HOSPITAL PHARMACY", "413-555-0147", "TACROLIMUS 1 MG CAPSULE"]))
        XCTAssertEqual(hospital.pharmacyName, "Riverside Children's Hospital Pharmacy")
        XCTAssertEqual(hospital.pharmacyPhone, "(413) 555-0147")
        XCTAssertFalse(ScanParser.isPharmacyLine("TAKE 1 TABLET BY MOUTH DAILY"))
        XCTAssertTrue(ScanParser.isPharmacyLine("Rite Aid #1234"))
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
