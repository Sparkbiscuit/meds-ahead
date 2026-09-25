import XCTest
@testable import Meds

final class HealthMedicationMapperTests: XCTestCase {
    private func summary(
        _ displayText: String,
        nickname: String = "",
        form: HealthMedicationSummary.Form = .unknown,
        hasSchedule: Bool = true,
        rxNormCode: String? = nil
    ) -> HealthMedicationSummary {
        HealthMedicationSummary(
            id: displayText,
            displayText: displayText,
            nickname: nickname,
            form: form,
            hasSchedule: hasSchedule,
            isArchived: false,
            rxNormCode: rxNormCode
        )
    }

    func testAnRxNormStyleNameSplitsIntoItsFields() {
        let draft = HealthMedicationMapper.draft(for: summary(
            "sertraline 50 MG Oral Tablet [Zoloft]",
            form: .tablet,
            rxNormCode: "312938"
        ))

        XCTAssertEqual(draft.name, "Sertraline")
        XCTAssertEqual(draft.brandName, "Zoloft")
        XCTAssertEqual(draft.strength, "50 mg")
        XCTAssertEqual(draft.form, .tablet)
        XCTAssertEqual(draft.productIdentifier, "312938")
        XCTAssertEqual(draft.productIdentifierType, "RxNorm")
        XCTAssertEqual(draft.source, .appleHealth)
        XCTAssertEqual(draft.nameProvenance, .appleHealth)
        XCTAssertFalse(draft.isAsNeeded)
        XCTAssertTrue(draft.evidence.isEmpty)
    }

    func testAPlainNameBorrowsTheReferenceBrandAndHealthsForm() {
        let draft = HealthMedicationMapper.draft(for: summary("Tacrolimus 1 mg", form: .capsule, hasSchedule: false))

        XCTAssertEqual(draft.name, "Tacrolimus")
        XCTAssertEqual(draft.brandName, "Prograf")
        XCTAssertEqual(draft.strength, "1 mg")
        XCTAssertEqual(draft.form, .capsule)
        XCTAssertTrue(draft.isAsNeeded, "no schedule in Health means as needed here until the person says otherwise")
    }

    func testABrandNameResolvesToItsGeneric() {
        let draft = HealthMedicationMapper.draft(for: summary("Zoloft 100mg tablet"))
        XCTAssertEqual(draft.name, "Sertraline")
        XCTAssertEqual(draft.brandName, "Zoloft")
        XCTAssertEqual(draft.strength, "100 mg")
        XCTAssertEqual(draft.form, .tablet, "inferred from the text when Health gives no form")
    }

    /// A custom entry is the person's own word for their medication and is kept as typed.
    func testATypedNameIsKeptAsTyped() {
        let draft = HealthMedicationMapper.draft(for: summary("Ellis's evening vitamin", nickname: "Gummy", form: .unknown))

        XCTAssertEqual(draft.name, "Ellis's evening vitamin")
        XCTAssertEqual(draft.nickname, "Gummy")
        XCTAssertEqual(draft.brandName, "")
        XCTAssertEqual(draft.strength, "")
        XCTAssertEqual(draft.productIdentifier, "")
    }

    func testRecentDosesRideAlongForTheReviewScreen() {
        var shared = summary("Ondansetron 4 mg", hasSchedule: false)
        let doses = [ImportedDose(date: Date(timeIntervalSince1970: 1_800_000_000), quantity: 1),
                     ImportedDose(date: Date(timeIntervalSince1970: 1_800_100_000), quantity: 2)]
        shared.recentTakenDoses = doses

        let draft = HealthMedicationMapper.draft(for: shared)

        XCTAssertEqual(draft.importedDoses, doses)
        XCTAssertTrue(HealthMedicationMapper.draft(for: summary("Ondansetron 4 mg")).importedDoses.isEmpty)
    }

    /// Health's name for an extended-release medication loses its "ER" with
    /// the form words; the table's immediate-release brand must not take its
    /// place, and the name keeps the release instead.
    func testAnExtendedReleaseNameIsNotGivenTheImmediateReleaseBrand() {
        let typed = HealthMedicationMapper.draft(for: summary("Tacrolimus ER 1 mg", form: .capsule))
        XCTAssertEqual(typed.name, "Tacrolimus ER")
        XCTAssertEqual(typed.brandName, "", "never Prograf")

        let succinate = HealthMedicationMapper.draft(for: summary("Metoprolol succinate 25 MG Extended Release Oral Tablet"))
        XCTAssertEqual(succinate.name, "Metoprolol succinate")
        XCTAssertEqual(succinate.brandName, "Toprol XL", "the one release metoprolol succinate comes in")

        let glucophage = HealthMedicationMapper.draft(for: summary("Glucophage XR 500 mg"))
        XCTAssertEqual(glucophage.name, "Metformin")
        XCTAssertEqual(glucophage.brandName, "Glucophage XR")

        let branded = HealthMedicationMapper.draft(for: summary("tacrolimus 1 MG Extended Release Oral Capsule [Astagraf XL]"))
        XCTAssertEqual(branded.name, "Tacrolimus")
        XCTAssertEqual(branded.brandName, "Astagraf XL")
    }

    /// Astagraf XL and Prograf share the name tacrolimus; a Health entry for
    /// one is not "already in Meds Ahead" as the other.
    @MainActor
    func testANameMatchesOnlyWithinOneRelease() {
        let prograf = Medication(name: "Tacrolimus", brandName: "Prograf", strength: "1 mg")
        let astagraf = Medication(name: "Tacrolimus", brandName: "Astagraf XL", strength: "1 mg")

        let immediate = HealthMedicationMapper.draft(for: summary("Tacrolimus 1 mg"))
        XCTAssertEqual(HealthMedicationMapper.existingMedication(for: immediate, among: [astagraf]), nil)
        XCTAssertEqual(HealthMedicationMapper.existingMedication(for: immediate, among: [astagraf, prograf])?.id, prograf.id)

        let extended = HealthMedicationMapper.draft(for: summary("tacrolimus 1 MG Extended Release Oral Capsule [Astagraf XL]"))
        XCTAssertEqual(HealthMedicationMapper.existingMedication(for: extended, among: [prograf]), nil)
        XCTAssertEqual(HealthMedicationMapper.existingMedication(for: extended, among: [prograf, astagraf])?.id, astagraf.id)

        let typedExtended = HealthMedicationMapper.draft(for: summary("Tacrolimus ER 1 mg"))
        XCTAssertEqual(HealthMedicationMapper.existingMedication(for: typedExtended, among: [prograf]), nil)
    }

    /// By code as well as by name: RxNorm gives each release its own clinical
    /// drug, so widening a brand to its generic never joins Astagraf XL to a
    /// scanned Prograf bottle, for the "already in Meds Ahead" check or for
    /// the dose sync that charges the count.
    @available(iOS 26.0, *)
    @MainActor
    func testTheRxNormCodesOfTwoReleasesNeverMatch() {
        let prograf = Medication(name: "Tacrolimus", brandName: "Prograf", strength: "1 mg", rxNormCode: "108513")

        let astagraf = HealthMedicationMapper.draft(for: summary("Astagraf XL 1 mg", rxNormCode: "1431982"))
        XCTAssertNil(HealthMedicationMapper.existingMedication(for: astagraf, among: [prograf], rxNormTable: .shared))
        let sameProduct = HealthMedicationMapper.draft(for: summary("Prograf 1 mg", rxNormCode: "108513"))
        XCTAssertEqual(HealthMedicationMapper.existingMedication(for: sameProduct, among: [prograf], rxNormTable: .shared)?.id, prograf.id)

        let entry = HealthSharedMedication(id: "astagraf", rxNormCodes: ["1431982"], isArchived: false)
        XCTAssertTrue(HealthDoseSync.groups(of: [entry], matching: [prograf], table: .shared).isEmpty)
    }

    /// A release the entry states stays with it for a drug the brand table
    /// does not know, or whose brand is not the one on file, so an
    /// extended-release entry never reads as the immediate-release
    /// medication already here.
    @MainActor
    func testAReleaseStaysWithAnyDrug() {
        let nifedipine = HealthMedicationMapper.draft(for: summary("Nifedipine ER 30 mg"))
        XCTAssertEqual(nifedipine.name, "Nifedipine ER")
        XCTAssertNil(HealthMedicationMapper.existingMedication(for: nifedipine, among: [Medication(name: "Nifedipine", strength: "10 mg")]))

        let wellbutrin = HealthMedicationMapper.draft(for: summary("Wellbutrin XL 150 mg"))
        XCTAssertEqual(MedicationBrandIndex.release(ofName: wellbutrin.name, brand: wellbutrin.brandName), .extended)
        XCTAssertNil(HealthMedicationMapper.existingMedication(
            for: wellbutrin, among: [Medication(name: "Bupropion", brandName: "Wellbutrin", strength: "75 mg")]
        ))

        let rxNormName = HealthMedicationMapper.draft(for: summary("24 HR tacrolimus 1 MG Extended Release Oral Capsule"))
        XCTAssertEqual(rxNormName.name, "Tacrolimus ER", "RxNorm's leading duration is not part of the name")
        XCTAssertEqual(rxNormName.brandName, "")
    }

    /// An entry whose name states no release, coded as an extended-release
    /// product, is that product: not lent Prograf, and not the Prograf on file.
    @MainActor
    func testAnEntryTakesItsReleaseFromItsCode() {
        XCTAssertEqual(HealthMedicationMapper.release(ofRxNormCode: "1431982"), .extended, "Astagraf XL 1 mg")
        XCTAssertEqual(HealthMedicationMapper.release(ofRxNormCode: "1431980"), .extended, "tacrolimus 1 mg extended-release")
        XCTAssertEqual(HealthMedicationMapper.release(ofRxNormCode: "108513"), .immediate, "Prograf 1 mg")
        XCTAssertNil(HealthMedicationMapper.release(ofRxNormCode: "999999999"))

        var astagraf = summary("Tacrolimus 1 mg", rxNormCode: "1431982")
        astagraf.codedRelease = HealthMedicationMapper.release(ofRxNormCode: "1431982")
        let coded = HealthMedicationMapper.draft(for: astagraf)
        XCTAssertEqual(coded.name, "Tacrolimus ER")
        XCTAssertEqual(coded.brandName, "", "never Prograf")

        let prograf = Medication(name: "Tacrolimus", brandName: "Prograf", strength: "1 mg", rxNormCode: "108513")
        XCTAssertNil(HealthMedicationMapper.existingMedication(for: coded, among: [prograf], rxNormTable: .shared))

        var prografEntry = summary("Tacrolimus 1 mg", rxNormCode: "108513")
        prografEntry.codedRelease = HealthMedicationMapper.release(ofRxNormCode: "108513")
        let immediate = HealthMedicationMapper.draft(for: prografEntry)
        XCTAssertEqual(immediate.name, "Tacrolimus")
        XCTAssertEqual(immediate.brandName, "Prograf")
        XCTAssertEqual(HealthMedicationMapper.existingMedication(for: immediate, among: [prograf], rxNormTable: .shared)?.id, prograf.id)
    }

    /// Codes on both sides that name different clinical drugs are two
    /// medications, whatever their names say.
    @MainActor
    func testCodesThatDisagreeAreNotJoinedByName() {
        let entry = HealthMedicationMapper.draft(for: summary("Melatonin 5 mg", rxNormCode: "900001"))
        XCTAssertNil(HealthMedicationMapper.existingMedication(for: entry, among: [Medication(name: "Melatonin", rxNormCode: "900002")]))

        let uncoded = Medication(name: "Melatonin")
        XCTAssertEqual(HealthMedicationMapper.existingMedication(for: entry, among: [uncoded])?.id, uncoded.id, "a name still matches a medication without a code")
        let typed = HealthMedicationMapper.draft(for: summary("Melatonin 5 mg"))
        let coded = Medication(name: "Melatonin", rxNormCode: "900002")
        XCTAssertEqual(HealthMedicationMapper.existingMedication(for: typed, among: [coded])?.id, coded.id, "and an entry without one")
    }

    func testFormWordsAndRoutesAreNotPartOfTheName() {
        XCTAssertEqual(HealthMedicationMapper.cleanedName(from: "Metoprolol succinate 25 MG Extended Release Oral Tablet"), "Metoprolol succinate")
        XCTAssertEqual(HealthMedicationMapper.cleanedName(from: "Insulin glargine 100 units/mL injection pen"), "Insulin glargine")
        XCTAssertEqual(HealthMedicationMapper.cleanedName(from: "Prednisolone 15 mg/5 mL oral solution"), "Prednisolone")
    }

    @MainActor
    func testAnEntryAlreadyOnFileIsRecognised() {
        let sertraline = Medication(name: "Sertraline", brandName: "Zoloft", strength: "50 mg")
        let coded = Medication(name: "Something typed", productIdentifier: "312938", productIdentifierType: "RxNorm")
        let archived = Medication(name: "Tacrolimus", isArchived: true)
        let medications = [sertraline, coded, archived]

        let byBrand = HealthMedicationMapper.draft(for: summary("Zoloft 50 MG"))
        XCTAssertEqual(HealthMedicationMapper.existingMedication(for: byBrand, among: medications)?.id, sertraline.id)

        let byCode = HealthMedicationMapper.draft(for: summary("Unrelated wording", rxNormCode: "312938"))
        XCTAssertEqual(HealthMedicationMapper.existingMedication(for: byCode, among: medications)?.id, coded.id)

        let archivedMatch = HealthMedicationMapper.draft(for: summary("Tacrolimus 1 mg"))
        XCTAssertNil(HealthMedicationMapper.existingMedication(for: archivedMatch, among: medications), "an archived medication is not on the active list")

        let unknown = HealthMedicationMapper.draft(for: summary("Melatonin 5 mg"))
        XCTAssertNil(HealthMedicationMapper.existingMedication(for: unknown, among: medications))
    }
}
