import XCTest
@testable import Meds

final class LabelScanPipelineTests: XCTestCase {
    func testLatinPolicyAcceptsEnglishSpanishAndFrench() {
        XCTAssertTrue(LabelTextPolicy.isAllowedLine("Take one tablet daily"))
        XCTAssertTrue(LabelTextPolicy.isAllowedLine("Melatonina rápida 5 mg"))
        XCTAssertTrue(LabelTextPolicy.isAllowedLine("Comprimé à libération prolongée"))
    }

    func testLatinPolicyRejectsOtherScriptsAndMixedConfusables() {
        XCTAssertFalse(LabelTextPolicy.isAllowedLine("Мелатонин"))
        XCTAssertFalse(LabelTextPolicy.isAllowedLine("褪黑素"))
        XCTAssertFalse(LabelTextPolicy.isAllowedLine("Mеlatonin")) // Cyrillic е
        XCTAssertFalse(LabelTextPolicy.isAllowedLine("μελατονίνη"))
    }

    func testSanitizerRetainsLatinLinesAndDropsNonLatinLines() {
        XCTAssertEqual(
            LabelTextPolicy.sanitized("Melatonin\n褪黑素\n5 mg"),
            "Melatonin\n5 mg"
        )
    }

    func testTransientObservationDisappearsWithoutPromotion() {
        var tracker = LiveEvidenceTracker<String>(textStabilityInterval: 0.4)
        _ = tracker.update([observation(id: "a", value: "Carpet fibers")], at: 0)
        let update = tracker.update([], at: 0.2)

        XCTAssertTrue(update.evidence.isEmpty)
        XCTAssertFalse(update.promotedNewEvidence)
    }

    func testStableObservationPromotesAfterRequiredInterval() {
        var tracker = LiveEvidenceTracker<String>(textStabilityInterval: 0.4)
        _ = tracker.update([observation(id: "a", value: "Melatonin")], at: 0)
        let update = tracker.promote(at: 0.41)

        XCTAssertEqual(update.evidence.map(\.value), ["Melatonin"])
        XCTAssertTrue(update.promotedNewEvidence)
    }

    func testImprovedEquivalentReadingReplacesFragment() {
        var tracker = LiveEvidenceTracker<String>(textStabilityInterval: 0.4)
        _ = tracker.update([observation(id: "a", value: "elatonin")], at: 0)
        _ = tracker.update([observation(id: "a", value: "Melatonin")], at: 0.2)
        let update = tracker.promote(at: 0.41)

        XCTAssertEqual(update.evidence.map(\.value), ["Melatonin"])
    }

    func testDifferentReadingForSameItemRestartsStabilityWindow() {
        var tracker = LiveEvidenceTracker<String>(textStabilityInterval: 0.4)
        _ = tracker.update([observation(id: "a", value: "Patient Name")], at: 0)
        _ = tracker.update([observation(id: "a", value: "Melatonin")], at: 0.3)

        XCTAssertTrue(tracker.promote(at: 0.5).evidence.isEmpty)
        XCTAssertEqual(tracker.promote(at: 0.71).evidence.map(\.value), ["Melatonin"])
    }

    func testPromotedEvidenceSurvivesBottleRotation() {
        var tracker = LiveEvidenceTracker<String>(textStabilityInterval: 0.4)
        _ = tracker.update([observation(id: "a", value: "Melatonin")], at: 0)
        _ = tracker.promote(at: 0.5)
        let update = tracker.update([], at: 0.6)

        XCTAssertEqual(update.evidence.map(\.value), ["Melatonin"])
    }

    func testAspectFillCropMapsVisibleFrameIntoSourceImage() throws {
        let mapped = try XCTUnwrap(AspectFillCropMapper.sourceRect(
            imageSize: CGSize(width: 4000, height: 3000),
            displayedIn: CGSize(width: 300, height: 600),
            visibleRect: CGRect(x: 24, y: 64, width: 252, height: 472)
        ))

        XCTAssertEqual(mapped.origin.x, 1370, accuracy: 1)
        XCTAssertEqual(mapped.origin.y, 320, accuracy: 1)
        XCTAssertEqual(mapped.width, 1260, accuracy: 1)
        XCTAssertEqual(mapped.height, 2360, accuracy: 1)
    }

    private func observation(id: String, value: String) -> LiveEvidenceObservation<String> {
        LiveEvidenceObservation(
            id: id,
            evidence: ScanEvidence(
                kind: .text,
                value: value,
                confidence: 0.12,
                origin: .liveCamera
            )
        )
    }
}
