import XCTest
@testable import Meds

/// The bundled RxNorm slice: what it answers, and the real rows the shipped
/// files must keep answering the same way.
final class RxNormTableTests: XCTestCase {
    private func table() -> RxNormTable {
        let products = """
        # Test RxNorm slice
        000931039\t312941\t
        004690617\t108513\t198377
        581510575\t208161\t312941
        999999999\t\t

        """
        return RxNormTable(productsData: Data(products.utf8))
    }

    func testAProductAnswersWithItsConceptAndClinicalDrug() throws {
        let table = table()
        XCTAssertEqual(table.productCount, 4, "every keyed row is indexed; a blank concept answers nil below")
        XCTAssertEqual(table.snapshotDescription, "Test RxNorm slice")

        let prograf = try XCTUnwrap(table.product(forProductKey: "004690617"))
        XCTAssertEqual(prograf.rxcui, "108513")
        XCTAssertEqual(prograf.clinicalDrugRxcui, "198377")
        XCTAssertEqual(prograf.clinicalDrugCode, "198377")

        let generic = try XCTUnwrap(table.product(forProductKey: "000931039"))
        XCTAssertEqual(generic.rxcui, "312941")
        XCTAssertNil(generic.clinicalDrugRxcui)
        XCTAssertEqual(generic.clinicalDrugCode, "312941")

        XCTAssertNil(table.product(forProductKey: "999999999"))
        XCTAssertNil(table.product(forProductKey: "123456789"))
        XCTAssertNil(table.product(forProductKey: "12345"))
        XCTAssertEqual(table.product(for: try XCTUnwrap(NationalDrugCode(canonicalDigits: "00469061773")))?.rxcui, "108513")
    }

    func testClinicalDrugsResolve() {
        let table = table()
        XCTAssertEqual(table.clinicalDrugCode(for: "108513"), "198377", "a brand answers with its clinical drug")
        XCTAssertEqual(table.clinicalDrugCode(for: "208161"), "312941")
        XCTAssertEqual(table.clinicalDrugCode(for: "198377"), "198377", "a clinical drug answers for itself")
        XCTAssertEqual(table.clinicalDrugCode(for: "424242"), "424242", "an unknown code answers for itself")
    }

    func testAnEmptyTableAnswersNothing() {
        let empty = RxNormTable(productsData: Data())
        XCTAssertTrue(empty.isEmpty)
        XCTAssertNil(empty.product(forProductKey: "004690617"))
        XCTAssertEqual(empty.clinicalDrugCode(for: "108513"), "108513")
    }

    // MARK: - The files that ship

    func testTheBundledSliceIsPresentAndPinsRealProducts() throws {
        let shared = RxNormTable.shared
        XCTAssertGreaterThan(shared.productCount, 60_000, "about eighty thousand FDA products carry a prescribable concept")
        XCTAssertTrue(shared.snapshotDescription?.contains("RxNorm current prescribable content 20") == true)

        let prograf = try XCTUnwrap(shared.product(forProductKey: "004690617"))
        XCTAssertEqual(prograf.rxcui, "108513")
        XCTAssertEqual(prograf.clinicalDrugRxcui, "198377", "the code Health shows for tacrolimus 1 mg")

        let zoloft = try XCTUnwrap(shared.product(forProductKey: "581510575"))
        let genericSertraline = try XCTUnwrap(shared.product(forProductKey: "167140612"))
        XCTAssertEqual(zoloft.clinicalDrugCode, genericSertraline.rxcui, "the brand and a generic are one clinical drug")

        let tecfidera = try XCTUnwrap(shared.product(forProductKey: "644060006"))
        XCTAssertNotNil(tecfidera.clinicalDrugRxcui)
    }

    // MARK: - Where the code goes

    func testAnAcceptedNDCCarriesItsRxNormConcept() {
        let directory = NDCDirectory(data: Data("# t\n004690617\ttacrolimus\tPrograf\t1 mg\tcapsule\n".utf8))
        let capture = UUID()
        let evidence = ["TACROLIMUS 1 MG CAPSULE", "NDC 0469-0617-73"].enumerated().map { index, value in
            ScanEvidence(kind: .text, value: value, confidence: 0.9, origin: .cameraCapture, captureID: capture, lineIndex: index)
        }

        let draft = MedicationLabelInterpreter.offlineDraft(evidence, ndcDirectory: directory, rxNormTable: table())

        XCTAssertEqual(draft.nameProvenance, .ndc)
        XCTAssertEqual(draft.rxNormCode, "108513")
        let unresolvable = MedicationLabelInterpreter.offlineDraft(
            evidence,
            ndcDirectory: directory,
            rxNormTable: RxNormTable(productsData: Data())
        )
        XCTAssertEqual(unresolvable.nameProvenance, .ndc)
        XCTAssertEqual(unresolvable.rxNormCode, "", "no table, no code, and the identification stands")
    }

    @MainActor
    func testAHealthEntryRecognisesTheSameClinicalDrugUnderAnotherBrand() {
        let scannedGeneric = Medication(name: "Sertraline", productIdentifier: "00093-1039-01", productIdentifierType: "NDC", rxNormCode: "312941")
        let scannedProgaf = Medication(name: "Tacrolimus", productIdentifier: "00469-0617-73", productIdentifierType: "NDC", rxNormCode: "108513")
        let medications = [scannedGeneric, scannedProgaf]

        var fromZoloft = MedicationDraft()
        fromZoloft.productIdentifier = "208161"
        fromZoloft.productIdentifierType = "RxNorm"
        fromZoloft.rxNormCode = "208161"
        XCTAssertEqual(
            HealthMedicationMapper.existingMedication(for: fromZoloft, among: medications, rxNormTable: table())?.id,
            scannedGeneric.id,
            "Zoloft in Health is the generic sertraline bottle here"
        )

        var fromTacrolimus = MedicationDraft()
        fromTacrolimus.productIdentifier = "198377"
        fromTacrolimus.productIdentifierType = "RxNorm"
        XCTAssertEqual(
            HealthMedicationMapper.existingMedication(for: fromTacrolimus, among: medications, rxNormTable: table())?.id,
            scannedProgaf.id,
            "the clinical drug in Health is the Prograf bottle here"
        )

        var unrelated = MedicationDraft()
        unrelated.productIdentifier = "313988"
        unrelated.productIdentifierType = "RxNorm"
        XCTAssertNil(HealthMedicationMapper.existingMedication(for: unrelated, among: medications, rxNormTable: table()))
    }

    func testTheSyncWidensBothSidesToTheClinicalDrug() {
        if #available(iOS 26.0, *) {
            XCTAssertEqual(HealthDoseSync.expanded(["108513"], table: table()), ["108513", "198377"])
            XCTAssertEqual(HealthDoseSync.expanded(["198377"], table: table()), ["198377"])
            XCTAssertTrue(HealthDoseSync.expanded([], table: table()).isEmpty)
        }
    }
}
