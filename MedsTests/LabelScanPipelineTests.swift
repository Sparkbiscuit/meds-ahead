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

    /// A better live reading of a captured line takes the captured line's place
    /// in its line order, or the adjacency a wrapped sig depends on is lost.
    func testABetterLiveReadingKeepsTheCapturedLinesPosition() {
        let capture = UUID()
        let captured = ScanEvidence(kind: .text, value: "TAKE 1 TABLET BY MOUTH", confidence: 0.4,
                                    origin: .cameraCapture, captureID: capture, lineIndex: 3)
        let live = ScanEvidence(kind: .text, value: "TAKE 1 TABLET BY MOUTH", confidence: 0.95, origin: .liveCamera)

        let merged = ScanEvidenceQuality.mergingBest(existing: [captured], additions: [live])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].confidence, 0.95, "the better reading wins")
        XCTAssertEqual(merged[0].captureID, capture)
        XCTAssertEqual(merged[0].lineIndex, 3)

        // The other way round, a captured line that replaces a live one already has a position.
        let reversed = ScanEvidenceQuality.mergingBest(existing: [live], additions: [captured])
        XCTAssertEqual(reversed[0].confidence, 0.95)
        XCTAssertEqual(reversed[0].lineIndex, 3)
    }

    /// Two readings of one code line share their letters and differ in their
    /// digits, which the merge took for one line read twice, keeping whichever
    /// scored higher: a product chosen by OCR confidence. Both go forward now,
    /// and the identification gate asks the label.
    func testTwoReadingsOfACodeLineWithDifferentCodesAreBothKept() {
        let capture = UUID()
        let first = ScanEvidence(kind: .text, value: "MFR BIOGEN NDC 54405-005-02", confidence: 1,
                                 origin: .cameraCapture, captureID: capture, lineIndex: 3)
        let second = ScanEvidence(kind: .text, value: "MFR BIOGEN NDC 64406-006-02", confidence: 1,
                                  origin: .cameraCapture, captureID: capture, lineIndex: 4)
        XCTAssertEqual(ScanEvidenceQuality.mergingBest(existing: [], additions: [first, second]).map(\.value), [first.value, second.value])

        let again = ScanEvidence(kind: .text, value: "MFR: BIOGEN NDC 64406-006-02", confidence: 1, origin: .liveCamera)
        XCTAssertEqual(ScanEvidenceQuality.mergingBest(existing: [second], additions: [again]).count, 1, "the same code read twice is one line")
    }

    /// The capture leads the merge so the cap cuts live extras, never the capture.
    func testTheCaptureSurvivesTheEvidenceCapAheadOfLiveItems() {
        // Lines that differ only by a digit read as one line to the merge, so each
        // gets letters of its own.
        func word(_ index: Int) -> String {
            let letters = Array("QWERTYUIOP")
            let spelled = String(index).compactMap { $0.wholeNumberValue.map { letters[$0] } }
            return String(repeating: String(spelled), count: 3)
        }
        let capture = UUID()
        let captured = (0..<40).map { index in
            ScanEvidence(kind: .text, value: "CAPTURED \(word(index))", confidence: 0.9,
                         origin: .cameraCapture, captureID: capture, lineIndex: index)
        }
        let live = (0..<200).map { index in
            ScanEvidence(kind: .text, value: "LIVE \(word(index))", confidence: 0.9, origin: .liveCamera)
        }

        let merged = ScanEvidenceQuality.mergingBest(existing: captured, additions: live)

        XCTAssertEqual(merged.count, ScanEvidenceQuality.evidenceLimit)
        XCTAssertEqual(merged.filter { $0.captureID == capture }.count, 40)
    }

    /// The zoomed second pass reads a crop and reports boxes inside it; those have
    /// to land back on the whole image or the line order is wrong.
    func testASecondPassBoxMapsBackOntoTheWholeImage() {
        let imageSize = CGSize(width: 3000, height: 4000)
        // A line in the lower-left quarter of the image, in Vision's bottom-left terms.
        let line = CGRect(x: 0.10, y: 0.20, width: 0.30, height: 0.01)
        let pixels = StillImageRecognizer.pixelRect(fromNormalized: line, imageSize: imageSize)
        XCTAssertEqual(pixels.minX, 300, accuracy: 0.5)
        XCTAssertEqual(pixels.minY, 4000 - 0.21 * 4000, accuracy: 0.5, "top of the line, from the top of the image")
        XCTAssertEqual(pixels.height, 40, accuracy: 0.5)

        // Crop that region with padding, then a box Vision reports inside the crop.
        let crop = pixels.insetBy(dx: -100, dy: -30)
        let insideCrop = CGRect(
            x: 100 / crop.width,
            y: 30 / crop.height,
            width: pixels.width / crop.width,
            height: pixels.height / crop.height
        )
        let mapped = StillImageRecognizer.fullImageBox(fromCropBox: insideCrop, cropRect: crop, imageSize: imageSize)
        XCTAssertEqual(mapped.minX, line.minX, accuracy: 0.001)
        XCTAssertEqual(mapped.minY, line.minY, accuracy: 0.001)
        XCTAssertEqual(mapped.width, line.width, accuracy: 0.001)
        XCTAssertEqual(mapped.height, line.height, accuracy: 0.001)
    }

    func testLinesWorthASecondLookAreTheCaptionAndCodeShapedDigits() {
        XCTAssertTrue(StillImageRecognizer.looksLikeCodeFragment("MFR: TEVA   NDC"))
        XCTAssertTrue(StillImageRecognizer.looksLikeCodeFragment("N0C 0093-1039-01"), "the caption as small print reads it")
        XCTAssertTrue(StillImageRecognizer.looksLikeCodeFragment("0093-1039"))
        XCTAssertTrue(StillImageRecognizer.looksLikeCodeFragment("00093103901"))
        XCTAssertFalse(StillImageRecognizer.looksLikeCodeFragment("TAKE 1 TABLET BY MOUTH DAILY"))
        XCTAssertFalse(StillImageRecognizer.looksLikeCodeFragment("RX# 8842197"))
        XCTAssertFalse(StillImageRecognizer.looksLikeCodeFragment("413-555-0123"))
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
