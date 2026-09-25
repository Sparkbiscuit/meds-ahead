import XCTest
@testable import Meds

/// The gate between a resolved code and the review screen. A code is exact, and
/// that is precisely why a misread one must never fill the name on its own.
final class NDCIdentificationTests: XCTestCase {
    private typealias Row = (key: String, generic: String, brand: String, strength: String, form: String)

    private let rows: [Row] = [
        ("000494960", "sertraline hydrochloride", "Zoloft", "50 mg", "tablet"),
        ("000541817", "prednisolone sodium phosphate", "", "15 mg/5 mL", "liquid"),
        ("000544161", "tacrolimus", "", "1 mg", "capsule"),
        ("000931039", "sertraline hydrochloride", "", "50 mg", "tablet"),
        ("000931040", "sertraline hydrochloride", "", "100 mg", "tablet"),
        ("006781234", "metoprolol tartrate", "", "50 mg", "tablet"),
        ("006781235", "metoprolol succinate", "", "50 mg", "tablet"),
        ("644060006", "dimethyl fumarate", "Tecfidera", "240 mg", "capsule"),
        ("645100060", "dextroamphetamine saccharate, amphetamine aspartate, dextroamphetamine sulfate and amphetamine sulfate", "Adderall", "5-5-5-5 mg", "tablet")
    ]

    private func directory(_ rows: [Row]) -> NDCDirectory {
        let body = rows
            .sorted { $0.key < $1.key }
            .map { [$0.key, $0.generic, $0.brand, $0.strength, $0.form].joined(separator: "\t") }
            .joined(separator: "\n")
        return NDCDirectory(data: Data(("# Test snapshot\n" + body + "\n").utf8))
    }

    private func evidence(_ lines: [String], barcode: String? = nil) -> [ScanEvidence] {
        let capture = UUID()
        var items = lines.enumerated().map { index, value in
            ScanEvidence(kind: .text, value: value, confidence: 0.9,
                         origin: .cameraCapture, captureID: capture, lineIndex: index)
        }
        if let barcode {
            items.append(ScanEvidence(kind: .barcode, value: barcode, symbology: "GS1 DataBar Limited"))
        }
        return items
    }

    private func draft(_ lines: [String], barcode: String? = nil, rows: [Row]? = nil) -> MedicationDraft {
        MedicationLabelInterpreter.offlineDraft(evidence(lines, barcode: barcode), ndcDirectory: directory(rows ?? self.rows))
    }

    // MARK: - Directory

    func testDirectoryFindsRowsAndNothingElse() {
        let directory = directory(rows)
        XCTAssertEqual(directory.count, rows.count)
        XCTAssertEqual(directory.snapshotDescription, "Test snapshot")
        let product = directory.product(forKey: "644060006")
        XCTAssertEqual(product?.genericName, "dimethyl fumarate")
        XCTAssertEqual(product?.brandName, "Tecfidera")
        XCTAssertEqual(product?.strength, "240 mg")
        XCTAssertEqual(product?.form, .capsule)
        XCTAssertNil(directory.product(forKey: "644060007"))
        XCTAssertNil(directory.product(forKey: "64406000"))
        XCTAssertTrue(NDCDirectory(data: Data()).isEmpty)
    }

    func testDirectoryDropsRowsThatBreakItsOrder() {
        let data = Data("000000002\ta\t\t\ttablet\n000000001\tb\t\t\ttablet\n000000003\tc\t\t\ttablet\n".utf8)
        let directory = NDCDirectory(data: data)
        XCTAssertEqual(directory.count, 2)
        XCTAssertNil(directory.product(forKey: "000000001"))
        XCTAssertEqual(directory.product(forKey: "000000003")?.genericName, "c")
    }

    // MARK: - Printed codes

    func testAPrintedCodeTheLabelVouchesForFillsTheIdentity() {
        let draft = draft(["SERTRALINE HCL 50 MG TABLET", "NDC 0093-1039-01", "TAKE 1 TABLET BY MOUTH DAILY", "QTY: 30"])

        XCTAssertEqual(draft.name, "Sertraline")
        XCTAssertEqual(draft.brandName, "Zoloft", "a generic listing borrows the reference brand, as the label path does")
        XCTAssertEqual(draft.strength, "50 mg")
        XCTAssertEqual(draft.form, .tablet)
        XCTAssertEqual(draft.nameProvenance, .ndc)
        XCTAssertEqual(draft.productIdentifier, "00093-1039-01")
        XCTAssertEqual(draft.productIdentifierType, "NDC")
        XCTAssertEqual(draft.directions, "TAKE 1 TABLET BY MOUTH DAILY")
        XCTAssertEqual(draft.currentSupply, 30)
    }

    func testTheListingsOwnBrandIsPreferredToTheReferenceBrand() {
        let draft = draft(["ZOLOFT 50 MG", "NDC 0049-4960-66"])
        XCTAssertEqual(draft.name, "Sertraline")
        XCTAssertEqual(draft.brandName, "Zoloft")
        XCTAssertEqual(draft.nameProvenance, .ndc)
    }

    func testAPrintedCodeAloneIsNotEnough() {
        let draft = draft(["RX# 8842197", "NDC 0093-1039-01", "QTY: 30"])

        XCTAssertEqual(draft.name, "", "one misread digit is a different product; nothing on this label can check it")
        XCTAssertEqual(draft.nameProvenance, .none)
        XCTAssertEqual(draft.productIdentifier, "0093-1039-01", "the code is still kept as read")
        XCTAssertEqual(draft.productIdentifierType, "NDC")
    }

    func testAMatchingStrengthAloneCorroboratesAPrintedCode() {
        let draft = draft(["50 MG TABLET", "NDC 0093-1039-01"])
        XCTAssertEqual(draft.name, "Sertraline")
        XCTAssertEqual(draft.nameProvenance, .ndc)
    }

    func testALabelNamingAnotherDrugRefusesThePrintedCode() {
        let draft = draft(["TACROLIMUS 1 MG CAPSULE", "NDC 0093-1039-01", "TAKE 1 CAPSULE TWICE DAILY"])

        XCTAssertEqual(draft.name, "Tacrolimus")
        XCTAssertEqual(draft.brandName, "Prograf")
        XCTAssertEqual(draft.nameProvenance, .vocabulary)
        XCTAssertEqual(draft.productIdentifier, "0093-1039-01")
    }

    func testAStrengthTheLabelContradictsRefusesTheCode() {
        let draft = draft(["SERTRALINE HCL 100 MG TABLET", "NDC 0093-1039-01"])

        XCTAssertEqual(draft.name, "Sertraline")
        XCTAssertEqual(draft.strength, "100 mg")
        XCTAssertEqual(draft.nameProvenance, .vocabulary)
    }

    func testAFormTheLabelContradictsRefusesTheCode() {
        let draft = draft(["SERTRALINE HCL 50 MG CAPSULE", "NDC 0093-1039-01"])
        XCTAssertNotEqual(draft.nameProvenance, .ndc)
        XCTAssertEqual(draft.form, .capsule)
    }

    /// Metoprolol succinate and metoprolol tartrate are different products, and a
    /// shared first word must not paper over the salt.
    func testSaltsThatMakeDifferentProductsAreNotInterchangeable() {
        let draft = draft(["METOPROLOL SUCCINATE ER 50 MG TAB", "NDC 0678-1234-01"])
        XCTAssertNotEqual(draft.nameProvenance, .ndc)
        XCTAssertEqual(draft.name, "Metoprolol succinate")

        let agreeing = self.draft(["METOPROLOL SUCCINATE ER 50 MG TAB", "NDC 0678-1235-01"])
        XCTAssertEqual(agreeing.nameProvenance, .ndc)
        XCTAssertEqual(agreeing.name, "Metoprolol succinate")
        XCTAssertEqual(agreeing.brandName, "Toprol XL")
    }

    func testAMixedSaltTotalAgreesWithItsComponents() {
        let draft = draft(["AMPHETAMINE SALT COMBO 20 MG TAB", "NDC 64510-0060-01", "TAKE 1 TABLET BY MOUTH TWICE DAILY"])

        XCTAssertEqual(draft.nameProvenance, .ndc)
        XCTAssertEqual(draft.brandName, "Adderall")
        XCTAssertEqual(draft.strength, "20 mg", "the total printed on the label, not the four components")
        XCTAssertEqual(draft.name, "Amphetamine - dextroamphetamine", "the listing's four salts collapse to the name everyone uses")
    }

    func testAnOralSolutionKeepsItsConcentration() {
        let draft = draft(["PREDNISOLONE SOD PHOS 15MG/5ML SOLN", "NDC 0054-1817-01"])
        XCTAssertEqual(draft.nameProvenance, .ndc)
        XCTAssertEqual(draft.name, "Prednisolone")
        XCTAssertEqual(draft.strength, "15 mg/5 mL")
        XCTAssertEqual(draft.form, .liquid)
    }

    /// Small print breaks a code around its hyphen into two recognized lines.
    /// Read line by line, neither half is a code; read in order, it is.
    func testACodeSplitAcrossTwoCapturedLinesResolves() {
        let draft = draft(["SERTRALINE HCL 50 MG TABLET", "NDC 00093-", "1039-01", "TAKE 1 TABLET BY MOUTH DAILY"])
        XCTAssertEqual(draft.nameProvenance, .ndc)
        XCTAssertEqual(draft.productIdentifier, "00093-1039-01")
    }

    // MARK: - What the review screen is told

    func testTheDraftSaysWhatBecameOfTheCode() {
        XCTAssertEqual(
            draft(["SERTRALINE HCL 50 MG TABLET", "NDC 0093-1039-01"]).identification,
            .accepted(code: "00093-1039-01")
        )
        XCTAssertEqual(
            draft(["RX# 8842197", "NDC 0093-1039-01", "QTY: 30"]).identification,
            .uncorroborated(code: "00093-1039-01", product: "Sertraline 50 mg")
        )
        XCTAssertEqual(
            draft(["TACROLIMUS 1 MG CAPSULE", "NDC 0093-1039-01"]).identification,
            .contradicted(code: "00093-1039-01", product: "Sertraline 50 mg")
        )
        XCTAssertEqual(
            draft(["SERTRALINE HCL 50 MG TABLET", "NDC 0093-9999-01"]).identification,
            .unlisted(code: "0093-9999-01"),
            "the code as read, so the person can check its digits"
        )
        XCTAssertEqual(
            draft(["NDC 0093-1039-01", "NDC 0054-4161-01"]).identification,
            .ambiguous
        )
        XCTAssertNil(draft(["SERTRALINE HCL 50 MG TABLET", "TAKE 1 TABLET DAILY"]).identification, "no code was read")
        XCTAssertEqual(
            draft(["ZOLOFT 50 MG", "NDC 0049-4960-66"]).identification,
            .accepted(code: "00049-4960-66")
        )
        XCTAssertEqual(NDCIdentificationOutcome.uncorroborated(code: "1", product: "p").codeToCheck, "1")
        XCTAssertNil(NDCIdentificationOutcome.accepted(code: "1").codeToCheck)
    }

    func testAnEmptyDirectoryReportsNoOutcome() {
        let draft = MedicationLabelInterpreter.offlineDraft(
            evidence(["NDC 0093-1039-01"]),
            ndcDirectory: NDCDirectory(data: Data())
        )
        XCTAssertNil(draft.identification)
    }

    // MARK: - Barcodes

    func testAManufacturerBarcodeNeedsNoCorroboration() {
        let draft = draft([], barcode: "0100364406006029")

        XCTAssertEqual(draft.name, "Dimethyl fumarate")
        XCTAssertEqual(draft.brandName, "Tecfidera")
        XCTAssertEqual(draft.strength, "240 mg")
        XCTAssertEqual(draft.form, .capsule)
        XCTAssertEqual(draft.nameProvenance, .ndc)
        XCTAssertEqual(draft.productIdentifier, "64406-0006-02")
        XCTAssertEqual(draft.productIdentifierType, "NDC")
    }

    func testABarcodeTheLabelContradictsIsRefused() {
        let draft = draft(["SERTRALINE HCL 50 MG TABLET"], barcode: "0100364406006029")

        XCTAssertEqual(draft.name, "Sertraline")
        XCTAssertEqual(draft.nameProvenance, .vocabulary)
        XCTAssertEqual(draft.productIdentifier, "0100364406006029", "the code is kept as evidence, not as identity")
    }

    func testTenBareDigitsThatFitTwoProductsResolveToNothing() {
        let ambiguous = rows + [("064406006", "ibuprofen", "", "200 mg", "tablet")]
        let match = NDCIdentification.match(in: evidence([], barcode: "0100364406006029"), directory: directory(ambiguous))
        XCTAssertNil(match)
    }

    /// The still pipeline reads a code line twice and a blurred line comes back
    /// as two different codes; the label chooses between them.
    func testACodeTheLabelContradictsGivesWayToOneItVouchesFor() {
        let chosen = draft(["DIMETHYL FUMARATE 240 MG DR CAPSULE", "NDC 64406-005-02", "MFR: BIOGEN NDC 64406-006-02"],
                           rows: rows + [("644060005", "natalizumab", "Tysabri", "300 mg/15 mL", "injection")])
        XCTAssertEqual(chosen.identification, .accepted(code: "64406-0006-02"))
        XCTAssertEqual(chosen.brandName, "Tecfidera")

        let byStrength = draft(["SERTRALINE HCL 50 MG TABLET", "NDC 0093-1040-01", "NDC 0093-1039-01"])
        XCTAssertEqual(byStrength.identification, .accepted(code: "00093-1039-01"), "the 100 mg listing disagrees with the label")

        let noHelp = draft(["NDC 0093-1040-01", "NDC 0093-1039-01"])
        XCTAssertEqual(noHelp.identification, .ambiguous, "with nothing to choose by, neither fills anything")

        let bothWrong = draft(["TACROLIMUS 1 MG CAPSULE", "NDC 0093-1039-01", "NDC 0093-1040-01"])
        XCTAssertEqual(bothWrong.identification, .contradicted(code: "00093-1039-01", product: "Sertraline 50 mg"))
        XCTAssertEqual(bothWrong.name, "Tacrolimus")
    }

    /// What an iOS 27 capture of a shaken Tecfidera label read: a code with the
    /// wrong digits, twice. The code names nothing, so it fills nothing, but the
    /// printed name is the vocabulary's and fills the name as it would on a
    /// label with no code at all.
    func testAnUnlistedCodeLeavesTheLabelsOwnNameInPlace() {
        let draft = draft([
            "SPRINGFIELD PHARMACY #2214", "RX# 4402917",
            "DIMETHYL FUMARATE 240 MG DR CAPSULE",
            "VER BIOGEN NOC 54405-005-22", "MFR:BIOGEN NDC:54405-005-02",
            "TAKE 1 CAPSULE BY MOUTH TWICE DAILY", "QTY: 60"
        ])

        XCTAssertEqual(draft.identification, .unlisted(code: "54405-005-02"))
        XCTAssertEqual(draft.name, "Dimethyl fumarate")
        XCTAssertEqual(draft.nameProvenance, .vocabulary)
        XCTAssertEqual(draft.strength, "240 mg")
        XCTAssertEqual(draft.form, .capsule)
        XCTAssertEqual(draft.productIdentifier, "54405-005-02", "the code as read, ready to check against the bottle")
    }

    /// The directory and the label vouch for the product, never the package,
    /// so a package read two ways is left off rather than guessed: the product
    /// NDC names the drug exactly, and a wrong package code on the shared list
    /// names a bottle no pharmacy dispensed.
    func testAPackageReadTwoWaysIsLeftOffTheCode() {
        let label = ["DIMETHYL FUMARATE 240 MG DR CAPSULE", "NDC 64406-006-02", "MFR: BIOGEN NDC 64406-006-07"]
        let split = draft(label)
        XCTAssertEqual(split.nameProvenance, .ndc)
        XCTAssertEqual(split.brandName, "Tecfidera")
        XCTAssertEqual(split.productIdentifier, "64406-0006")
        XCTAssertEqual(split.productIdentifierType, "NDC")
        XCTAssertEqual(split.identification, .accepted(code: "64406-0006"))

        let agreed = draft(["DIMETHYL FUMARATE 240 MG DR CAPSULE", "NDC 64406-006-02", "NDC 64406000602"])
        XCTAssertEqual(agreed.productIdentifier, "64406-0006-02", "two layouts of one code agree on the package")
        XCTAssertEqual(agreed.rxNormCode, split.rxNormCode, "the RxNorm concept is the product's either way")

        let scanned = draft(label, barcode: "0100364406006029")
        XCTAssertEqual(scanned.productIdentifier, "64406-0006-02", "a barcode's check digit covers the package")
    }

    func testAnEmptyDirectoryChangesNothing() {
        let draft = MedicationLabelInterpreter.offlineDraft(
            evidence(["SERTRALINE HCL 50 MG TABLET", "NDC 0093-1039-01"]),
            ndcDirectory: NDCDirectory(data: Data())
        )
        XCTAssertEqual(draft.name, "Sertraline")
        XCTAssertEqual(draft.nameProvenance, .vocabulary)
        XCTAssertEqual(draft.productIdentifier, "0093-1039-01")
    }

    // MARK: - The rest of the pipeline

    @available(iOS 26.0, *)
    func testTheLanguageModelCannotOverrideAResolvedIdentity() {
        let resolved = draft(["SERTRALINE HCL 50 MG TABLET", "NDC 0093-1039-01", "TAKE 1 TABLET BY MOUTH DAILY"])
        XCTAssertEqual(resolved.nameProvenance, .ndc)
        let candidates = LabelInterpretationCandidates(
            medicationNames: [LabelFieldCandidate(id: 1, value: "TACROLIMUS")],
            strengths: [LabelFieldCandidate(id: 1, value: "1 mg")],
            directions: [LabelFieldCandidate(id: 1, value: "Take 1 tablet by mouth daily")],
            quantities: [],
            refills: []
        )
        let selection = LabelFieldSelection(
            medicationNameID: 1,
            normalizedMedicationName: "Tacrolimus",
            strengthID: 1,
            directionsID: 1,
            quantityID: 0,
            refillsID: 0
        )

        let refined = MedicationLabelInterpreter.applying(selection, candidates: candidates, to: resolved)

        XCTAssertEqual(refined.name, "Sertraline")
        XCTAssertEqual(refined.strength, "50 mg")
        XCTAssertEqual(refined.nameProvenance, .ndc)
        XCTAssertEqual(refined.directions, "Take 1 tablet by mouth daily", "directions may still be refined")
    }

    func testThePreviewReportsAnExactMatch() {
        let matched = ScanPreview.make(
            from: evidence(["SERTRALINE HCL 50 MG TABLET", "NDC 0093-1039-01"]),
            ndcDirectory: directory(rows)
        )
        XCTAssertTrue(matched.isExactMatch)
        XCTAssertEqual(matched.medicationName, "Sertraline")

        let unmatched = ScanPreview.make(from: evidence(["SERTRALINE HCL 50 MG TABLET"]), ndcDirectory: directory(rows))
        XCTAssertFalse(unmatched.isExactMatch)
    }

    func testAPrintedCodeOutranksAPharmacyBarcodeAsTheProductCode() {
        let parsed = ScanParser.parse([
            ScanEvidence(kind: .barcode, value: "323615013", symbology: "Code 128"),
            ScanEvidence(kind: .text, value: "NDC 0093-1039-01")
        ])
        XCTAssertEqual(parsed.productIdentifier, "0093-1039-01")
        XCTAssertEqual(parsed.productIdentifierType, "NDC")
    }

    // MARK: - Strengths

    func testStrengthsWrittenDifferentlyStillAgree() {
        XCTAssertEqual(StrengthComparison.compare(label: "800-160 mg", product: "800 mg/160 mg"), .equivalent)
        XCTAssertEqual(StrengthComparison.compare(label: "5/325 mg", product: "5-325 mg"), .equivalent)
        XCTAssertEqual(StrengthComparison.compare(label: "100 units/mL", product: "100 IU/mL"), .equivalent)
        XCTAssertEqual(StrengthComparison.compare(label: "15 mg/5 mL", product: "15 mg/5 mL"), .equivalent)
        XCTAssertEqual(StrengthComparison.compare(label: "20 mg", product: "5-5-5-5 mg"), .equivalent)
        XCTAssertEqual(StrengthComparison.compare(label: "1,000 IU", product: "1000 IU"), .equivalent)
    }

    func testStrengthsThatDisagreeAreDifferent() {
        XCTAssertEqual(StrengthComparison.compare(label: "50 mg", product: "100 mg"), .different)
        XCTAssertEqual(StrengthComparison.compare(label: "50 mg", product: "50 mcg"), .different)
        XCTAssertEqual(StrengthComparison.compare(label: "10 mg/5 mL", product: "10 mg/mL"), .different)
        XCTAssertEqual(StrengthComparison.compare(label: "800-160 mg", product: "400-80 mg"), .different)
    }

    func testStrengthsThatCannotBeComparedProveNothing() {
        XCTAssertEqual(StrengthComparison.compare(label: "", product: "50 mg"), .incomparable)
        XCTAssertEqual(StrengthComparison.compare(label: "50 mg", product: ""), .incomparable)
        XCTAssertEqual(StrengthComparison.compare(label: "325 mg", product: "325-10-5 mg"), .incomparable, "a partial reading of a three-ingredient product")
    }

    func testExplicitFormsAreReadFromTheLabel() {
        XCTAssertEqual(NDCIdentification.explicitForm(in: "TAKE 1 TABLET BY MOUTH DAILY"), .tablet)
        XCTAssertEqual(NDCIdentification.explicitForm(in: "SERTRALINE 50 MG CAPS"), .capsule)
        XCTAssertNil(NDCIdentification.explicitForm(in: "SERTRALINE 50 MG"))
        XCTAssertNil(NDCIdentification.explicitForm(in: "1 TABLET OR 2 CAPSULES"), "two forms is no form")
    }
}
