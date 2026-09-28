import XCTest
@testable import Meds

final class MedicationVocabularyTests: XCTestCase {
    private let sampleNames = [
        "Adderall",
        "amphetamine - dextroamphetamine",
        "dimethyl fumarate",
        "furosemide",
        "melatonin",
        "meloxicam"
    ]

    func testCompletesUniqueCurvedBottleEdge() {
        XCTAssertEqual(
            MedicationVocabulary.uniqueMatch(
                for: "AMPHETAMINE - DEXTROAMPHET",
                among: sampleNames
            ),
            "amphetamine - dextroamphetamine"
        )
    }

    func testCompoundEdgeRepairMustRemainUnique() {
        XCTAssertNil(
            MedicationVocabulary.uniqueMatch(
                for: "alpha-betama",
                among: ["alpha-betamax", "alpha-betamay"]
            )
        )
    }

    func testDoesNotCompleteAmbiguousShortFragment() {
        XCTAssertNil(MedicationVocabulary.uniqueMatch(for: "melat", among: sampleNames))
    }

    func testBundledVocabularyContainsReleaseExamples() {
        XCTAssertEqual(MedicationVocabulary.uniqueMatch(for: "elatonin"), "melatonin")
        XCTAssertEqual(
            MedicationVocabulary.uniqueMatch(for: "AMPHETAMINE - DEXTROAMPHET"),
            "amphetamine - dextroamphetamine"
        )
        XCTAssertEqual(
            MedicationVocabulary.uniqueMatch(for: "amphetamine-dextroan"),
            "amphetamine - dextroamphetamine"
        )
    }

    func testDetectsClippedNamesInsideLongerVocabularyEntries() {
        for fragment in ["Rolol Succin", "Toprolol Succina", "Oprolol Succinate"] {
            XCTAssertTrue(
                MedicationVocabulary.isFragmentOfLongerName(fragment),
                "Expected clipped reading to be recognized: \(fragment)"
            )
        }
    }

    func testDoesNotCallRealEntriesOrUnlistedWordingFragments() {
        for name in ["metoprolol", "tacrolimus", "sertraline", "prednisone"] {
            XCTAssertFalse(
                MedicationVocabulary.isFragmentOfLongerName(name),
                "A vocabulary entry is a medication name, not a clipped fragment: \(name)"
            )
        }

        XCTAssertFalse(MedicationVocabulary.isFragmentOfLongerName("rol"))
        XCTAssertFalse(MedicationVocabulary.isFragmentOfLongerName("Amphetamine salt combo"))
    }

    func testMatchesExactCoreAfterRemovingTrailingNoise() {
        XCTAssertEqual(
            MedicationVocabulary.matchIgnoringTrailingNoise(
                for: "Metoprolol Succinate ER GG 263"
            ),
            "metoprolol succinate"
        )
        XCTAssertNil(
            MedicationVocabulary.matchIgnoringTrailingNoise(for: "Metoprolol Succinate")
        )
        XCTAssertNil(
            MedicationVocabulary.matchIgnoringTrailingNoise(for: "Metoprolol Succ ER")
        )
    }

    func testExactMatchSetsAsideInterchangeableHydrochlorideSalt() {
        XCTAssertEqual(
            MedicationVocabulary.exactMatch(for: "SERTRALINE HCL"),
            "sertraline"
        )
        XCTAssertEqual(
            MedicationVocabulary.exactMatch(for: "VALGANCICLOVIR HCL"),
            "valganciclovir"
        )
    }

    func testExactMatchPreservesDistinguishingMetoprololSalts() {
        let expectedMatches = [
            ("METOPROLOL SUCCINATE", "metoprolol succinate"),
            ("METOPROLOL TARTRATE", "metoprolol tartrate")
        ]

        for (reading, expected) in expectedMatches {
            let match = MedicationVocabulary.exactMatch(for: reading)
            XCTAssertEqual(match, expected, reading)
            XCTAssertNotEqual(match, "metoprolol", reading)
        }
    }

    func testExactMatchRejectsNameShapedNearMisses() {
        for reading in ["SERTRALIN", "EDRONATE"] {
            XCTAssertNil(MedicationVocabulary.exactMatch(for: reading), reading)
        }
    }

    func testSuffixCompletionRequiresTheDistinguishingBeginning() {
        XCTAssertNil(MedicationVocabulary.uniqueMatch(for: "edronate"))
        XCTAssertEqual(
            MedicationVocabulary.uniqueMatch(for: "isedronate"),
            "risedronate"
        )
    }

    func testPrefixCompletionStillResolvesVisibleLeadingFragments() {
        XCTAssertEqual(
            MedicationVocabulary.uniqueMatch(for: "METOPROLOL SUCC"),
            "metoprolol succinate"
        )
        XCTAssertEqual(
            MedicationVocabulary.uniqueMatch(for: "MYCOPHENOLATE MOF"),
            "mycophenolate mofetil"
        )
    }

    /// A labeler lists a stimulant under all four of its salts; the vocabulary
    /// also has the two-word name everyone uses, and that is the one to show.
    func testACombinationResolvesToItsShortestName() {
        XCTAssertEqual(
            MedicationVocabulary.shortestName(forCombination: "Dextroamphetamine Saccharate, Amphetamine Aspartate, Dextroamphetamine Sulfate, Amphetamine Sulfate"),
            "amphetamine - dextroamphetamine"
        )
        XCTAssertEqual(
            MedicationVocabulary.shortestName(forCombination: "Dextroamphetamine Sulfate, Dextroamphetamine Saccharate, Amphetamine Sulfate and Amphetamine Aspartate"),
            "amphetamine - dextroamphetamine",
            "order does not matter"
        )
        XCTAssertEqual(MedicationVocabulary.shortestName(forCombination: "sulfamethoxazole and Trimethoprim"), "sulfamethoxazole / trimethoprim")
        XCTAssertEqual(MedicationVocabulary.shortestName(forCombination: "hydrochlorothiazide and metoprolol"), "hydrochlorothiazide / metoprolol")
        // Succinate and tartrate are different products; a listing that names one
        // must not be shown under a name that drops it.
        XCTAssertNil(MedicationVocabulary.shortestName(forCombination: "hydrochlorothiazide and metoprolol tartrate"))
        XCTAssertNil(MedicationVocabulary.shortestName(forCombination: "sertraline hydrochloride"), "single ingredients keep their salt-aware paths")
        XCTAssertNil(MedicationVocabulary.shortestName(forCombination: "unobtainium and dilithium"))
    }
}
