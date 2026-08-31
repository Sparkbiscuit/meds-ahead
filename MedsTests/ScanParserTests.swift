import XCTest
@testable import Meds

final class ScanParserTests: XCTestCase {
    func testParsesManufacturerLabelAndGS1Code() {
        let evidence = [
            ScanEvidence(kind: .text, value: "Each capsule contains"),
            ScanEvidence(kind: .text, value: "240 mg dimethyl fumarate"),
            ScanEvidence(kind: .text, value: "LOT SH0752"),
            ScanEvidence(kind: .text, value: "EXP 05/2029"),
            ScanEvidence(kind: .barcode, value: "0100364406006029", symbology: "GS1 DataBar Limited")
        ]

        let draft = ScanParser.parse(evidence)

        XCTAssertEqual(draft.name.lowercased(), "dimethyl fumarate")
        XCTAssertEqual(draft.strength.lowercased(), "240 mg")
        XCTAssertEqual(draft.form, .capsule)
        XCTAssertEqual(draft.lotNumber, "SH0752")
        XCTAssertEqual(draft.productIdentifier, "0100364406006029")
    }

    func testParsesOTCQuantity() {
        let evidence = [
            ScanEvidence(kind: .text, value: "Melatonin"),
            ScanEvidence(kind: .text, value: "5 mg"),
            ScanEvidence(kind: .text, value: "CONTENTS\n120 TABLETS"),
            ScanEvidence(kind: .barcode, value: "0036800401044", symbology: "EAN-13")
        ]
        let draft = ScanParser.parse(evidence)

        XCTAssertEqual(draft.name, "Melatonin")
        XCTAssertEqual(draft.strength.lowercased(), "5 mg")
        XCTAssertEqual(draft.currentSupply, 120)
    }

    func testPrefersNonURLBarcode() {
        let evidence = [
            ScanEvidence(kind: .barcode, value: "https://example.invalid/private", symbology: "QR"),
            ScanEvidence(kind: .barcode, value: "323615013", symbology: "Code 128")
        ]
        XCTAssertEqual(ScanParser.parse(evidence).productIdentifier, "323615013")
    }

    func testNoRefillsLeftParsesAsZero() {
        let evidence = [ScanEvidence(kind: .text, value: "No refills left")]
        XCTAssertEqual(ScanParser.parse(evidence).refillsRemaining, 0)
    }

    func testParsesCommonLabeledRefillFormats() {
        for value in ["Refills: 3", "REFILLS REMAINING 3", "Rfls #3", "3 refills"] {
            let evidence = [ScanEvidence(kind: .text, value: value)]
            XCTAssertEqual(ScanParser.parse(evidence).refillsRemaining, 3, value)
        }
    }

    func testLowConfidenceFragmentDoesNotOverrideMedicationName() {
        let evidence = [
            ScanEvidence(kind: .text, value: "Fur0 random", confidence: 0.31),
            ScanEvidence(kind: .text, value: "Furosemide", confidence: 0.94),
            ScanEvidence(kind: .text, value: "20 mg", confidence: 0.97)
        ]

        let draft = ScanParser.parse(evidence)

        XCTAssertEqual(draft.name, "Furosemide")
        XCTAssertEqual(draft.strength.lowercased(), "20 mg")
        XCTAssertEqual(draft.evidence.count, 3, "Raw evidence remains available for human review")
    }

    func testLowConfidenceContextCanStillSupplyExplicitField() {
        let evidence = [
            ScanEvidence(kind: .text, value: "Qty 30", confidence: 0.34)
        ]

        XCTAssertEqual(ScanParser.parse(evidence).currentSupply, 30)
    }

    func testLiveEvidenceMergeRetainsLowConfidenceTextForSemanticReview() {
        let liveText = ScanEvidence(
            kind: .text,
            value: "AMPHETAMINE",
            confidence: 0.12,
            origin: .liveCamera
        )

        let merged = ScanEvidenceQuality.mergingBest(
            existing: [],
            additions: [liveText]
        )

        XCTAssertEqual(merged.map(\.value), ["AMPHETAMINE"])
    }

    func testHighResolutionCaptureRetainsLowConfidenceDrugFragmentForVocabularyRepair() {
        let captured = ScanEvidence(
            kind: .text,
            value: "AMPHETAMINE - DEXTROAMPHET",
            confidence: 0.27,
            origin: .cameraCapture
        )

        let merged = ScanEvidenceQuality.mergingBest(existing: [], additions: [captured])

        XCTAssertEqual(merged.map(\.value), ["AMPHETAMINE - DEXTROAMPHET"])
        XCTAssertEqual(
            MedicationLabelInterpreter.offlineDraft(merged).name,
            "Amphetamine - dextroamphetamine"
        )
    }

    func testLiveCameraConfidenceDoesNotSuppressStructuredLabelFields() {
        let evidence = [
            ScanEvidence(kind: .text, value: "FUROSEMIDE", confidence: 0.12),
            ScanEvidence(kind: .text, value: "20 mg tablet", confidence: 0.16),
            ScanEvidence(kind: .text, value: "TAKE ONE TABLET DAILY", confidence: 0.14),
            ScanEvidence(kind: .text, value: "Qty: 30", confidence: 0.11),
            ScanEvidence(kind: .text, value: "Refills: 2", confidence: 0.10)
        ]

        let draft = ScanParser.parse(evidence)

        XCTAssertEqual(draft.name, "Furosemide")
        XCTAssertEqual(draft.strength.lowercased(), "20 mg")
        XCTAssertEqual(draft.form, .tablet)
        XCTAssertEqual(draft.directions, "TAKE ONE TABLET DAILY")
        XCTAssertEqual(draft.currentSupply, 30)
        XCTAssertEqual(draft.refillsRemaining, 2)
    }

    func testEvidenceMergeKeepsBestConfidenceForEquivalentReading() throws {
        let earlier = ScanEvidence(kind: .text, value: "FUROSEMIDE", confidence: 0.62)
        let corrected = ScanEvidence(kind: .text, value: "  furosemide. ", confidence: 0.96)

        let merged = ScanEvidenceQuality.mergingBest(existing: [earlier], additions: [corrected])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(try XCTUnwrap(merged.first).id, corrected.id)
    }

    func testEvidenceMergeReplacesMissingFirstLetterWithCompleteReading() throws {
        let fragment = ScanEvidence(kind: .text, value: "elatonin", confidence: 0.84)
        let complete = ScanEvidence(kind: .text, value: "Melatonin", confidence: 0.84)

        let merged = ScanEvidenceQuality.mergingBest(existing: [fragment], additions: [complete])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(try XCTUnwrap(merged.first).value, "Melatonin")
    }

    func testEvidenceMergeCollapsesOCRSpellingAlternatives() throws {
        let primary = ScanEvidence(kind: .text, value: "Melatonin", confidence: 1)
        let alternate = ScanEvidence(kind: .text, value: "Meltonin", confidence: 0.5)

        let merged = ScanEvidenceQuality.mergingBest(existing: [], additions: [primary, alternate])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(try XCTUnwrap(merged.first).value, "Melatonin")
    }

    func testIncompleteDirectionsFromCurvedLabelAreNotAutofilled() {
        let evidence = [ScanEvidence(kind: .text, value: "TAKE ONE TABLET BY MO.")]

        XCTAssertEqual(ScanParser.parse(evidence).directions, "")
    }

    func testPackageCountParsesAsCurrentSupply() {
        let evidence = [ScanEvidence(kind: .text, value: "120 TABLETS")]

        XCTAssertEqual(ScanParser.parse(evidence).currentSupply, 120)
    }

    func testDirectionsDoseCountIsNotMistakenForPackageQuantity() {
        // An OTC label with no printed QTY: the directions line fits the bare
        // "(N) tablets" shape and used to autofill a supply of 1.
        let evidence = [
            ScanEvidence(kind: .text, value: "Ibuprofen"),
            ScanEvidence(kind: .text, value: "200 mg"),
            ScanEvidence(kind: .text, value: "Take 1 tablet every 6 hours"),
            ScanEvidence(kind: .text, value: "100 tablets")
        ]

        XCTAssertEqual(ScanParser.parse(evidence).currentSupply, 100)
    }

    func testDirectionsAloneLeaveQuantityEmpty() {
        let evidence = [ScanEvidence(kind: .text, value: "Take 2 tablets daily")]

        XCTAssertNil(ScanParser.parse(evidence).currentSupply)
    }

    func testNameOnStrengthLineDropsDosageFormWords() {
        let evidence = [
            ScanEvidence(kind: .text, value: "FUROSEMIDE 20 MG TABLETS", confidence: 0.92),
            ScanEvidence(kind: .text, value: "TAKE ONE TABLET DAILY", confidence: 0.97)
        ]

        let draft = ScanParser.parse(evidence)

        XCTAssertEqual(draft.name, "Furosemide")
        XCTAssertEqual(draft.strength.lowercased(), "20 mg")
    }

    func testPatientNameIsNotChosenAsMedicationName() {
        let evidence = [
            ScanEvidence(kind: .text, value: "Patient", confidence: 0.99),
            ScanEvidence(kind: .text, value: "Alex Morgan", confidence: 0.99),
            ScanEvidence(kind: .text, value: "Furosemide", confidence: 0.86)
        ]

        XCTAssertEqual(ScanParser.parse(evidence).name, "Furosemide")
    }

    func testAmbiguousPackagingTextLeavesMedicationNameBlank() {
        let evidence = [
            ScanEvidence(kind: .text, value: "Natural Cherry", confidence: 0.98),
            ScanEvidence(kind: .text, value: "May Help Support Sleep", confidence: 0.97),
            ScanEvidence(kind: .text, value: "Store in a cool dry place", confidence: 0.96)
        ]

        XCTAssertEqual(ScanParser.parse(evidence).name, "")
    }

    func testPrintedNDCIsUsedWhenNoBarcodeDecodes() {
        let evidence = [
            ScanEvidence(kind: .text, value: "NDC 00054-8179-25", confidence: 0.96)
        ]

        let draft = ScanParser.parse(evidence)

        XCTAssertEqual(draft.productIdentifier, "00054-8179-25")
        XCTAssertEqual(draft.productIdentifierType, "NDC")
    }

    func testDirectionsIgnoreExpirationAndSupplementFragments() {
        let evidence = [
            ScanEvidence(kind: .text, value: "Furosemide", confidence: 0.92),
            ScanEvidence(kind: .text, value: "20 mg", confidence: 0.96),
            ScanEvidence(kind: .text, value: "USE BY 05/2029", confidence: 0.99),
            ScanEvidence(kind: .text, value: "% DAILY VALUE", confidence: 0.99),
            ScanEvidence(kind: .text, value: "TAKE ONE TABLET DAILY", confidence: 0.84)
        ]

        XCTAssertEqual(ScanParser.parse(evidence).directions, "TAKE ONE TABLET DAILY")
    }

    func testDirectionsAcceptDoseFrequencyWithoutVerb() {
        let evidence = [
            ScanEvidence(kind: .text, value: "ONE CAPSULE TWICE DAILY", confidence: 0.88)
        ]

        XCTAssertEqual(ScanParser.parse(evidence).directions, "ONE CAPSULE TWICE DAILY")
    }

    func testNonLatinOCRFragmentsNeverReachParser() {
        let evidence = [
            ScanEvidence(kind: .text, value: "Мелатонин", confidence: 0.99),
            ScanEvidence(kind: .text, value: "褪黑素", confidence: 0.99),
            ScanEvidence(kind: .text, value: "Melatonin", confidence: 0.90),
            ScanEvidence(kind: .text, value: "5 mg", confidence: 0.90)
        ]

        let draft = ScanParser.parse(evidence)

        XCTAssertEqual(draft.name, "Melatonin")
        XCTAssertEqual(draft.evidence.map(\.value), ["Melatonin", "5 mg"])
    }

    /// Insulin, heparin and vitamin D are dosed in units, and leaving the strength
    /// blank on those labels made someone retype what the vial plainly says.
    func testUnitDenominatedStrengthsAreRecognized() {
        XCTAssertEqual(
            ScanParser.parse([ScanEvidence(kind: .text, value: "INSULIN GLARGINE 100 units/mL")]).strength,
            "100 units/mL"
        )
        XCTAssertEqual(
            ScanParser.parse([ScanEvidence(kind: .text, value: "VITAMIN D3 2000 IU SOFTGEL")]).strength,
            "2000 IU"
        )
    }

    /// A directions line quotes an amount to take, not the strength of the product.
    /// On an insulin label both are units, so the product line has to win.
    func testStrengthPrefersTheProductLineOverTheDirections() {
        let draft = ScanParser.parse([
            ScanEvidence(kind: .text, value: "Inject 10 units subcutaneously once daily", lineIndex: 0),
            ScanEvidence(kind: .text, value: "INSULIN GLARGINE 100 units/mL", lineIndex: 1)
        ])
        XCTAssertEqual(draft.strength, "100 units/mL")
    }

    func testHyphenatedCombinationStrengthKeepsBothComponents() {
        XCTAssertEqual(
            ScanParser.parse([
                ScanEvidence(
                    kind: .text,
                    value: "SULFAMETHOXAZOLE/TRIMETHOPRIM 400-80 MG TAB",
                    confidence: 0.98
                )
            ]).strength,
            "400-80 mg"
        )
    }

    func testSlashedCombinationStrengthKeepsBothComponents() {
        XCTAssertEqual(
            ScanParser.parse([
                ScanEvidence(
                    kind: .text,
                    value: "HYDROCODONE/ACETAMINOPHEN 5/325 MG",
                    confidence: 0.98
                )
            ]).strength,
            "5/325 mg"
        )
    }

    func testCombinationStrengthWithUnitsOnBothHalvesKeepsBothUnits() {
        XCTAssertEqual(
            ScanParser.parse([
                ScanEvidence(kind: .text, value: "800 MG / 160 MG", confidence: 0.98)
            ]).strength,
            // Separators carry no surrounding spaces, so "400-80 mg" and
            // "800 mg/160 mg" read as one strength rather than two.
            "800 mg/160 mg"
        )
    }

    func testUnitsPerMilliliterRatioStrengthRemainsSupported() {
        XCTAssertEqual(
            ScanParser.parse([
                ScanEvidence(kind: .text, value: "INSULIN GLARGINE 100 UNITS/ML", confidence: 0.98)
            ]).strength,
            "100 units/mL"
        )
    }

    func testCompactStrengthTextIsCanonicalizedWhenParsing() {
        XCTAssertEqual(
            ScanParser.parse([
                ScanEvidence(kind: .text, value: "SERTRALINE HCL 50MG", confidence: 0.98)
            ]).strength,
            "50 mg"
        )
    }

    func testNormalizedStrengthReturnsCanonicalValueOnlyForStrengthText() {
        XCTAssertEqual(ScanParser.normalizedStrength("50MG"), "50 mg")
        XCTAssertNil(ScanParser.normalizedStrength("Take one tablet"))
    }

    func testStrengthMatchesReturnsCanonicalStrengthsInOrder() {
        XCTAssertEqual(
            ScanParser.strengthMatches(in: "AMOXICILLIN 875 MG / CLAVULANATE 125 MG"),
            ["875 mg", "125 mg"]
        )
    }

    func testFilledPharmacyLineIsNotTrustedAsDirections() {
        let value = "is Filled: 8/13/2026 RPh: Mg by mouth 1 time each chew."

        XCTAssertEqual(
            ScanParser.parse([
                ScanEvidence(kind: .text, value: value, confidence: 0.98)
            ]).directions,
            ""
        )
        XCTAssertFalse(ScanParser.isTrustedDirections(value))
    }

    func testOCRFragmentWithoutDirectionOpeningIsNotTrustedAsDirections() {
        let value = "- capsule by mouth 2 tim agNe 8.5 mg total twice da"

        XCTAssertEqual(
            ScanParser.parse([
                ScanEvidence(kind: .text, value: value, confidence: 0.98)
            ]).directions,
            ""
        )
        XCTAssertFalse(ScanParser.isTrustedDirections(value))
    }

    func testMangledWeekdayFragmentIsNotTrustedAsDirections() {
        let value = "like 2 tablets by mouth rednesdays, and fridays"

        XCTAssertEqual(
            ScanParser.parse([
                ScanEvidence(kind: .text, value: value, confidence: 0.98)
            ]).directions,
            ""
        )
        XCTAssertFalse(ScanParser.isTrustedDirections(value))
    }

    func testVerbDirectionsRemainTrusted() {
        let value = "Take 1 tablet by mouth twice daily"

        XCTAssertEqual(
            ScanParser.parse([
                ScanEvidence(kind: .text, value: value, confidence: 0.98)
            ]).directions,
            value
        )
    }

    func testNoVerbCompleteSigRemainsTrusted() {
        XCTAssertTrue(ScanParser.isTrustedDirections("ONE CAPSULE TWICE DAILY"))
    }

    func testAsDirectedDirectionsRemainTrusted() {
        let value = "TAKE 2 TABLETS BY MOUTH AS DIRECTED"

        XCTAssertEqual(
            ScanParser.parse([
                ScanEvidence(kind: .text, value: value, confidence: 0.98)
            ]).directions,
            value
        )
    }

    func testWrappedDirectionsJoinAdjacentOCRLines() {
        let evidence = [
            ScanEvidence(
                kind: .text,
                value: "TAKE 2 TABLETS BY MOUTH ON MONDAYS,\nWEDNESDAYS, AND FRIDAYS",
                confidence: 0.98
            )
        ]

        XCTAssertEqual(
            ScanParser.parse(evidence).directions,
            "TAKE 2 TABLETS BY MOUTH ON MONDAYS, WEDNESDAYS, AND FRIDAYS"
        )
    }

    func testUntrustedAdjacentLinesAreNotJoinedAsDirections() {
        let evidence = [
            ScanEvidence(
                kind: .text,
                value: "TAKE 2 TABLETS BY MOUTH\nWITH WATER",
                confidence: 0.98
            )
        ]

        XCTAssertEqual(ScanParser.parse(evidence).directions, "")
    }

    func testTrailingPharmacyImprintIsRemovedFromStrengthAnchoredName() {
        XCTAssertEqual(
            ScanParser.parse([
                ScanEvidence(kind: .text, value: "SERTRALINE HCL 50MG G1", confidence: 0.98)
            ]).name,
            "Sertraline HCl"
        )
    }

    func testLegitimateMultiWordNameIsNotTruncatedAfterStrengthRemoval() {
        XCTAssertEqual(
            ScanParser.parse([
                ScanEvidence(
                    kind: .text,
                    value: "METOPROLOL SUCCINATE 50 MG",
                    confidence: 0.98
                )
            ]).name,
            "Metoprolol Succinate"
        )
    }

    func testWrappedDirectionsDoNotJoinAcrossEvidenceCaptures() {
        let separateCaptures = [
            ScanEvidence(kind: .text, value: "TAKE 1 TABLET"),
            ScanEvidence(kind: .text, value: "Patient: Jane Doe"),
            ScanEvidence(kind: .text, value: "TWICE DAILY")
        ]

        XCTAssertEqual(ScanParser.parse(separateCaptures).directions, "")

        XCTAssertEqual(
            ScanParser.parse([
                ScanEvidence(
                    kind: .text,
                    value: "TAKE 1 TABLET\nBY MOUTH TWICE DAILY"
                )
            ]).directions,
            "TAKE 1 TABLET BY MOUTH TWICE DAILY"
        )
    }

    func testDispensingMarkersMatchWholeWords() {
        XCTAssertTrue(
            ScanParser.isTrustedDirections("Apply lotion to affected area twice daily")
        )
        XCTAssertTrue(
            ScanParser.isTrustedDirections("Use on exposed skin twice daily")
        )
        XCTAssertFalse(
            ScanParser.isTrustedDirections("Apply LOT to affected area twice daily")
        )
        XCTAssertFalse(
            ScanParser.isTrustedDirections("Take 1 tablet by mouth twice daily RPh")
        )
    }

    func testDirectionsNamingAPatientAreNotTrusted() {
        XCTAssertFalse(
            ScanParser.isTrustedDirections(
                "Take 1 tablet by mouth daily Patient: Jane Doe"
            )
        )
    }

    func testDanglingFrequencyWordIsNotTrustedButWrappedDailyRecoversSig() {
        XCTAssertFalse(
            ScanParser.isTrustedDirections("TAKE 1 TABLET BY MOUTH TWICE")
        )

        XCTAssertEqual(
            ScanParser.parse([
                ScanEvidence(
                    kind: .text,
                    value: "TAKE 1 TABLET BY MOUTH TWICE\nDAILY"
                )
            ]).directions,
            "TAKE 1 TABLET BY MOUTH TWICE DAILY"
        )

        XCTAssertTrue(
            ScanParser.isTrustedDirections("Take 1 tablet by mouth twice daily")
        )
    }

    func testCommaGroupedStrengthsAreCanonicalizedWithoutDroppingDigits() {
        XCTAssertEqual(ScanParser.normalizedStrength("1,000 IU"), "1000 IU")
        XCTAssertEqual(
            ScanParser.parse([
                ScanEvidence(kind: .text, value: "VITAMIN D3 1,000 IU")
            ]).strength,
            "1000 IU"
        )
        XCTAssertEqual(ScanParser.normalizedStrength("5,000 units"), "5000 units")
    }

    func testNameResiduePreservesAlphanumericNameTokensAndDropsTrailingImprint() {
        XCTAssertEqual(
            ScanParser.parse([
                ScanEvidence(kind: .text, value: "VITAMIN B12 1000 MCG")
            ]).name,
            "Vitamin B12"
        )
        XCTAssertEqual(
            ScanParser.parse([
                ScanEvidence(kind: .text, value: "SERTRALINE HCL 50MG G1")
            ]).name,
            "Sertraline HCl"
        )
    }

    func testDirectionsGateAllowsCompleteBottleSigsButRejectsBottleOCRGarbage() {
        let trustedValues = [
            "TAKE 1 TABLET BY MOUTH BID",
            "1 TABLET PO BID",
            "INHALE 2 PUFFS Q4H PRN WHEEZING",
            "TAKE 1 TABLET WITH FOOD",
            "TAKE 1 TABLET FOR 7 DAYS",
            "SWISH AND SWALLOW 15 ML BY MOUTH 4 TIMES DAILY",
            "1/2 TABLET PO DAILY",
            "2.5 ML PO BID",
            "1 TO 2 TABLETS PO Q6H",
            "1 TAB PO BID",
            "CHILDREN: 5 ML BY MOUTH TWICE DAILY"
        ]
        for value in trustedValues {
            XCTAssertTrue(ScanParser.isTrustedDirections(value), value)
        }

        let rejectedValues = [
            "is Filled: 8/13/2026 RPh: Mg by mouth 1 time each chew.",
            "- capsule by mouth 2 tim agNe 8.5 mg total twice da",
            "like 2 tablets by mouth rednesdays, and fridays",
            "TAKE 1 TABLET BY MOUTH TWICE"
        ]
        for value in rejectedValues {
            XCTAssertFalse(ScanParser.isTrustedDirections(value), value)
        }
    }

    func testAddressAndPersonLinesCannotBecomeMedicationNames() {
        let addressOrPersonLines = [
            "300 LONGWOOD AVENUE",
            "BOSTON MA 02115",
            "41 MAPLE TERRACE",
            "CHRISTOFORAKIS, LUKAS",
            "BOSTON CHILDREN'S HOSPITAL",
            "1200 MAIN ST"
        ]
        for value in addressOrPersonLines {
            XCTAssertTrue(ScanParser.isAddressOrPersonName(value), value)
        }

        let medicationLines = [
            "SERTRALINE HCL",
            "METOPROLOL SUCCINATE",
            "MYCOPHENOLATE MOFETIL",
            "SULFAMETHOXAZOLE / TRIMETHOPRIM"
        ]
        for value in medicationLines {
            XCTAssertFalse(ScanParser.isAddressOrPersonName(value), value)
        }
    }

    /// A photo yields one `ScanEvidence` per recognised line, sharing a capture and
    /// numbered top to bottom — not one evidence carrying newlines. Adjacency was
    /// being read off the evidence item, so on a real scan no two lines were ever
    /// adjacent and a wrapped sig never assembled. The live camera supplies neither
    /// a capture nor a line number, so reading order has to carry it there.
    func testWrappedSigAssemblesAcrossSeparateEvidenceLines() {
        let capture = UUID()
        let lines = [
            "SULFAMETHOXAZOLE/TRIMETHOPRIM 400-80 MG TAB",
            "TAKE 2 TABLETS BY MOUTH ON MONDAYS,",
            "WEDNESDAYS, AND FRIDAYS",
            "QTY: 64"
        ]
        let photo = lines.enumerated().map { index, value in
            ScanEvidence(
                kind: .text, value: value, confidence: 0.9,
                origin: .cameraCapture, captureID: capture, lineIndex: index
            )
        }
        XCTAssertEqual(
            ScanParser.parse(photo).directions,
            "TAKE 2 TABLETS BY MOUTH ON MONDAYS, WEDNESDAYS, AND FRIDAYS"
        )

        let live = lines.map { ScanEvidence(kind: .text, value: $0, confidence: 0.9, origin: .liveCamera) }
        XCTAssertEqual(
            ScanParser.parse(live).directions,
            "TAKE 2 TABLETS BY MOUTH ON MONDAYS, WEDNESDAYS, AND FRIDAYS"
        )
    }

    /// Two separate photos must never be joined into one instruction.
    func testWrappedSigDoesNotAssembleAcrossTwoCaptures() {
        let first = ScanEvidence(
            kind: .text, value: "TAKE 2 TABLETS BY MOUTH ON MONDAYS,",
            confidence: 0.9, origin: .cameraCapture, captureID: UUID(), lineIndex: 0
        )
        let second = ScanEvidence(
            kind: .text, value: "WEDNESDAYS, AND FRIDAYS",
            confidence: 0.9, origin: .cameraCapture, captureID: UUID(), lineIndex: 0
        )
        XCTAssertEqual(ScanParser.parse([first, second]).directions, "")
    }
}
