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
        let draft = HealthMedicationMapper.draft(for: summary("Lukas's evening vitamin", nickname: "Gummy", form: .unknown))

        XCTAssertEqual(draft.name, "Lukas's evening vitamin")
        XCTAssertEqual(draft.nickname, "Gummy")
        XCTAssertEqual(draft.brandName, "")
        XCTAssertEqual(draft.strength, "")
        XCTAssertEqual(draft.productIdentifier, "")
    }

    func testFormWordsAndRoutesAreNotPartOfTheName() {
        XCTAssertEqual(HealthMedicationMapper.cleanedName(from: "Metoprolol succinate 25 MG Extended Release Oral Tablet"), "Metoprolol succinate")
        XCTAssertEqual(HealthMedicationMapper.cleanedName(from: "Insulin glargine 100 units/mL injection pen"), "Insulin glargine")
        XCTAssertEqual(HealthMedicationMapper.cleanedName(from: "Prednisolone 15 mg/5 mL oral solution"), "Prednisolone")
    }

    func testHealthFormsMapOntoTheAppsForms() {
        XCTAssertEqual(HealthMedicationMapper.form(for: .tablet), .tablet)
        XCTAssertEqual(HealthMedicationMapper.form(for: .capsule), .capsule)
        XCTAssertEqual(HealthMedicationMapper.form(for: .liquid), .liquid)
        XCTAssertEqual(HealthMedicationMapper.form(for: .injection), .injection)
        XCTAssertEqual(HealthMedicationMapper.form(for: .inhaler), .inhaler)
        XCTAssertEqual(HealthMedicationMapper.form(for: .patch), .patch)
        XCTAssertEqual(HealthMedicationMapper.form(for: .drops), .drops)
        XCTAssertEqual(HealthMedicationMapper.form(for: .ointment), .topical)
        XCTAssertEqual(HealthMedicationMapper.form(for: .spray), .other)
        XCTAssertNil(HealthMedicationMapper.form(for: .unknown))
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
