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

    /// The bar a guess below the recognizer's top reading must clear: the
    /// label's confirmed name and its printed strength are the product's, and
    /// nothing on it contradicts the product.
    func testOnlyTheProductTheLabelNamesExactlyClearsTheBarForAGuess() throws {
        let rows = self.rows + [("644060005", "dimethyl fumarate", "Tecfidera", "120 mg", "capsule")]
        let directory = directory(rows)
        func namesExactly(_ key: String, _ lines: [String]) throws -> Bool {
            try labelNamesExactly(key + "02", lines, directory: directory)
        }
        let tecfidera = ["DIMETHYL FUMARATE 240 MG DR CAPSULE", "TAKE 1 CAPSULE BY MOUTH TWICE DAILY"]

        XCTAssertTrue(try namesExactly("644060006", tecfidera))
        XCTAssertFalse(try namesExactly("644060005", tecfidera), "the same drug at another strength")
        XCTAssertFalse(try namesExactly("644060006", ["DIMETHYL FUMARATE", "QTY: 60"]), "a name alone cannot tell the strengths apart")
        XCTAssertFalse(try namesExactly("644060006", ["TACROLIMUS 240 MG CAPSULE"]), "another drug at the same strength")
        XCTAssertFalse(try namesExactly("644060006", ["DIMETHYL FUMARATE 240 MG TABLET"]), "another form")
        XCTAssertFalse(try namesExactly("644060006", ["240 MG CAPSULE", "TAKE 1 CAPSULE BY MOUTH TWICE DAILY"]), "a strength with no name")
    }

    /// Prograf and Astagraf XL are immediate- and extended-release tacrolimus
    /// from one labeler, one digit apart at every strength, and the directory
    /// records no release. A label that says only "tacrolimus 1 mg capsule"
    /// names both, so a guess at either is refused. A label that prints the
    /// brand sets the other apart, and one that prints a brand the guessed
    /// product does not carry refuses it.
    func testAGuessIsRefusedWhileTheLabelFitsAnotherProductOfItsLabeler() throws {
        let rows: [Row] = [
            ("000544161", "tacrolimus", "", "1 mg", "capsule"),
            ("004690607", "tacrolimus", "Prograf", "0.5 mg", "capsule"),
            ("004690617", "tacrolimus", "Prograf", "1 mg", "capsule"),
            ("004690647", "tacrolimus", "Astagraf XL", "0.5 mg", "capsule"),
            ("004690677", "tacrolimus", "Astagraf XL", "1 mg", "capsule"),
            ("004691330", "tacrolimus", "Prograf", "1 mg", "liquid")
        ]
        let directory = directory(rows)
        func namesExactly(_ key: String, _ lines: [String]) throws -> Bool {
            try labelNamesExactly(key + "73", lines, directory: directory)
        }
        let generic = ["TACROLIMUS 1 MG CAPSULE", "TAKE 1 CAPSULE BY MOUTH TWICE DAILY"]
        XCTAssertFalse(try namesExactly("004690617", generic), "Astagraf XL 1 mg fits the label as well")
        XCTAssertFalse(try namesExactly("004690677", generic), "Prograf 1 mg fits the label as well")
        XCTAssertTrue(try namesExactly("000544161", generic), "the one product of its labeler the label fits")

        let prograf = ["PROGRAF 1 MG CAPSULE", "TAKE 1 CAPSULE BY MOUTH TWICE DAILY"]
        XCTAssertTrue(try namesExactly("004690617", prograf), "the printed brand sets Astagraf XL apart")
        XCTAssertFalse(try namesExactly("004690677", prograf), "the label prints another brand")
        XCTAssertFalse(try namesExactly("004691330", prograf), "the label prints another form")
        XCTAssertFalse(try namesExactly("000544161", prograf), "a generic, where the label prints a brand")
        XCTAssertFalse(try namesExactly("004690617", ["PROGRAF 1 MG", "TAKE ONE TWICE DAILY"]),
                       "with no form printed, the 1 mg granules fit as well")

        let astagraf = ["ASTAGRAF XL 1 MG CAPSULE", "TAKE 1 CAPSULE BY MOUTH ONCE DAILY"]
        XCTAssertTrue(try namesExactly("004690677", astagraf))
        XCTAssertFalse(try namesExactly("004690617", astagraf), "the label prints another brand")
    }

    /// A brand spelled out with its release letters is another medicine than
    /// the same brand with others, even from another labeler. A label printing
    /// WELLBUTRIN XL gets no guess at Wellbutrin SR, and one printing the brand
    /// alone names neither release.
    func testAGuessNeedsTheWholeBrandTheLabelPrints() throws {
        let directory = directory([
            ("001730135", "bupropion hydrochloride", "Wellbutrin SR", "150 mg", "tablet"),
            ("001870730", "bupropion hydrochloride", "Wellbutrin XL", "150 mg", "tablet")
        ])
        let extended = ["WELLBUTRIN XL 150 MG TABLET", "TAKE 1 TABLET BY MOUTH EVERY MORNING"]
        XCTAssertTrue(try labelNamesExactly("00187073001", extended, directory: directory))
        XCTAssertFalse(try labelNamesExactly("00173013501", extended, directory: directory), "another release of the brand")

        let brandAlone = ["WELLBUTRIN 150 MG TABLET", "TAKE 1 TABLET BY MOUTH EVERY MORNING"]
        XCTAssertFalse(try labelNamesExactly("00187073001", brandAlone, directory: directory))
        XCTAssertFalse(try labelNamesExactly("00173013501", brandAlone, directory: directory))
    }

    /// Whether a guessed code clears the stricter bar against a label read
    /// from these lines.
    private func labelNamesExactly(_ digits: String, _ lines: [String], directory: NDCDirectory) throws -> Bool {
        let label = MedicationLabelInterpreter.offlineDraft(evidence(lines), ndcDirectory: directory)
        let text = LabelCandidateBuilder.textLines(from: label.evidence).joined(separator: "\n")
        let code = try XCTUnwrap(NationalDrugCode(canonicalDigits: digits))
        let product = try XCTUnwrap(directory.product(for: code))
        return NDCIdentification.labelNamesExactly(.init(code: code, product: product, source: .printedText), draft: label, labelText: text, directory: directory)
    }

    // MARK: - Release

    /// Rows with the release column the bundled snapshot carries: "er", "dr",
    /// or empty for a listing that claims neither.
    private typealias ReleasedRow = (key: String, generic: String, brand: String, strength: String, form: String, release: String)

    private let tacrolimusRows: [ReleasedRow] = [
        ("004690617", "tacrolimus", "Prograf", "1 mg", "capsule", ""),
        ("004690677", "tacrolimus", "Astagraf XL", "1 mg", "capsule", "er"),
        ("689923010", "tacrolimus", "Envarsus XR", "1 mg", "tablet", "er"),
        ("714322002", "tacrolimus", "", "1 mg", "capsule", "er"),
        ("006157824", "metoprolol succinate", "", "50 mg", "tablet", "er"),
        ("006781234", "metoprolol tartrate", "", "50 mg", "tablet", ""),
        ("167290189", "mycophenolic acid", "", "360 mg", "tablet", "dr"),
        ("644060006", "dimethyl fumarate", "Tecfidera", "240 mg", "capsule", ""),
        ("500900001", "cetirizine hydrochloride", "Zyrtec", "10 mg", "tablet", ""),
        ("497080146", "sulfamethoxazole and trimethoprim", "Bactrim DS", "800-160 mg", "tablet", ""),
        ("499350220", "naproxen sodium", "Equate Naproxen Sodium", "220 mg", "tablet", "")
    ]

    private func releasedDirectory(_ rows: [ReleasedRow]) -> NDCDirectory {
        let body = rows
            .sorted { $0.key < $1.key }
            .map { [$0.key, $0.generic, $0.brand, $0.strength, $0.form, $0.release].joined(separator: "\t") }
            .joined(separator: "\n")
        return NDCDirectory(data: Data(("# Test snapshot\n" + body + "\n").utf8))
    }

    private func releasedDraft(_ lines: [String], barcode: String? = nil) -> MedicationDraft {
        MedicationLabelInterpreter.offlineDraft(evidence(lines, barcode: barcode), ndcDirectory: releasedDirectory(tacrolimusRows))
    }

    func testTheReleaseColumnIsReadAndFiveColumnRowsStillLoad() throws {
        let directory = releasedDirectory(tacrolimusRows)
        XCTAssertEqual(directory.product(forKey: "004690677")?.release, .extended)
        XCTAssertEqual(directory.product(forKey: "004690617")?.release, .immediate)
        XCTAssertEqual(directory.product(forKey: "167290189")?.release, .delayed)

        // A row without the column says only what its brand's letters say.
        let fiveColumns = NDCDirectory(data: Data("004690617\ttacrolimus\tPrograf\t1 mg\tcapsule\n004690677\ttacrolimus\tAstagraf XL\t1 mg\tcapsule\n".utf8))
        XCTAssertEqual(fiveColumns.count, 2)
        XCTAssertNil(fiveColumns.product(forKey: "004690617")?.release)
        XCTAssertEqual(fiveColumns.product(forKey: "004690677")?.release, .extended)
        XCTAssertEqual(try XCTUnwrap(fiveColumns.product(forKey: "004690677")).form, .capsule)
    }

    /// The confirmed hazard: small print swaps 1 and 7, and 0469-0617 read as
    /// 0469-0677 is Astagraf XL on a Prograf bottle. The name, strength and
    /// form all agree; the brand and the release do not.
    func testAPrografLabelRefusesAMisreadAstagrafCode() {
        let draft = releasedDraft(["PROGRAF 1 MG CAPSULE", "NDC 0469-0677-73", "TAKE 1 CAPSULE BY MOUTH TWICE DAILY"])

        XCTAssertEqual(draft.identification, .contradicted(code: "00469-0677-73", product: "Tacrolimus 1 mg (Astagraf XL)"))
        XCTAssertEqual(draft.name, "Tacrolimus", "the label's own name stands")
        XCTAssertEqual(draft.brandName, "Prograf", "the brand the label prints, never the code's")
        XCTAssertNotEqual(draft.nameProvenance, .ndc)
        XCTAssertEqual(draft.rxNormCode, "", "a refused code carries no RxNorm concept")
        XCTAssertEqual(draft.productIdentifier, "0469-0677-73", "kept as read, to check against the bottle")

        let envarsus = releasedDraft(["PROGRAF 1 MG", "NDC 68992-3010-01"])
        XCTAssertEqual(envarsus.identification, .contradicted(code: "68992-3010-01", product: "Tacrolimus 1 mg (Envarsus XR)"))
    }

    /// "TACROLIMUS 1 MG CAPSULE" does not say which release. An
    /// extended-release code beside it fills nothing, and the reference brand
    /// the label would otherwise borrow, Prograf, is not lent either.
    func testALabelThatDoesNotSayExtendedReleaseCannotFillAnExtendedReleaseCode() {
        let draft = releasedDraft(["TACROLIMUS 1 MG CAPSULE", "NDC 0469-0677-73", "TAKE 1 CAPSULE BY MOUTH TWICE DAILY"])

        XCTAssertEqual(draft.identification, .uncorroborated(code: "00469-0677-73", product: "Tacrolimus 1 mg (Astagraf XL)"))
        XCTAssertNotEqual(draft.nameProvenance, .ndc)
        XCTAssertEqual(draft.name, "Tacrolimus")
        XCTAssertEqual(draft.brandName, "", "neither Astagraf XL nor the borrowed Prograf")
        XCTAssertEqual(draft.rxNormCode, "")

        let generic = releasedDraft(["TACROLIMUS 1 MG CAPSULE", "NDC 71432-2002-01"])
        XCTAssertEqual(generic.identification, .uncorroborated(code: "71432-2002-01", product: "Tacrolimus 1 mg extended-release"))

        // The same label with the immediate-release code is Prograf, as before.
        let prograf = releasedDraft(["TACROLIMUS 1 MG CAPSULE", "NDC 0469-0617-73"])
        XCTAssertEqual(prograf.identification, .accepted(code: "00469-0617-73"))
        XCTAssertEqual(prograf.brandName, "Prograf")
    }

    func testALabelThatSaysTheReleaseAcceptsItsOwnCode() {
        let astagraf = releasedDraft(["ASTAGRAF XL 1 MG CAPSULE", "NDC 0469-0677-73", "TAKE 1 CAPSULE BY MOUTH ONCE DAILY"])
        XCTAssertEqual(astagraf.identification, .accepted(code: "00469-0677-73"))
        XCTAssertEqual(astagraf.nameProvenance, .ndc)
        XCTAssertEqual(astagraf.name, "Tacrolimus")
        XCTAssertEqual(astagraf.brandName, "Astagraf XL")

        let generic = releasedDraft(["TACROLIMUS ER 1 MG CAPSULE", "NDC 71432-2002-01", "TAKE 1 CAPSULE BY MOUTH ONCE DAILY"])
        XCTAssertEqual(generic.identification, .accepted(code: "71432-2002-01"))
        XCTAssertEqual(generic.name, "Tacrolimus ER", "the release stays in the name when the table's brand is another release's")
        XCTAssertEqual(generic.brandName, "", "never Prograf")

        let phrase = releasedDraft(["TACROLIMUS EXTENDED-RELEASE 1 MG CAPSULE", "NDC 71432-2002-01"])
        XCTAssertEqual(phrase.identification, .accepted(code: "71432-2002-01"))
    }

    func testAnExtendedReleaseLabelRefusesAnImmediateReleaseProduct() {
        let printed = releasedDraft(["TACROLIMUS XL 1 MG CAPSULE", "NDC 0469-0617-73", "TAKE 1 CAPSULE BY MOUTH ONCE DAILY"])
        XCTAssertEqual(printed.identification, .contradicted(code: "00469-0617-73", product: "Tacrolimus 1 mg (Prograf)"))
        XCTAssertEqual(printed.name, "Tacrolimus XL", "the label's release, as it prints it")
        XCTAssertEqual(printed.brandName, "", "an extended-release label is not lent the immediate-release brand")

        // A barcode needs no backing, but it is still refused when the label says otherwise.
        let scanned = releasedDraft(["TACROLIMUS ER 1 MG CAPSULE"], barcode: "0100304690617730")
        XCTAssertNotEqual(scanned.nameProvenance, .ndc)
        XCTAssertEqual(scanned.identification, .contradicted(code: "00469-0617-73", product: "Tacrolimus 1 mg (Prograf)"))
    }

    /// Metoprolol succinate is only ever extended-release, so its name backs
    /// the release up whether or not the label prints ER.
    func testMetoprololSuccinateStillResolvesWithOrWithoutItsLetters() {
        for lines in [["METOPROLOL SUCCINATE ER 50 MG TAB", "NDC 0615-7824-39"], ["METOPROLOL SUCCINATE 50 MG TABLET", "NDC 0615-7824-39"]] {
            let draft = releasedDraft(lines)
            XCTAssertEqual(draft.identification, .accepted(code: "00615-7824-39"), "\(lines)")
            XCTAssertEqual(draft.name, "Metoprolol succinate")
            XCTAssertEqual(draft.brandName, "Toprol XL")
        }
        let tartrate = releasedDraft(["METOPROLOL SUCCINATE ER 50 MG TAB", "NDC 0678-1234-01"])
        XCTAssertEqual(tartrate.identification, .contradicted(code: "00678-1234-01", product: "Metoprolol tartrate 50 mg"))
    }

    /// The FDA files some delayed-release products as plain capsules, and
    /// Tecfidera is one: a label that says DR does not refuse a listing that
    /// claims no release. Extended and delayed still refuse each other.
    func testDelayedReleaseAgainstTheDirectory() {
        let tecfidera = releasedDraft(["DIMETHYL FUMARATE 240 MG DR CAPSULE", "NDC 64406-006-02"])
        XCTAssertEqual(tecfidera.identification, .accepted(code: "64406-0006-02"))

        let mycophenolic = releasedDraft(["MYCOPHENOLIC ACID DR 360 MG TABLET", "NDC 16729-189-01"])
        XCTAssertEqual(mycophenolic.identification, .accepted(code: "16729-0189-01"))

        let named = releasedDraft(["MYCOPHENOLIC ACID 360 MG TABLET", "NDC 16729-189-01"])
        XCTAssertEqual(named.identification, .accepted(code: "16729-0189-01"), "the table knows mycophenolic acid only as delayed-release")

        let extended = releasedDraft(["MYCOPHENOLIC ACID ER 360 MG TABLET", "NDC 16729-189-01"])
        XCTAssertEqual(extended.identification, .contradicted(code: "16729-0189-01", product: "Mycophenolic acid 360 mg delayed-release"))
    }

    /// A brand is refused as another product's only when it is a different
    /// name for the drug. A variant of the reference brand differs in strength
    /// or release, which are checked on their own, and a store's brand prints
    /// the reference brand to compare itself with.
    func testABrandVariantOrAStoreBrandIsNotAnotherProduct() {
        let bactrim = releasedDraft(["BACTRIM 800-160 MG TABLET", "NDC 49708-146-01"])
        XCTAssertEqual(bactrim.identification, .accepted(code: "49708-0146-01"))
        XCTAssertEqual(bactrim.brandName, "Bactrim DS")

        let store = releasedDraft(["NAPROXEN SODIUM 220 MG TABLET", "COMPARE TO ALEVE", "NDC 49935-220-01"])
        XCTAssertEqual(store.identification, .accepted(code: "49935-0220-01"))
    }

    /// "24 HR" is on Zyrtec and Allegra, which are immediate-release, so it
    /// backs an extended-release product up but never refuses another.
    func testAnHourCountBacksUpButNeverRefuses() {
        let zyrtec = releasedDraft(["ZYRTEC 24 HR 10 MG TABLET", "NDC 50090-0001-01"])
        XCTAssertEqual(zyrtec.identification, .accepted(code: "50090-0001-01"))

        let tacrolimus = releasedDraft(["TACROLIMUS 24 HR 1 MG CAPSULE", "NDC 71432-2002-01"])
        XCTAssertEqual(tacrolimus.identification, .accepted(code: "71432-2002-01"))
    }

    /// A dosing interval on the drug's line is how often, not how the product
    /// releases. "Every 12 hours" is Prograf's schedule, and it must never
    /// vouch for an Astagraf XL code misread off a Prograf bottle.
    func testADosingIntervalDoesNotVouchForExtendedRelease() {
        for lines in [
            ["RIVERSIDE PHARMACY", "TACROLIMUS 1 MG CAPSULE EVERY 12 HOURS", "NDC 0469-0677-73"],
            ["RIVERSIDE PHARMACY", "TAKE 1 TACROLIMUS 1 MG CAPSULE BY MOUTH EVERY 12 HOURS", "NDC 0469-0677-73"],
            ["RIVERSIDE PHARMACY", "TACROLIMUS 1 MG CAPSULE 12 HR", "NDC 0469-0677-73"],
            ["RIVERSIDE PHARMACY", "TACROLIMUS 1 MG CAPSULE EVERY 24 HOURS", "NDC 0469-0677-73"]
        ] {
            let draft = releasedDraft(lines)
            XCTAssertEqual(draft.identification, .uncorroborated(code: "00469-0677-73", product: "Tacrolimus 1 mg (Astagraf XL)"), "\(lines)")
            XCTAssertNotEqual(draft.nameProvenance, .ndc, "\(lines)")
            XCTAssertEqual(draft.brandName, "", "\(lines)")
            XCTAssertEqual(draft.rxNormCode, "", "\(lines)")
        }
    }

    /// The other direction of the brand check: ASTAGRAF XL printed anywhere
    /// on the label, and the code misread to Prograf. The labeler's other
    /// brands of the drug are brands the label can print.
    func testALabelPrintingAnotherBrandOfTheDrugRefusesTheCode() {
        for lines in [
            ["RIVERSIDE PHARMACY", "TACROLIMUS 1 MG CAPSULE", "ASTAGRAF XL", "NDC 0469-0617-73"],
            ["RIVERSIDE PHARMACY", "TACROLIMUS 1 MG CAPSULE", "GENERIC FOR ASTAGRAF XL", "NDC 0469-0617-73"],
            ["RIVERSIDE PHARMACY", "ASTAGRAF XL 1 MG CAPSULE", "NDC 0469-0617-73"]
        ] {
            let draft = releasedDraft(lines)
            XCTAssertEqual(draft.identification, .contradicted(code: "00469-0617-73", product: "Tacrolimus 1 mg (Prograf)"), "\(lines)")
            XCTAssertNotEqual(draft.nameProvenance, .ndc, "\(lines)")
            XCTAssertNotEqual(draft.brandName, "Prograf", "\(lines)")
            XCTAssertEqual(draft.rxNormCode, "", "\(lines)")
        }

        // The same label with the code it carries.
        let right = releasedDraft(["RIVERSIDE PHARMACY", "TACROLIMUS 1 MG CAPSULE", "ASTAGRAF XL", "NDC 0469-0677-73"])
        XCTAssertEqual(right.identification, .accepted(code: "00469-0677-73"))
        XCTAssertEqual(right.brandName, "Astagraf XL")

        // A generic of the labeler has no brand of its own to print, and the
        // release the printed brand names refuses it instead.
        let generic = MedicationLabelInterpreter.offlineDraft(
            evidence(["RIVERSIDE PHARMACY", "TACROLIMUS 1 MG CAPSULE", "ASTAGRAF XL", "NDC 0469-0999-73"]),
            ndcDirectory: releasedDirectory(tacrolimusRows + [("004690999", "tacrolimus", "", "1 mg", "capsule", "")])
        )
        XCTAssertEqual(generic.identification, .contradicted(code: "00469-0999-73", product: "Tacrolimus 1 mg"))
    }

    /// A narrow label wraps "TACROLIMUS XL 1 MG CAPSULE" onto two lines.
    func testWrappedReleaseLettersRefuseAnImmediateReleaseCode() {
        for lines in [
            ["RIVERSIDE PHARMACY", "TACROLIMUS", "XL 1 MG CAPSULE", "NDC 0469-0617-73"],
            ["RIVERSIDE PHARMACY", "TACROLIMUS 1 MG", "ER CAPSULE", "NDC 0469-0617-73"]
        ] {
            let draft = releasedDraft(lines)
            XCTAssertEqual(draft.identification, .contradicted(code: "00469-0617-73", product: "Tacrolimus 1 mg (Prograf)"), "\(lines)")
            XCTAssertNotEqual(draft.brandName, "Prograf", "\(lines)")
            XCTAssertEqual(draft.rxNormCode, "", "\(lines)")
        }
    }

    /// Two readings, one of each release, leave the release in doubt, so the
    /// table's immediate-release brand is not lent either.
    func testTwoReadingsOfTwoReleasesLendNoBrand() {
        let draft = releasedDraft(["TACROLIMUS 1 MG CAPSULE", "NDC 0469-0677-73", "NDC 0469-0617-73"])
        XCTAssertEqual(draft.identification, .ambiguous)
        XCTAssertEqual(draft.name, "Tacrolimus")
        XCTAssertEqual(draft.brandName, "")
    }

    /// Some listings carry the drug's name and strength as their brand. A
    /// label that names the drug has not named such a product, so it does not
    /// vouch for the product's release.
    func testABrandThatIsOnlyTheDrugsNameDoesNotBackARelease() {
        let rows = tacrolimusRows + [("699990081", "aspirin", "Aspirin 81 mg", "81 mg", "tablet", "dr")]
        func draft(_ lines: [String]) -> MedicationDraft {
            MedicationLabelInterpreter.offlineDraft(evidence(lines), ndcDirectory: releasedDirectory(rows))
        }
        XCTAssertEqual(draft(["ASPIRIN 81 MG TABLET", "NDC 69999-0081-01"]).identification,
                       .uncorroborated(code: "69999-0081-01", product: "Aspirin 81 mg delayed-release (Aspirin 81 mg)"))
        XCTAssertEqual(draft(["ASPIRIN EC 81 MG TABLET", "NDC 69999-0081-01"]).identification, .accepted(code: "69999-0081-01"))
    }

    /// A guess at a neighbouring code goes forward only when the label rules
    /// out every other product of the labeler; a release it prints rules out
    /// the other release.
    func testAGuessUsesThePrintedReleaseToSetTheOtherApart() throws {
        let directory = releasedDirectory(tacrolimusRows)
        func namesExactly(_ digits: String, _ lines: [String]) throws -> Bool {
            try labelNamesExactly(digits, lines, directory: directory)
        }
        XCTAssertTrue(try namesExactly("00469067773", ["TACROLIMUS XL 1 MG CAPSULE", "TAKE 1 CAPSULE BY MOUTH ONCE DAILY"]))
        XCTAssertFalse(try namesExactly("00469061773", ["TACROLIMUS XL 1 MG CAPSULE"]), "the label says extended-release")
        XCTAssertFalse(try namesExactly("00469061773", ["TACROLIMUS 1 MG CAPSULE"]), "Astagraf XL fits a label that does not say")
        XCTAssertFalse(try namesExactly("00469067773", ["TACROLIMUS 1 MG CAPSULE"]), "an extended-release guess needs the label to say so")
        XCTAssertTrue(try namesExactly("00469061773", ["PROGRAF 1 MG CAPSULE"]))
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

    /// The model choosing the same name again must not lend back the brand
    /// the gate withheld because the code beside it left the release in doubt.
    @available(iOS 26.0, *)
    func testTheLanguageModelDoesNotLendBackAWithheldBrand() {
        let doubted = releasedDraft(["TACROLIMUS 1 MG CAPSULE", "NDC 0469-0677-73", "TAKE 1 CAPSULE BY MOUTH TWICE DAILY"])
        XCTAssertEqual(doubted.brandName, "")
        let candidates = LabelInterpretationCandidates(
            medicationNames: [LabelFieldCandidate(id: 1, value: "TACROLIMUS")],
            strengths: [LabelFieldCandidate(id: 1, value: "1 mg")],
            directions: [],
            quantities: [],
            refills: []
        )
        let selection = LabelFieldSelection(
            medicationNameID: 1,
            normalizedMedicationName: "Tacrolimus",
            strengthID: 1,
            directionsID: 0,
            quantityID: 0,
            refillsID: 0
        )

        let refined = MedicationLabelInterpreter.applying(selection, candidates: candidates, to: doubted)

        XCTAssertEqual(refined.name, "Tacrolimus")
        XCTAssertEqual(refined.brandName, "", "not Prograf")
        XCTAssertEqual(refined.identification, doubted.identification)
    }

    /// Nor may it lend one when the reading without it found no name at all,
    /// and the model supplies the name beside a code for the other release.
    @available(iOS 26.0, *)
    func testTheLanguageModelDoesNotLendABrandTheCodeArguesAgainst() {
        let unnamed = releasedDraft(["QTY 60 1 MG", "TACROLIMUS CAPSULES", "NDC 0469-0677-73"])
        XCTAssertEqual(unnamed.name, "", "the reading without the model finds no name here")
        XCTAssertEqual(unnamed.identification, .uncorroborated(code: "00469-0677-73", product: "Tacrolimus 1 mg (Astagraf XL)"))
        let candidates = LabelInterpretationCandidates(
            medicationNames: [LabelFieldCandidate(id: 1, value: "TACROLIMUS")],
            strengths: [LabelFieldCandidate(id: 1, value: "1 mg")],
            directions: [],
            quantities: [],
            refills: []
        )
        let selection = LabelFieldSelection(
            medicationNameID: 1,
            normalizedMedicationName: "Tacrolimus",
            strengthID: 1,
            directionsID: 0,
            quantityID: 0,
            refillsID: 0
        )

        let refined = MedicationLabelInterpreter.applying(selection, candidates: candidates, to: unnamed)

        XCTAssertEqual(refined.name, "Tacrolimus")
        XCTAssertEqual(refined.brandName, "", "not Prograf beside a code for Astagraf XL")
        XCTAssertEqual(refined.identification, unnamed.identification)
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
