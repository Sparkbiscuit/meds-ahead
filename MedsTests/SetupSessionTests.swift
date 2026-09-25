import XCTest
@testable import Meds

/// Save and Scan Next: a bottle from the scanner returns to a new scanner,
/// and the bar under the camera says what has gone in so far.
final class SetupSessionTests: XCTestCase {
    private let british = Locale(identifier: "en_GB")

    func testTheTallyNamesBottlesAsTheyWereSaved() {
        var tally = SetupSessionTally()
        XCTAssertNil(tally.summary(locale: british), "nothing to show before the first bottle")

        tally.recordAdded("Furosemide")
        XCTAssertEqual(tally.summary(locale: british), "1 added: Furosemide")

        tally.recordAdded("Tacrolimus")
        XCTAssertEqual(tally.summary(locale: british), "2 added: Tacrolimus and Furosemide", "the newest first")

        tally.recordAdded("Prednisone ")
        XCTAssertEqual(tally.summary(locale: british), "3 added: Prednisone, Tacrolimus and Furosemide")
        XCTAssertEqual(tally.summary(locale: Locale(identifier: "en_US")), "3 added: Prednisone, Tacrolimus, and Furosemide",
                       "the locale's own list, serial comma and all")
    }

    func testBottlesAddedToATrackedMedicationAreSaidSo() {
        var tally = SetupSessionTally()
        tally.recordAddedTo("Furosemide")
        XCTAssertEqual(tally.summary(locale: british), "Added to Furosemide")

        tally.recordAdded("Tacrolimus")
        XCTAssertEqual(tally.summary(locale: british), "1 added: Tacrolimus · Added to Furosemide")
        tally.recordAddedTo("Furosemide")
        tally.recordAddedTo("Amlodipine")
        XCTAssertEqual(tally.summary(locale: british), "Added to Amlodipine and Furosemide · 1 added: Tacrolimus",
                       "whichever kind of bottle came last leads, and a medication is named once")
    }

    /// The bar has two lines. On a dozen-bottle day it is the oldest names
    /// that run off its end, never the bottle just saved or where it went.
    func testTheLatestBottleLeadsALongTally() {
        var tally = SetupSessionTally()
        for name in ["Tacrolimus", "Mycophenolate mofetil", "Prednisone", "Valganciclovir", "Pantoprazole", "Amlodipine"] {
            tally.recordAdded(name)
        }
        let six = tally.summary(locale: british) ?? ""
        XCTAssertTrue(six.hasPrefix("6 added: Amlodipine, Pantoprazole, Valganciclovir"), six)
        XCTAssertTrue(six.hasSuffix("Mycophenolate mofetil and Tacrolimus"), six)

        tally.recordAddedTo("Furosemide")
        XCTAssertTrue(tally.summary(locale: british)?.hasPrefix("Added to Furosemide · 6 added: Amlodipine") == true)
        tally.recordAdded("Sulfamethoxazole / Trimethoprim")
        XCTAssertTrue(tally.summary(locale: british)?.hasPrefix("7 added: Sulfamethoxazole / Trimethoprim, Amlodipine") == true)
        XCTAssertTrue(tally.summary(locale: british)?.hasSuffix(" · Added to Furosemide") == true)
    }

    private func scannedDraft(_ label: String) -> MedicationDraft {
        MedicationDraft(
            name: label.capitalized,
            source: .scanned,
            evidence: [ScanEvidence(kind: .text, value: label.uppercased(), confidence: 0.9)]
        )
    }

    /// Nothing the first bottle's scanner or review held survives into the
    /// second: the new path holds a scanner numbered past every earlier one,
    /// so SwiftUI builds it with empty evidence, and no draft at all.
    func testEachBottleGetsAScannerNoEarlierBottleUsed() {
        var navigation = AddMedicationFlow.Navigation()
        navigation.scan()
        XCTAssertEqual(navigation.path, [.scanner(0)])

        let first = scannedDraft("Tacrolimus 1 mg")
        navigation.path.append(.editor(first))
        XCTAssertEqual(navigation.finish(.added("Tacrolimus"), from: first), .scanNext)
        XCTAssertEqual(navigation.path, [.scanner(1)], "the review and its evidence are gone")
        XCTAssertEqual(navigation.tally.summary(locale: british), "1 added: Tacrolimus")

        let second = scannedDraft("Prednisone 5 mg")
        navigation.path.append(.editor(second))
        XCTAssertEqual(navigation.finish(.addedTo("Furosemide"), from: second), .scanNext)
        XCTAssertEqual(navigation.path, [.scanner(2)])
        XCTAssertEqual(navigation.tally.summary(locale: british), "Added to Furosemide · 1 added: Tacrolimus")

        // Back out to the menu and scan again: still a scanner never seen.
        navigation.path.removeAll()
        navigation.scan()
        XCTAssertEqual(navigation.path, [.scanner(3)])
    }

    /// A review thrown away, often a bottle found to be counted already,
    /// leaves a scanner no earlier bottle used, and adds nothing to the
    /// tally: the scanner it came from still holds the discarded label.
    func testDiscardingAReviewLeavesAScannerNoEarlierBottleUsed() {
        var navigation = AddMedicationFlow.Navigation()
        navigation.scan()
        let counted = scannedDraft("Tacrolimus 1 mg")
        navigation.path.append(.editor(counted))
        XCTAssertEqual(navigation.finish(.added("Tacrolimus"), from: counted), .scanNext)

        let alreadyCounted = scannedDraft("Tacrolimus 1 mg")
        navigation.path.append(.editor(alreadyCounted))
        navigation.discard()
        XCTAssertEqual(navigation.path, [.scanner(2)], "not the scanner that read the discarded label")
        XCTAssertEqual(navigation.tally.summary(locale: british), "1 added: Tacrolimus", "nothing was added")

        let next = scannedDraft("Prednisone 5 mg")
        navigation.path.append(.editor(next))
        XCTAssertEqual(navigation.finish(.added("Prednisone"), from: next), .scanNext)
        XCTAssertEqual(navigation.path, [.scanner(3)])
    }

    func testAnythingEnteredByHandStillClosesTheFlow() {
        var navigation = AddMedicationFlow.Navigation()
        let manual = MedicationDraft(name: "Furosemide", strength: "20 mg")
        navigation.path.append(.editor(manual))
        XCTAssertEqual(navigation.finish(.added("Furosemide"), from: manual), .close)
        XCTAssertEqual(navigation.finish(.addedTo("Furosemide"), from: manual), .close)
        XCTAssertTrue(navigation.tally.isEmpty, "a flow that closes has nothing to tally")
    }

#if DEBUG
    func testSimulatedScanArgumentsDescribeEachBottleInTurn() {
        let bottles = SimulatedScan.bottles(from: [
            "-ui-testing",
            "-simulate-scan-name", "Tacrolimus", "-simulate-scan-strength", "1 mg", "-simulate-scan-quantity", "60",
            "-simulate-scan-name", "Prednisone", "-simulate-scan-quantity", "30"
        ])
        XCTAssertEqual(bottles, [
            SimulatedScan.Bottle(name: "Tacrolimus", strength: "1 mg", quantity: 60),
            SimulatedScan.Bottle(name: "Prednisone", strength: "", quantity: 30)
        ])
        XCTAssertEqual(SimulatedScan.evidence(for: bottles[0]).map(\.value), ["TACROLIMUS 1 MG", "QTY: 60"])
    }
#endif
}
