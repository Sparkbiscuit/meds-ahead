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

    func testRepairsDroppedLeadingCharacter() {
        XCTAssertEqual(
            MedicationVocabulary.uniqueMatch(for: "elatonin", among: sampleNames),
            "melatonin"
        )
    }

    func testCompletesUniqueCurvedBottleEdge() {
        XCTAssertEqual(
            MedicationVocabulary.uniqueMatch(
                for: "AMPHETAMINE - DEXTROAMPHET",
                among: sampleNames
            ),
            "amphetamine - dextroamphetamine"
        )
    }

    func testRepairsUserReportedCompoundEdgeFragment() {
        XCTAssertEqual(
            MedicationVocabulary.uniqueMatch(
                for: "amphetamine-dextroan",
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

    func testDoesNotSubstituteBrandForPrintedGeneric() {
        XCTAssertNotEqual(
            MedicationVocabulary.uniqueMatch(
                for: "AMPHETAMINE - DEXTROAMPHET",
                among: sampleNames
            ),
            "Adderall"
        )
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
}
