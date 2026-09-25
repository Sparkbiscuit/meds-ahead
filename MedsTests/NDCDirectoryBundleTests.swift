import XCTest
@testable import Meds

/// The snapshot that ships. These pin real products so a regenerated file that
/// dropped a column, an encoding, or the delisted listings fails loudly.
final class NDCDirectoryBundleTests: XCTestCase {
    private let directory = NDCDirectory.shared

    func testTheSnapshotIsBundledAndLarge() {
        XCTAssertGreaterThan(directory.count, 80_000, "the trimmed FDA directory is about a hundred thousand products")
        let description = try? XCTUnwrap(directory.snapshotDescription)
        XCTAssertTrue(description?.contains("FDA NDC Directory snapshot 20") == true, description ?? "no header")
    }

    func testBrandedListingsCarryTheirBrand() throws {
        let tecfidera = try XCTUnwrap(directory.product(forKey: "644060006"))
        XCTAssertEqual(tecfidera.genericName, "dimethyl fumarate")
        XCTAssertEqual(tecfidera.brandName, "Tecfidera")
        XCTAssertEqual(tecfidera.strength, "240 mg")
        XCTAssertEqual(tecfidera.form, .capsule)

        let prograf = try XCTUnwrap(directory.product(forKey: "004690617"))
        XCTAssertEqual(prograf.genericName, "tacrolimus")
        XCTAssertEqual(prograf.brandName, "Prograf")
        XCTAssertEqual(prograf.strength, "1 mg")
        XCTAssertEqual(prograf.form, .capsule)

        let zoloft = try XCTUnwrap(directory.product(forKey: "581510575"))
        XCTAssertEqual(zoloft.genericName, "sertraline hydrochloride")
        XCTAssertEqual(zoloft.brandName, "Zoloft")
        XCTAssertEqual(zoloft.strength, "50 mg")
        XCTAssertEqual(zoloft.form, .tablet)
    }

    func testGenericListingsCarryNoBrandOfTheirOwn() throws {
        let sertraline = try XCTUnwrap(directory.product(forKey: "167140612"))
        XCTAssertEqual(sertraline.genericName, "sertraline hydrochloride")
        XCTAssertEqual(sertraline.brandName, "", "the proprietary name merely restates the generic")
        XCTAssertEqual(sertraline.strength, "50 mg")

        let azathioprine = try XCTUnwrap(directory.product(forKey: "165710835"))
        XCTAssertEqual(azathioprine.genericName, "azathioprine")
        XCTAssertEqual(azathioprine.brandName, "")
        XCTAssertEqual(azathioprine.strength, "50 mg")
        XCTAssertEqual(azathioprine.form, .tablet)
    }

    func testCombinationsLiquidsAndMixedSaltsAreWrittenTheWayALabelPrintsThem() throws {
        let bactrimDS = try XCTUnwrap(directory.product(forKey: "497080146"))
        XCTAssertEqual(bactrimDS.strength, "800-160 mg")
        XCTAssertEqual(bactrimDS.brandName, "Bactrim DS")
        XCTAssertEqual(bactrimDS.genericName, "sulfamethoxazole and trimethoprim")

        let prednisolone = try XCTUnwrap(directory.product(forKey: "001210759"))
        XCTAssertEqual(prednisolone.strength, "15 mg/5 mL")
        XCTAssertEqual(prednisolone.form, .liquid)

        let adderallXR = try XCTUnwrap(directory.product(forKey: "540920381"))
        XCTAssertEqual(adderallXR.strength, "1.25-1.25-1.25-1.25 mg")
        XCTAssertEqual(adderallXR.brandName, "Adderall XR")
        XCTAssertEqual(adderallXR.form, .capsule)

        // A labeler wrote the form, strength and schedule into the generic name;
        // the tool cuts them off so the name is the name.
        let mixedSalts = try XCTUnwrap(directory.product(forKey: "477810174"))
        XCTAssertEqual(mixedSalts.genericName, "dextroamphetamine saccharate, amphetamine aspartate, dextroamphetamine sulfate, amphetamine sulfate")
        XCTAssertEqual(mixedSalts.brandName, "")
    }

    func testResolvedNamesReadTheWayTheRestOfTheAppSpellsThem() throws {
        XCTAssertEqual(NDCIdentification.displayName(for: try XCTUnwrap(directory.product(forKey: "167140612"))), "Sertraline")
        XCTAssertEqual(NDCIdentification.displayName(for: try XCTUnwrap(directory.product(forKey: "497080146"))), "Sulfamethoxazole / trimethoprim")
        XCTAssertEqual(NDCIdentification.displayName(for: try XCTUnwrap(directory.product(forKey: "001210759"))), "Prednisolone")
        XCTAssertEqual(NDCIdentification.displayName(for: try XCTUnwrap(directory.product(forKey: "644060006"))), "Dimethyl fumarate")
        // Four salts on the listing, two words on the screen.
        XCTAssertEqual(NDCIdentification.displayName(for: try XCTUnwrap(directory.product(forKey: "477810174"))), "Amphetamine - dextroamphetamine")
        XCTAssertEqual(NDCIdentification.displayName(for: try XCTUnwrap(directory.product(forKey: "540920381"))), "Amphetamine - dextroamphetamine")
    }

    /// The release column, pinned on the products it exists for. Prograf and
    /// Astagraf XL are one digit apart and otherwise identical in the file.
    func testTheReleaseColumnTellsTheTacrolimusProductsApart() throws {
        let prograf = try XCTUnwrap(directory.product(forKey: "004690617"))
        XCTAssertEqual(prograf.release, .immediate)

        let astagraf = try XCTUnwrap(directory.product(forKey: "004690677"))
        XCTAssertEqual(astagraf.genericName, "tacrolimus")
        XCTAssertEqual(astagraf.brandName, "Astagraf XL")
        XCTAssertEqual(astagraf.strength, "1 mg")
        XCTAssertEqual(astagraf.form, .capsule)
        XCTAssertEqual(astagraf.release, .extended)

        let envarsus = try XCTUnwrap(directory.product(forKey: "689923010"))
        XCTAssertEqual(envarsus.brandName, "Envarsus XR")
        XCTAssertEqual(envarsus.form, .tablet)
        XCTAssertEqual(envarsus.release, .extended)

        let genericExtended = try XCTUnwrap(directory.product(forKey: "714322002"))
        XCTAssertEqual(genericExtended.genericName, "tacrolimus")
        XCTAssertEqual(genericExtended.brandName, "")
        XCTAssertEqual(genericExtended.release, .extended)
    }

    func testTheReleaseColumnOnOtherModifiedReleaseProducts() throws {
        let toprol = try XCTUnwrap(directory.product(forKey: "708420111"))
        XCTAssertEqual(toprol.genericName, "metoprolol succinate")
        XCTAssertEqual(toprol.brandName, "Toprol XL")
        XCTAssertEqual(toprol.strength, "50 mg")
        XCTAssertEqual(toprol.release, .extended)

        let succinate = try XCTUnwrap(directory.product(forKey: "006157824"))
        XCTAssertEqual(succinate.genericName, "metoprolol succinate")
        XCTAssertEqual(succinate.brandName, "")
        XCTAssertEqual(succinate.release, .extended)

        let myfortic = try XCTUnwrap(directory.product(forKey: "000780386"))
        XCTAssertEqual(myfortic.genericName, "mycophenolic acid")
        XCTAssertEqual(myfortic.brandName, "Myfortic")
        XCTAssertEqual(myfortic.strength, "360 mg")
        XCTAssertEqual(myfortic.release, .delayed)

        // A repackager's listing whose release is only in its generic name,
        // "Metformin ER 500 mg", filed as a plain TABLET.
        let metformin = try XCTUnwrap(directory.product(forKey: "500906515"))
        XCTAssertEqual(metformin.genericName, "metformin er")
        XCTAssertEqual(metformin.form, .tablet)
        XCTAssertEqual(metformin.release, .extended)
        XCTAssertEqual(directory.product(forKey: "716100613")?.release, .extended)

        XCTAssertEqual(directory.product(forKey: "540920381")?.release, .extended, "Adderall XR")
        XCTAssertEqual(directory.product(forKey: "167140612")?.release, .immediate, "a generic sertraline")
        // The FDA lists Tecfidera as a plain CAPSULE, which is why a label that
        // says DR does not refuse a listing that claims no release.
        XCTAssertEqual(directory.product(forKey: "644060006")?.release, .immediate)
    }

    /// The confirmed hazard, against the file that ships: 0469-0617 misread
    /// as 0469-0677 on a Prograf label is refused, on a label that does not
    /// say which release fills nothing, and on an Astagraf XL label is
    /// accepted.
    func testAMisreadTacrolimusCodeAgainstTheSnapshot() {
        let prograf = draft(["RIVERSIDE CHILDREN'S HOSPITAL PHARMACY", "PROGRAF 1 MG CAPSULE", "NDC 0469-0677-73", "TAKE 1 CAPSULE BY MOUTH TWICE DAILY"])
        XCTAssertEqual(prograf.identification, .contradicted(code: "00469-0677-73", product: "Tacrolimus 1 mg (Astagraf XL)"))
        XCTAssertEqual(prograf.name, "Tacrolimus")
        XCTAssertEqual(prograf.brandName, "Prograf")
        XCTAssertEqual(prograf.rxNormCode, "")

        let plain = draft(["RIVERSIDE CHILDREN'S HOSPITAL PHARMACY", "TACROLIMUS 1 MG CAPSULE", "NDC 0469-0677-73", "TAKE 1 CAPSULE BY MOUTH TWICE DAILY"])
        XCTAssertEqual(plain.identification, .uncorroborated(code: "00469-0677-73", product: "Tacrolimus 1 mg (Astagraf XL)"))
        XCTAssertNotEqual(plain.nameProvenance, .ndc)
        XCTAssertNotEqual(plain.brandName, "Astagraf XL")

        let astagraf = draft(["RIVERSIDE CHILDREN'S HOSPITAL PHARMACY", "ASTAGRAF XL 1 MG CAPSULE", "NDC 0469-0677-73", "TAKE 1 CAPSULE BY MOUTH ONCE DAILY"])
        XCTAssertEqual(astagraf.identification, .accepted(code: "00469-0677-73"))
        XCTAssertEqual(astagraf.name, "Tacrolimus")
        XCTAssertEqual(astagraf.brandName, "Astagraf XL")
        XCTAssertFalse(astagraf.rxNormCode.isEmpty)
        XCTAssertNotEqual(
            RxNormTable.shared.clinicalDrugCode(for: astagraf.rxNormCode),
            RxNormTable.shared.product(forProductKey: "004690617")?.clinicalDrugCode,
            "Health and the sync never read the two releases as one clinical drug"
        )

        let extended = draft(["RIVERSIDE CHILDREN'S HOSPITAL PHARMACY", "TACROLIMUS XL 1 MG CAPSULE", "NDC 0469-0617-73"])
        XCTAssertEqual(extended.identification, .contradicted(code: "00469-0617-73", product: "Tacrolimus 1 mg (Prograf)"))
        XCTAssertNotEqual(extended.brandName, "Prograf")
    }

    /// Labels that once filled the wrong release from a code misread by one
    /// digit, against the file that ships: a dosing interval taken for a
    /// release, a brand printed on a line of its own, and release letters
    /// wrapped onto the next line.
    func testMoreMisreadTacrolimusLabelsAgainstTheSnapshot() {
        for lines in [
            ["RIVERSIDE PHARMACY", "TACROLIMUS 1 MG CAPSULE EVERY 12 HOURS", "NDC 0469-0677-73"],
            ["RIVERSIDE PHARMACY", "TAKE 1 TACROLIMUS 1 MG CAPSULE BY MOUTH EVERY 12 HOURS", "NDC 0469-0677-73"],
            ["RIVERSIDE PHARMACY", "TACROLIMUS 1 MG CAPSULE 12 HR", "NDC 0469-0677-73"]
        ] {
            let label = draft(lines)
            XCTAssertEqual(label.identification, .uncorroborated(code: "00469-0677-73", product: "Tacrolimus 1 mg (Astagraf XL)"), "\(lines)")
            XCTAssertNotEqual(label.brandName, "Astagraf XL", "\(lines)")
            XCTAssertNotEqual(label.brandName, "Prograf", "\(lines)")
            XCTAssertEqual(label.rxNormCode, "", "\(lines)")
        }
        for lines in [
            ["RIVERSIDE PHARMACY", "TACROLIMUS 1 MG CAPSULE", "ASTAGRAF XL", "NDC 0469-0617-73"],
            ["RIVERSIDE PHARMACY", "TACROLIMUS 1 MG CAPSULE", "GENERIC FOR ASTAGRAF XL", "NDC 0469-0617-73"],
            ["RIVERSIDE PHARMACY", "TACROLIMUS", "XL 1 MG CAPSULE", "NDC 0469-0617-73"],
            ["RIVERSIDE PHARMACY", "TACROLIMUS 1 MG", "ER CAPSULE", "NDC 0469-0617-73"]
        ] {
            let label = draft(lines)
            XCTAssertEqual(label.identification, .contradicted(code: "00469-0617-73", product: "Tacrolimus 1 mg (Prograf)"), "\(lines)")
            XCTAssertNotEqual(label.brandName, "Prograf", "\(lines)")
            XCTAssertEqual(label.rxNormCode, "", "\(lines)")
        }
    }

    /// 50090-6515 is extended-release metformin that the FDA files as a plain
    /// tablet, with the release only in its generic name.
    func testAMetforminListingThatSaysERInItsNameAgainstTheSnapshot() {
        let extended = draft(["RIVERSIDE PHARMACY", "METFORMIN ER 500 MG TABLET", "NDC 50090-6515-0"])
        XCTAssertEqual(extended.identification, .accepted(code: "50090-6515-00"))

        let immediate = draft(["RIVERSIDE PHARMACY", "METFORMIN HCL 500 MG TABLET", "NDC 50090-6515-0"])
        XCTAssertEqual(immediate.identification, .uncorroborated(code: "50090-6515-00", product: "Metformin er 500 mg extended-release"))
        XCTAssertNotEqual(immediate.nameProvenance, .ndc)
        XCTAssertEqual(immediate.rxNormCode, "")
        XCTAssertEqual(immediate.brandName, "", "neither the code's release nor Glucophage settles it")
    }

    private func draft(_ lines: [String]) -> MedicationDraft {
        let capture = UUID()
        let evidence = lines.enumerated().map { index, value in
            ScanEvidence(kind: .text, value: value, confidence: 0.9, origin: .cameraCapture, captureID: capture, lineIndex: index)
        }
        return MedicationLabelInterpreter.offlineDraft(evidence)
    }

    /// A hospital pharmacy label, end to end against the shipped snapshot.
    func testAHospitalLabelResolvesAgainstTheSnapshot() {
        let capture = UUID()
        let evidence = [
            "RIVERSIDE CHILDREN'S HOSPITAL PHARMACY", "300 HARBOR AVENUE", "RX# 4402917",
            "TACROLIMUS 1 MG CAPSULE", "NDC 0469-0617-73",
            "TAKE 1 CAPSULE BY MOUTH TWICE DAILY", "QTY: 60"
        ].enumerated().map { index, value in
            ScanEvidence(kind: .text, value: value, confidence: 0.9, origin: .cameraCapture, captureID: capture, lineIndex: index)
        }

        let draft = MedicationLabelInterpreter.offlineDraft(evidence)

        XCTAssertEqual(draft.nameProvenance, .ndc)
        XCTAssertEqual(draft.name, "Tacrolimus")
        XCTAssertEqual(draft.brandName, "Prograf")
        XCTAssertEqual(draft.strength, "1 mg")
        XCTAssertEqual(draft.form, .capsule)
        XCTAssertEqual(draft.productIdentifier, "00469-0617-73")
    }
}
