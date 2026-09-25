import XCTest
@testable import Meds

/// Release is read off a label and a name the way a pharmacist reads it: from
/// the letters after the drug, never from a prescriber's title or an address.
final class ReleaseFormTests: XCTestCase {
    private let tacrolimus: Set<String> = ["tacrolimus"]

    func testTheDirectoryColumn() {
        XCTAssertEqual(ReleaseForm(directoryValue: "er"), .extended)
        XCTAssertEqual(ReleaseForm(directoryValue: "dr"), .delayed)
        XCTAssertEqual(ReleaseForm(directoryValue: ""), .immediate)
        XCTAssertNil(ReleaseForm(directoryValue: "xx"), "an unknown value claims nothing")
    }

    func testANamesReleaseLettersFollowTheDrug() {
        XCTAssertEqual(ReleaseForm.named(in: "Toprol XL"), .extended)
        XCTAssertEqual(ReleaseForm.named(in: "Astagraf XL"), .extended)
        XCTAssertEqual(ReleaseForm.named(in: "Envarsus XR"), .extended)
        XCTAssertEqual(ReleaseForm.named(in: "Cardizem CD"), .extended)
        XCTAssertEqual(ReleaseForm.named(in: "Tacrolimus ER"), .extended)
        XCTAssertEqual(ReleaseForm.named(in: "Aspirin EC"), .delayed)
        XCTAssertNil(ReleaseForm.named(in: "Prograf"))
        XCTAssertNil(ReleaseForm.named(in: "Nurtec ODT"), "orally disintegrating is not a release")
        XCTAssertNil(ReleaseForm.named(in: "Dr. Sheffield Anti Itch"), "a first word is never the release")
        XCTAssertNil(ReleaseForm.named(in: "La Roche Posay"))
        XCTAssertNil(ReleaseForm.named(in: "Wellbutrin XL DR"), "two releases is none")
    }

    func testALabelStatesItsReleaseOnTheLineThatNamesTheDrug() {
        func stated(_ text: String) -> Set<ReleaseForm> {
            ReleaseForm.evidence(in: text, namedBy: tacrolimus).stated
        }
        XCTAssertEqual(stated("TACROLIMUS XL 1 MG CAPSULE"), [.extended])
        XCTAssertEqual(stated("TACROLIMUS ER 1MG CAP"), [.extended])
        XCTAssertEqual(stated("TACROLIMUS EXTENDED-RELEASE CAPSULES"), [.extended])
        XCTAssertEqual(stated("TACROLIMUS\nEXTENDED-RELEASE CAPSULES 1 MG"), [.extended], "a manufacturer sets the phrase under the name")
        XCTAssertEqual(stated("TACROLIMUS 1 MG DR CAPSULE"), [.delayed])
        XCTAssertEqual(stated("TACROLIMUS IR 1 MG"), [.immediate])
        XCTAssertEqual(stated("TACROLIMUS 1 MG CAPSULE"), [])
    }

    /// Two-letter releases are also a prescriber's title, a state and a
    /// street, so only the drug's own line is read for them.
    func testLettersElsewhereOnTheLabelSayNothing() {
        let label = """
        RIVERSIDE PHARMACY, SHREVEPORT, LA 71101
        450 OAK DR
        DR. A. GREENE
        PRESCRIBER: DR JONES
        TACROLIMUS 1 MG CAPSULE
        TAKE 1 CAPSULE BY MOUTH TWICE DAILY
        """
        XCTAssertEqual(ReleaseForm.evidence(in: label, namedBy: tacrolimus).stated, [])
        XCTAssertEqual(ReleaseForm.evidence(in: "TACROLIMUS 1 MG CAPSULE   DR. A. GREENE", namedBy: tacrolimus).stated, [],
                       "a prescriber read onto the drug's line")
        XCTAssertEqual(ReleaseForm.evidence(in: "TACROLIMUS 1 MG CAPSULE DR JONES", namedBy: tacrolimus).stated, [])
        XCTAssertEqual(ReleaseForm.evidence(in: "MYCOPHENOLIC ACID DR 360 MG TABLET", namedBy: ["mycophenolic"]).stated, [.delayed])
        XCTAssertEqual(ReleaseForm.evidence(in: "OMEPRAZOLE DR CAPSULE", namedBy: ["omeprazole"]).stated, [.delayed])
    }

    /// "24 HR" is on Nexium 24HR and Allegra 24 Hour, which are not
    /// extended-release, as well as on products that are.
    func testAnHourCountOnlySuggestsExtendedRelease() {
        let evidence = ReleaseForm.evidence(in: "ZYRTEC 24 HR 10 MG TABLET", namedBy: ["zyrtec"])
        XCTAssertEqual(evidence.stated, [])
        XCTAssertEqual(evidence.suggested, [.extended])
        XCTAssertEqual(ReleaseForm.evidence(in: "NEXIUM 24HR 20 MG", namedBy: ["nexium"]).suggested, [.extended])
    }

    /// "Every 12 hours" is how immediate-release tacrolimus is taken. A
    /// dosing interval, on the drug's line or not, says nothing about release,
    /// and neither does a twelve-hour count.
    func testADosingIntervalIsNotARelease() {
        func suggested(_ text: String) -> Set<ReleaseForm> {
            ReleaseForm.evidence(in: text, namedBy: tacrolimus).suggested
        }
        XCTAssertEqual(suggested("TACROLIMUS 1 MG CAPSULE EVERY 12 HOURS"), [])
        XCTAssertEqual(suggested("TAKE 1 TACROLIMUS 1 MG CAPSULE BY MOUTH EVERY 12 HOURS"), [])
        XCTAssertEqual(suggested("TACROLIMUS 1 MG CAPSULE 12 HR"), [])
        XCTAssertEqual(suggested("TACROLIMUS 1 MG CAPSULE EVERY 24 HOURS"), [])
        XCTAssertEqual(suggested("TACROLIMUS 1 MG CAPSULE ONCE IN 24 HR"), [])
        XCTAssertEqual(suggested("TACROLIMUS 1 MG CAPSULE Q 24 HR"), [])
        XCTAssertEqual(suggested("TACROLIMUS 1 MG CAPSULE Q24H"), [])
        XCTAssertEqual(suggested("TACROLIMUS 24 HR 1 MG CAPSULE"), [.extended], "the product's own duration still counts")
        XCTAssertEqual(suggested("TACROLIMUS 24-HOUR 1 MG CAPSULE"), [.extended])
    }

    /// A narrow label wraps the drug's line, and the release letters land on
    /// the next one. They count there when that line is the rest of the
    /// description; DR, EC and LA never do, because a prescriber, a
    /// manufacturer and an address are what follow a drug's line.
    func testReleaseLettersWrappedOntoTheNextLine() {
        func stated(_ text: String) -> Set<ReleaseForm> {
            ReleaseForm.evidence(in: text, namedBy: tacrolimus).stated
        }
        XCTAssertEqual(stated("TACROLIMUS\nXL 1 MG CAPSULE"), [.extended])
        XCTAssertEqual(stated("TACROLIMUS 1 MG\nER CAPSULE"), [.extended])
        XCTAssertEqual(stated("TACROLIMUS 1 MG CAPSULE\nXR"), [.extended])
        XCTAssertEqual(ReleaseForm.evidence(in: "TACROLIMUS\nXL 1 MG CAPSULE", namedBy: tacrolimus).printedLetters(for: .extended), "XL")

        XCTAssertEqual(stated("TACROLIMUS 1 MG CAPSULE\nSR PHARMACY SERVICES"), [], "not the rest of the description")
        XCTAssertEqual(stated("TACROLIMUS 1 MG\nDR CAPSULE"), [])
        XCTAssertEqual(stated("TACROLIMUS 1 MG CAPSULE\nDR. A. GREENE"), [])
        XCTAssertEqual(stated("TACROLIMUS 1 MG CAPSULE\nSHREVEPORT, LA 71101"), [])
        XCTAssertEqual(stated("RIVERSIDE PHARMACY\nXL 1 MG CAPSULE\nTACROLIMUS"), [], "only the line after the drug's")
    }

    func testANameKeepsTheLabelsOwnLetters() {
        let evidence = ReleaseForm.evidence(in: "DILTIAZEM CD 120 MG CAPSULE", namedBy: ["diltiazem"])
        XCTAssertEqual(evidence.modified, .extended)
        XCTAssertEqual(evidence.printedLetters(for: .extended), "CD")
        XCTAssertEqual(ReleaseForm.evidence(in: "TACROLIMUS EXTENDED-RELEASE", namedBy: tacrolimus).printedLetters(for: .extended), "ER")
        XCTAssertEqual(ReleaseForm.name("Diltiazem", keeping: "CD"), "Diltiazem CD")
        XCTAssertEqual(ReleaseForm.name("Tacrolimus XL", keeping: "ER"), "Tacrolimus XL", "a name that already says it is left alone")
    }
}
