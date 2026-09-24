import XCTest
@testable import Meds

/// A label's QTY is what the pharmacy dispensed. Filled in as the current
/// amount it reads high for every dose already taken from the bottle, which is
/// the direction that runs someone out, so the review screen offers it instead.
final class LabelDispensedQuantityTests: XCTestCase {
    func testAScannedLabelsQuantityIsOfferedAndTheFieldStartsBlank() {
        let draft = MedicationLabelInterpreter.offlineDraft([
            ScanEvidence(kind: .text, value: "RX# 5550123", confidence: 0.9),
            ScanEvidence(kind: .text, value: "LISINOPRIL 10 MG TABLET", confidence: 0.9),
            ScanEvidence(kind: .text, value: "TAKE 1 TABLET BY MOUTH DAILY", confidence: 0.9),
            ScanEvidence(kind: .text, value: "QTY: 90", confidence: 0.9)
        ])

        XCTAssertEqual(draft.currentSupply, 90, "the parser still reads the label's count")
        XCTAssertEqual(draft.labelDispensedQuantity, 90)
        XCTAssertEqual(draft.labelDispensedNote, "Label says 90 dispensed")
        XCTAssertEqual(draft.initialCurrentAmountText, "", "a dispensed count must never become the current amount on its own")
    }

    /// The Use button writes the quantity as shown, to two decimals. Offered at
    /// the label's full precision, the field never matched it again: the button
    /// stayed "Use", as if the tap had done nothing.
    func testALabelsExtraDecimalsAreOfferedAsTheNumberTheButtonWrites() {
        let draft = MedicationLabelInterpreter.offlineDraft([
            ScanEvidence(kind: .text, value: "RX# 5550123", confidence: 0.9),
            ScanEvidence(kind: .text, value: "AMOXICILLIN 400 MG/5 ML SUSP", confidence: 0.9),
            ScanEvidence(kind: .text, value: "TAKE 5 ML BY MOUTH TWICE DAILY", confidence: 0.9),
            ScanEvidence(kind: .text, value: "QTY: 473.176", confidence: 0.9)
        ])

        XCTAssertEqual(draft.currentSupply, 473.176)
        let offered = draft.labelDispensedQuantity
        XCTAssertEqual(offered, 473.18)
        XCTAssertEqual(draft.labelDispensedNote?.contains("473.18"), true, draft.labelDispensedNote ?? "no note")
        // The editor shows "Using" when the field parses back to the offered
        // quantity, so what the button writes has to parse back to it exactly.
        XCTAssertEqual(offered.flatMap { Double.medicationQuantity(from: $0.medicationQuantityText) }, offered)
    }

    /// Below the second decimal a label's count shows as 0, and "Use 0" would
    /// only put a count of nothing one tap away.
    func testNoNoteForAQuantityThatShowsAsZero() {
        let draft = MedicationDraft(name: "Furosemide", currentSupply: 0.001, source: .scanned)
        XCTAssertNil(draft.labelDispensedQuantity)
        XCTAssertNil(draft.labelDispensedNote)
    }

    func testNoNoteWhenTheLabelPrintedNoQuantity() {
        let draft = MedicationDraft(name: "Furosemide", source: .scanned)

        XCTAssertNil(draft.labelDispensedQuantity)
        XCTAssertNil(draft.labelDispensedNote)
        XCTAssertEqual(draft.initialCurrentAmountText, "")
    }

    /// Nothing to offer: "Use 0" would only put a count of nothing one tap away.
    func testNoNoteForAQuantityThatCountsNothing() {
        for quantity in [0, -30, .nan, .infinity] as [Double] {
            let draft = MedicationDraft(name: "Furosemide", currentSupply: quantity, source: .scanned)
            XCTAssertNil(draft.labelDispensedNote, "\(quantity)")
            XCTAssertEqual(draft.initialCurrentAmountText, "", "\(quantity)")
        }
    }

    func testManualAndHealthDraftsKeepTheirAmount() {
        let manual = MedicationDraft(name: "Furosemide", currentSupply: 30, source: .manual)
        XCTAssertNil(manual.labelDispensedNote)
        XCTAssertEqual(manual.initialCurrentAmountText, "30")

        let health = MedicationDraft(name: "Melatonin", currentSupply: 12, source: .appleHealth)
        XCTAssertNil(health.labelDispensedNote)
        XCTAssertEqual(health.initialCurrentAmountText, "12")
    }
}
