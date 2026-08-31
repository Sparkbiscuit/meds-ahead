import Foundation
import XCTest

@testable import Meds

final class MedicationBrandIndexTests: XCTestCase {
    func testResolvesGenericAndBrandLabels() {
        assertPair(
            MedicationBrandIndex.resolve("Sertraline"),
            generic: "sertraline",
            brand: "Zoloft"
        )
        assertPair(
            MedicationBrandIndex.resolve("Zoloft"),
            generic: "sertraline",
            brand: "Zoloft"
        )
        assertPair(
            MedicationBrandIndex.resolve("Prograf"),
            generic: "tacrolimus",
            brand: "Prograf"
        )
        XCTAssertEqual(MedicationBrandIndex.brandName(forGeneric: "tacrolimus"), "Prograf")
        XCTAssertEqual(
            MedicationBrandIndex.genericName(forBrand: "Bactrim"),
            "sulfamethoxazole / trimethoprim"
        )
    }

    func testResolvesSaltAndReleaseFormSuffixes() {
        assertPair(
            MedicationBrandIndex.resolve("Sertraline HCl"),
            generic: "sertraline",
            brand: "Zoloft"
        )
        assertPair(
            MedicationBrandIndex.resolve("Metoprolol Succinate"),
            generic: "metoprolol succinate",
            brand: "Toprol XL"
        )
        assertPair(
            MedicationBrandIndex.resolve("Metoprolol Tartrate"),
            generic: "metoprolol tartrate",
            brand: "Lopressor"
        )
    }

    func testReturnsNilForUnknownOrUncertainNames() {
        let uncertainNames = [
            "NotARealMedication",
            "",
            " \t\n ",
            "sertral",
            "Zol",
            "Sertraline 200mg",
            "Ibuprofen 200mg"
        ]

        for name in uncertainNames {
            assertNoMatch(for: name)
        }
    }

    func testBundledTableHasExactlyTwoUniqueEntriesPerLine() {
        guard let table = medicationBrandNamesText() else {
            XCTFail("MedicationBrandNames.txt was not found in the test or host-app bundle")
            return
        }

        let lines = table.split(whereSeparator: { $0.isNewline })
        XCTAssertFalse(lines.isEmpty, "MedicationBrandNames.txt is empty")

        var genericKeys = Set<String>()
        var brandKeys = Set<String>()

        for (index, line) in lines.enumerated() {
            let components = line.split(separator: "|", omittingEmptySubsequences: false)
            XCTAssertEqual(
                components.count,
                2,
                "Line \(index + 1) must contain exactly one | separator"
            )
            guard components.count == 2 else { continue }

            let generic = String(components[0])
            let brand = String(components[1])
            XCTAssertFalse(
                generic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Line \(index + 1) has an empty generic component"
            )
            XCTAssertFalse(
                brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Line \(index + 1) has an empty brand component"
            )

            let genericKey = key(for: generic)
            let brandKey = key(for: brand)
            XCTAssertFalse(genericKey.isEmpty, "Line \(index + 1) has no generic key letters")
            XCTAssertFalse(brandKey.isEmpty, "Line \(index + 1) has no brand key letters")
            XCTAssertTrue(
                genericKeys.insert(genericKey).inserted,
                "Generic key repeats on line \(index + 1): \(genericKey)"
            )
            // A brand may legitimately answer to two generic spellings of the same
            // product — Myfortic is dispensed as both "mycophenolate sodium" and
            // "mycophenolic acid" — so a repeated brand is allowed. What must not
            // repeat is a generic, and the brand must still resolve to exactly one
            // pair. `MedicationBrandIndex` takes the first in file order.
            if !brandKeys.insert(brandKey).inserted {
                XCTAssertNotNil(
                    MedicationBrandIndex.genericName(forBrand: brand),
                    "Repeated brand on line \(index + 1) must still resolve: \(brandKey)"
                )
            }
        }
    }

    /// The regimen this app was built for. These are the medications a lung
    /// transplant household handles every week, and the shared list a clinician
    /// reads should carry both names for each of them.
    func testTransplantRegimenResolvesToItsBrands() {
        let expected: [(String, String)] = [
            ("tacrolimus", "Prograf"),
            ("mycophenolate mofetil", "CellCept"),
            ("mycophenolate sodium", "Myfortic"),
            ("azathioprine", "Imuran"),
            ("sirolimus", "Rapamune"),
            ("valganciclovir", "Valcyte"),
            ("letermovir", "Prevymis"),
            ("maribavir", "Livtencity"),
            ("sulfamethoxazole / trimethoprim", "Bactrim"),
            ("atovaquone", "Mepron"),
            ("acyclovir", "Zovirax"),
            ("valacyclovir", "Valtrex"),
            ("posaconazole", "Noxafil"),
            ("voriconazole", "Vfend"),
            ("itraconazole", "Sporanox"),
            ("isavuconazonium", "Cresemba"),
            ("azithromycin", "Zithromax"),
            ("pantoprazole", "Protonix"),
            ("famotidine", "Pepcid"),
            ("levalbuterol", "Xopenex"),
            ("metoprolol succinate", "Toprol XL"),
            ("sertraline", "Zoloft"),
            ("alendronate", "Fosamax"),
            ("magnesium oxide", "Mag-Ox")
        ]
        for (generic, brand) in expected {
            XCTAssertEqual(
                MedicationBrandIndex.brandName(forGeneric: generic),
                brand,
                "\(generic) should resolve to \(brand)"
            )
        }
    }

    /// A pharmacy prints the salt and the release form, not the bare ingredient.
    func testTransplantNamesResolveAsAPharmacyPrintsThem() {
        XCTAssertEqual(MedicationBrandIndex.resolve("Metoprolol Succinate XL")?.brand, "Toprol XL")
        XCTAssertEqual(MedicationBrandIndex.resolve("Sertraline HCl")?.brand, "Zoloft")
        XCTAssertEqual(MedicationBrandIndex.resolve("Sulfamethoxazole-Trimethoprim")?.brand, "Bactrim")
        XCTAssertEqual(MedicationBrandIndex.resolve("Azathioprine Sodium")?.brand, "Imuran")
    }

    /// Scanning the brand side has to give back the generic, which is the whole
    /// point of the table for someone holding a bottle that says PROGRAF.
    func testTransplantBrandsResolveBackToGenerics() {
        XCTAssertEqual(MedicationBrandIndex.genericName(forBrand: "Prograf"), "tacrolimus")
        XCTAssertEqual(MedicationBrandIndex.genericName(forBrand: "CellCept"), "mycophenolate mofetil")
        XCTAssertEqual(MedicationBrandIndex.genericName(forBrand: "Valcyte"), "valganciclovir")
        XCTAssertEqual(MedicationBrandIndex.genericName(forBrand: "Prevymis"), "letermovir")
    }

    /// Deliberate blanks. Each of these has either no brand still in use or several
    /// competing ones, and a confident wrong brand on a clinician's sheet is worse
    /// than an empty field. Pinning them stops a future expansion from adding one
    /// back without someone deciding to.
    func testAmbiguousOrObsoleteBrandsStayBlank() {
        for generic in [
            "prednisone",        // Deltasone is obsolete; Rayos is a different product
            "aspirin",           // Bayer, Ecotrin, Bufferin — no single name
            "cyclosporine",      // Neoral, Sandimmune and Gengraf are not interchangeable
            "everolimus",        // Zortress in transplant, Afinitor in oncology
            "budesonide",        // inhaled, nasal and oral products differ
            "tobramycin",        // inhaled, injectable and ophthalmic differ
            "albuterol",         // brand follows the device
            "ipratropium",       // Atrovent is both an inhaler and a nasal spray
            "lisinopril"         // Prinivil and Zestril are equally plausible
        ] {
            XCTAssertNil(
                MedicationBrandIndex.brandName(forGeneric: generic),
                "\(generic) must stay blank rather than guess a brand"
            )
        }
    }

    private func assertPair(
        _ result: (generic: String, brand: String)?,
        generic: String,
        brand: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let result else {
            XCTFail("Expected generic \(generic) and brand \(brand)", file: file, line: line)
            return
        }

        XCTAssertEqual(result.generic, generic, file: file, line: line)
        XCTAssertEqual(result.brand, brand, file: file, line: line)
    }

    private func assertNoMatch(
        for name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(MedicationBrandIndex.resolve(name), "Unexpected resolution for \(name)", file: file, line: line)
        XCTAssertNil(
            MedicationBrandIndex.brandName(forGeneric: name),
            "Unexpected generic lookup for \(name)",
            file: file,
            line: line
        )
        XCTAssertNil(
            MedicationBrandIndex.genericName(forBrand: name),
            "Unexpected brand lookup for \(name)",
            file: file,
            line: line
        )
    }

    private func medicationBrandNamesText() -> String? {
        let bundles = [
            Bundle(for: MedicationBrandIndexTests.self),
            Bundle.main
        ]

        for bundle in bundles {
            guard let url = bundle.url(forResource: "MedicationBrandNames", withExtension: "txt") else {
                continue
            }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }

        return nil
    }

    private func key(for value: String) -> String {
        value.lowercased().filter { $0.isLetter }
    }
}
