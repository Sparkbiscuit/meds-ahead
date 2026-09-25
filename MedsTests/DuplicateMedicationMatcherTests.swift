import XCTest
@testable import Meds

/// A second bottle of something already tracked, saved as new, splits one
/// supply into two counts and rings every reminder twice. The matcher finds
/// what it might be; it never decides, and it never matches a different
/// strength.
final class DuplicateMedicationMatcherTests: XCTestCase {
    private func furosemide(
        ndc: String = "",
        rxNorm: String = "",
        strength: String = "20 mg",
        person: String = "",
        archived: Bool = false
    ) -> Medication {
        Medication(
            name: "Furosemide",
            strength: strength,
            productIdentifier: ndc,
            productIdentifierType: ndc.isEmpty ? "" : "NDC",
            isArchived: archived,
            personName: person,
            rxNormCode: rxNorm
        )
    }

    /// A scanned bottle whose code the label vouched for, as the interpreter
    /// leaves it.
    private func identifiedDraft(ndc: String, name: String = "Furosemide", strength: String = "20 mg") -> MedicationDraft {
        var draft = MedicationDraft(name: name, strength: strength, source: .scanned)
        draft.productIdentifier = ndc
        draft.productIdentifierType = "NDC"
        draft.nameProvenance = .ndc
        return draft
    }

    private func matches(_ draft: MedicationDraft, _ medications: [Medication]) -> [Medication] {
        DuplicateMedicationMatcher.matches(for: .init(draft: draft), among: medications)
    }

    func testAnotherPackageSizeOfTheSameProductMatches() {
        let tracked = furosemide(ndc: "00054-4297-25")
        // The same labeler and product, a different package, printed in the
        // ten-digit 5-4-1 layout: still one product.
        XCTAssertEqual(matches(identifiedDraft(ndc: "00054-4297-31"), [tracked]).map(\.id), [tracked.id])
        XCTAssertEqual(matches(identifiedDraft(ndc: "00054-4297-3"), [tracked]).map(\.id), [tracked.id])
        XCTAssertTrue(matches(identifiedDraft(ndc: "00054-4298-25", name: "Something else"), [tracked]).isEmpty,
                      "a different product code is a different product")
    }

    /// A code the label printed but did not vouch for filled nothing, so it
    /// cannot say which medication this is either.
    func testACodeThatWasOnlyReadMatchesNothing() {
        let tracked = furosemide(ndc: "00054-4297-25")
        var draft = identifiedDraft(ndc: "00054-4297-25", name: "Torsemide")
        draft.nameProvenance = .strengthAnchored
        XCTAssertTrue(matches(draft, [tracked]).isEmpty)
    }

    func testTheSameRxNormConceptMatchesUnderAnotherName() {
        let tracked = furosemide(rxNorm: "310429")
        var draft = MedicationDraft(name: "Lasix", strength: "20 mg", source: .scanned)
        draft.rxNormCode = "310429"
        XCTAssertEqual(matches(draft, [tracked]).map(\.id), [tracked.id])

        var healthCoded = MedicationDraft(name: "Lasix", strength: "")
        healthCoded.productIdentifier = "310429"
        healthCoded.productIdentifierType = "RxNorm"
        XCTAssertEqual(matches(healthCoded, [tracked]).map(\.id), [tracked.id], "an RxNorm product identifier is the same code")
    }

    func testTheSameNameAndStrengthMatchWrittenAnyWay() {
        let tracked = furosemide()
        XCTAssertEqual(matches(MedicationDraft(name: "  furosemide", strength: "20MG"), [tracked]).map(\.id), [tracked.id])
        XCTAssertEqual(matches(MedicationDraft(name: "FUROSEMIDE", strength: "20 mg"), [tracked]).map(\.id), [tracked.id])
    }

    func testADifferentStrengthNeverMatches() {
        let tracked = furosemide(ndc: "00054-4297-25", rxNorm: "310429")
        XCTAssertTrue(matches(MedicationDraft(name: "Furosemide", strength: "40 mg"), [tracked]).isEmpty)
        // Whatever the codes say: a 40 mg bottle in a 20 mg count doubles
        // every dose it forecasts.
        var coded = identifiedDraft(ndc: "00054-4297-25", strength: "40 mg")
        coded.rxNormCode = "310429"
        XCTAssertTrue(matches(coded, [tracked]).isEmpty)
        // Words beside the amount are part of the strength.
        let metoprolol = Medication(name: "Metoprolol", strength: "25 mg")
        XCTAssertTrue(matches(MedicationDraft(name: "Metoprolol", strength: "25 mg ER"), [metoprolol]).isEmpty)
        // A strength not yet known confirms nothing.
        XCTAssertTrue(matches(MedicationDraft(name: "Furosemide", strength: ""), [tracked]).isEmpty)
    }

    /// One amount written two ways is not a different strength for a code match.
    func testACodeMatchSurvivesAStrengthWrittenAnotherWay() {
        let tracked = Medication(
            name: "Sulfamethoxazole / Trimethoprim",
            strength: "800 mg/160 mg",
            productIdentifier: "00093-0089-01",
            productIdentifierType: "NDC"
        )
        let draft = identifiedDraft(ndc: "00093-0089-05", name: "Sulfamethoxazole / Trimethoprim", strength: "800-160 mg")
        XCTAssertEqual(matches(draft, [tracked]).map(\.id), [tracked.id])
    }

    func testArchivedMedicationsAreLeftOut() {
        let archived = furosemide(ndc: "00054-4297-25", archived: true)
        XCTAssertTrue(matches(identifiedDraft(ndc: "00054-4297-25"), [archived]).isEmpty)
        XCTAssertTrue(matches(MedicationDraft(name: "Furosemide", strength: "20 mg"), [archived]).isEmpty)
    }

    func testTwoPeopleTakingTheSameDrugAreBothReturnedWithTheirNames() {
        let sam = furosemide(person: "Sam")
        let alex = furosemide(person: "Alex")
        let found = matches(MedicationDraft(name: "Furosemide", strength: "20 mg"), [sam, alex])
        XCTAssertEqual(Set(found.map(\.id)), [sam.id, alex.id])
        XCTAssertEqual(found.map(DuplicateMedicationMatcher.description(of:)), [
            "Furosemide 20 mg · for Alex",
            "Furosemide 20 mg · for Sam"
        ])
        XCTAssertEqual(DuplicateMedicationMatcher.description(of: furosemide()), "Furosemide 20 mg")
    }

    /// A manual entry has no code of its own, and its name and strength are
    /// all it can match by, even against a medication that has codes.
    func testAManualDraftMatchesByNameAndStrengthOnly() {
        let coded = furosemide(ndc: "00054-4297-25", rxNorm: "310429")
        let draft = MedicationDraft(name: "Furosemide", strength: "20 mg")
        XCTAssertEqual(draft.source, .manual)
        XCTAssertEqual(matches(draft, [coded]).map(\.id), [coded.id])
        XCTAssertTrue(matches(MedicationDraft(name: "Lasix", strength: "20 mg"), [coded]).isEmpty,
                      "another name with no code to link it is not a match")
        XCTAssertTrue(matches(MedicationDraft(name: "", strength: "20 mg"), [coded]).isEmpty)
    }
}
