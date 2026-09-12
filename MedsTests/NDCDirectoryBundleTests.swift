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

    /// A label from the household, end to end against the shipped snapshot.
    func testAHouseholdLabelResolvesAgainstTheSnapshot() {
        let capture = UUID()
        let evidence = [
            "BOSTON CHILDREN'S HOSPITAL PHARMACY", "300 LONGWOOD AVENUE", "RX# 7719204",
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

    func testLookupIsFastEnoughForTheLivePreview() {
        measure {
            for key in ["644060006", "004690617", "581510575", "167140612", "000000000", "999999999"] {
                _ = directory.product(forKey: key)
            }
        }
    }
}
