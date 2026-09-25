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

    /// The banner names the drug itself, which is what the bottle in hand can
    /// be checked against, however the medication is shown elsewhere.
    func testTheBannerNamesTheDrugBehindANickname() {
        let nicknamed = Medication(name: "Tacrolimus", nickname: "Anti-rejection AM", brandName: "Prograf", strength: "1 mg", personName: "Sam")
        XCTAssertEqual(DuplicateMedicationMatcher.description(of: nicknamed), "Tacrolimus 1 mg (Prograf) · “Anti-rejection AM” · for Sam")
        let found = matches(MedicationDraft(name: "Tacrolimus", strength: "1 mg"), [nicknamed])
        XCTAssertEqual(found.map(\.id), [nicknamed.id], "matched by its name, not its nickname")
        XCTAssertEqual(DuplicateMedicationMatcher.description(of: Medication(name: "Lasix", brandName: "LASIX", strength: "20 mg")), "Lasix 20 mg",
                       "a brand that is the name is not said twice")
    }

    func testOneAmountWrittenAnotherWayIsTheSameStrength() {
        let tacrolimus = Medication(name: "Tacrolimus", strength: "1 mg")
        XCTAssertEqual(matches(MedicationDraft(name: "Tacrolimus", strength: "1.0 mg"), [tacrolimus]).map(\.id), [tacrolimus.id])
        let halfMilligram = Medication(name: "Tacrolimus", strength: "0.5 mg")
        XCTAssertEqual(matches(MedicationDraft(name: "Tacrolimus", strength: ".5 mg"), [halfMilligram]).map(\.id), [halfMilligram.id])
        let vitaminD = Medication(name: "Cholecalciferol", strength: "1,000 IU")
        XCTAssertEqual(matches(MedicationDraft(name: "Cholecalciferol", strength: "1000 IU"), [vitaminD]).map(\.id), [vitaminD.id])
        XCTAssertTrue(matches(MedicationDraft(name: "Tacrolimus", strength: "5 mg"), [halfMilligram]).isEmpty)
        XCTAssertTrue(matches(MedicationDraft(name: "Tacrolimus", strength: "0.75 mg"), [halfMilligram]).isEmpty)
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

    // MARK: - Products one name and strength cannot tell apart

    /// Rows as the shipped snapshots list them: Prograf is immediate release,
    /// taken twice a day; Astagraf XL is extended release, taken once; the
    /// generic is Prograf's clinical drug. Metformin and Glumetza likewise.
    private let directory = NDCDirectory(data: Data("""
        # Test snapshot
        003782046\ttacrolimus\t\t1 mg\tcapsule
        003787185\tmetformin hydrochloride\t\t500 mg\ttablet
        004690617\ttacrolimus\tPrograf\t1 mg\tcapsule
        004690677\ttacrolimus\tAstagraf XL\t1 mg\tcapsule
        680120002\tmetformin hydrochloride\tGlumetza\t500 mg\ttablet

        """.utf8))

    private let rxNormTable = RxNormTable(productsData: Data("""
        # Test RxNorm slice
        003782046\t198377\t
        003787185\t861007\t
        004690617\t108513\t198377
        004690677\t1431982\t1431980
        680120002\t861018\t1807915

        """.utf8))

    /// A bottle whose code filled the review, as an accepted scan or Use This
    /// Product leaves it.
    private func accepted(_ rendering: String, directory: NDCDirectory? = nil, rxNormTable: RxNormTable? = nil) throws -> MedicationDraft {
        let directory = directory ?? self.directory
        let table = rxNormTable ?? self.rxNormTable
        let code = try XCTUnwrap(NationalDrugCode.candidates(fromRendering: rendering).first)
        let product = try XCTUnwrap(directory.product(for: code))
        var draft = MedicationDraft(
            name: NDCIdentification.displayName(for: product),
            brandName: product.brandName,
            strength: product.strength,
            form: product.form,
            source: .scanned
        )
        draft.productIdentifier = code.hyphenated
        draft.productIdentifierType = "NDC"
        draft.rxNormCode = table.product(for: code)?.rxcui ?? ""
        draft.nameProvenance = .ndc
        return draft
    }

    private func tracked(_ draft: MedicationDraft) -> Medication {
        Medication(
            name: draft.name,
            brandName: draft.brandName,
            strength: draft.strength,
            form: draft.form,
            productIdentifier: draft.productIdentifier,
            productIdentifierType: draft.productIdentifierType,
            source: draft.source,
            rxNormCode: draft.rxNormCode
        )
    }

    private func coded(_ draft: MedicationDraft, _ medications: [Medication]) -> [Medication] {
        DuplicateMedicationMatcher.matches(for: .init(draft: draft), among: medications, directory: directory, rxNormTable: rxNormTable)
    }

    /// Both "tacrolimus 1 mg capsule" to the directory. Adding the extended-
    /// release bottle to the immediate-release count would run it on twice-a-
    /// day reminders.
    func testAnExtendedReleaseBottleIsNotItsImmediateReleaseNamesake() throws {
        let prograf = tracked(try accepted("0469-0617-73"))
        let astagraf = try accepted("0469-0677-73")
        XCTAssertEqual(astagraf.name, prograf.name)
        XCTAssertEqual(astagraf.strength, prograf.strength)
        XCTAssertTrue(coded(astagraf, [prograf]).isEmpty, "Astagraf XL offered as Prograf")

        // Each rule on its own, with the brands left out of it.
        let unbranded = tracked(try accepted("0469-0617-73"))
        unbranded.brandName = ""
        var rxNormOnly = MedicationDraft(name: "Tacrolimus", strength: "1 mg")
        rxNormOnly.rxNormCode = astagraf.rxNormCode
        XCTAssertTrue(coded(rxNormOnly, [unbranded]).isEmpty, "different clinical drugs")
        unbranded.rxNormCode = ""
        var ndcOnly = astagraf
        ndcOnly.brandName = ""
        ndcOnly.rxNormCode = ""
        XCTAssertTrue(coded(ndcOnly, [unbranded]).isEmpty, "different products")

        // Entered by hand, with the brand the name brings: the brands disagree.
        let typed = Medication(name: "Tacrolimus", brandName: "Prograf", strength: "1 mg")
        XCTAssertTrue(coded(astagraf, [typed]).isEmpty, "different brands")
        var typedAstagraf = MedicationDraft(name: "Tacrolimus", brandName: "Astagraf XL", strength: "1 mg")
        XCTAssertTrue(matches(typedAstagraf, [prograf]).isEmpty)
        typedAstagraf.brandName = ""
        XCTAssertEqual(matches(typedAstagraf, [prograf]).map(\.id), [prograf.id],
                       "with nothing to tell them apart the banner asks, naming the brand it would join")
        XCTAssertEqual(DuplicateMedicationMatcher.description(of: prograf), "Tacrolimus 1 mg (Prograf)")
    }

    func testGlumetzaIsNotImmediateReleaseMetformin() throws {
        let metformin = tracked(try accepted("0378-7185-01"))
        let glumetza = try accepted("68012-002-10")
        XCTAssertEqual(glumetza.name, metformin.name)
        XCTAssertTrue(coded(glumetza, [metformin]).isEmpty)
        XCTAssertTrue(coded(try accepted("0378-7185-05"), [tracked(glumetza)]).isEmpty)
    }

    /// A generic is its brand's clinical drug, so the generic bottle a
    /// pharmacy substitutes still finds the brand tracked, and says which.
    func testAGenericBottleFindsItsBrandByClinicalDrug() throws {
        let prograf = tracked(try accepted("0469-0617-73"))
        let generic = try accepted("0378-2046-01")
        XCTAssertNotEqual(generic.productIdentifier, prograf.productIdentifier)
        XCTAssertEqual(coded(generic, [prograf]).map(\.id), [prograf.id])
        let trackedGeneric = tracked(generic)
        XCTAssertEqual(coded(try accepted("0469-0617-11"), [trackedGeneric]).map(\.id), [trackedGeneric.id], "and the brand finds the generic")
    }

    /// A code the label printed but did not vouch for is kept on the
    /// medication as read. When the directory lists it as something else, it
    /// is a misreading, and it cannot say this bottle is a different product.
    func testATrackedCodeThatNamesSomethingElseDoesNotBlockTheName() throws {
        let misread = Medication(name: "Tacrolimus", strength: "1 mg", productIdentifier: "00378-7185-01", productIdentifierType: "NDC")
        XCTAssertEqual(coded(try accepted("0469-0617-73"), [misread]).map(\.id), [misread.id])
        misread.productIdentifier = "12345-6789-01"
        XCTAssertEqual(coded(try accepted("0469-0617-73"), [misread]).map(\.id), [misread.id], "a code the directory does not list")
    }

    /// The snapshots that ship keep the two tacrolimus products apart.
    func testTheShippedTablesTellImmediateAndExtendedReleaseTacrolimusApart() throws {
        let prograf = tracked(try accepted("0469-0617-73", directory: .shared, rxNormTable: .shared))
        let astagraf = try accepted("0469-0677-73", directory: .shared, rxNormTable: .shared)
        let generic = try accepted("0378-2046-01", directory: .shared, rxNormTable: .shared)
        XCTAssertEqual(astagraf.name, prograf.name)
        XCTAssertEqual(astagraf.strength, prograf.strength)
        XCTAssertTrue(DuplicateMedicationMatcher.matches(for: .init(draft: astagraf), among: [prograf]).isEmpty)
        XCTAssertEqual(DuplicateMedicationMatcher.matches(for: .init(draft: generic), among: [prograf]).map(\.id), [prograf.id])
    }
}
