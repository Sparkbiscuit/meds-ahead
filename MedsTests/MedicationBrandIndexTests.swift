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
            XCTAssertTrue(
                brandKeys.insert(brandKey).inserted,
                "Brand key repeats on line \(index + 1): \(brandKey)"
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
