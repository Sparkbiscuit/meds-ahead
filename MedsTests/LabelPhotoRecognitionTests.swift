import UIKit
import XCTest
@testable import Meds

/// Pushes a rendered pharmacy-style label through the real Vision OCR,
/// sanitation, and parsing pipeline — the same path a chosen photo takes.
/// Every other scan test feeds the parser hand-written strings; this one
/// catches regressions between recognition and parsing, where the scanner
/// actually fails in the field.
final class LabelPhotoRecognitionTests: XCTestCase {
    func testRenderedPharmacyLabelPhotoFillsTheDraft() async throws {
        let image = renderedLabel(lines: [
            Line("SPRINGFIELD PHARMACY #2214", size: 44, bold: true),
            Line("450 ELM STREET, SPRINGFIELD MA", size: 34),
            Line("RX# 4402917", size: 40, bold: true),
            Line("PEMBERTON, ELLIS", size: 40),
            Line("TACROLIMUS 1 MG CAPSULE", size: 52, bold: true),
            Line("TAKE 1 CAPSULE BY MOUTH TWICE DAILY", size: 42),
            Line("QTY: 60", size: 44, bold: true),
            Line("2 REFILLS REMAINING", size: 40),
            Line("DISCARD AFTER 07/14/26", size: 40, bold: true),
            Line("LOT: TK4471", size: 36)
        ])
        let data = try XCTUnwrap(image.pngData())

        let evidence = try await StillImageRecognizer.recognize(data: data, origin: .photoLibrary)
        let draft = MedicationLabelInterpreter.offlineDraft(evidence)

        XCTAssertEqual(draft.name, "Tacrolimus")
        XCTAssertEqual(draft.strength.lowercased(), "1 mg")
        XCTAssertEqual(draft.form, .capsule)
        XCTAssertEqual(draft.directions.uppercased(), "TAKE 1 CAPSULE BY MOUTH TWICE DAILY")
        XCTAssertEqual(draft.currentSupply, 60)
        XCTAssertEqual(draft.refillsRemaining, 2)
        XCTAssertEqual(draft.lotNumber, "TK4471")
        let expiration = try XCTUnwrap(draft.expirationDate)
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: expiration)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 7)
        XCTAssertEqual(parts.day, 14)
    }

    /// The OTC shape: no printed QTY, a directions line that fits the bare
    /// "(N) tablets" pattern, and a named-month best-by date. The supply must
    /// come from the package count, never the directions.
    func testRenderedOTCLabelPhotoUsesPackageCountNotDirections() async throws {
        let image = renderedLabel(lines: [
            Line("Melatonin", size: 56, bold: true),
            Line("5 mg", size: 44, bold: true),
            Line("Take 2 tablets daily at bedtime", size: 38),
            Line("120 TABLETS", size: 42, bold: true),
            Line("BEST BY JAN 26", size: 36)
        ])
        let data = try XCTUnwrap(image.pngData())

        let evidence = try await StillImageRecognizer.recognize(data: data, origin: .photoLibrary)
        let draft = MedicationLabelInterpreter.offlineDraft(evidence)

        XCTAssertEqual(draft.name, "Melatonin")
        XCTAssertEqual(draft.strength.lowercased(), "5 mg")
        XCTAssertEqual(draft.currentSupply, 120, "package count must win over the dose in the directions")
        XCTAssertEqual(draft.directions.lowercased(), "take 2 tablets daily at bedtime")
        let expiration = try XCTUnwrap(draft.expirationDate)
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: expiration)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 1)
        XCTAssertEqual(parts.day, 31)
    }

    /// The shape a pharmacy label often takes: the product line in bold, the
    /// NDC in the small print underneath it. The code is real (Tecfidera), the
    /// pharmacy is not. The name and brand must come from the directory, which
    /// is what makes the bottle's brand appear without the label ever printing it.
    func testRenderedLabelWithASmallPrintedNDCResolvesTheExactProduct() async throws {
        let draft = try await draft(forSmallPrintNDCSize: 24)

        XCTAssertEqual(draft.nameProvenance, .ndc, "evidence: \(draft.evidence.map(\.value))")
        XCTAssertEqual(draft.name, "Dimethyl fumarate")
        XCTAssertEqual(draft.brandName, "Tecfidera")
        XCTAssertEqual(draft.strength, "240 mg")
        XCTAssertEqual(draft.form, .capsule)
        XCTAssertEqual(draft.productIdentifier, "64406-0006-02")
        XCTAssertEqual(draft.productIdentifierType, "NDC")
        XCTAssertEqual(draft.currentSupply, 60)
    }

    /// The same label with the NDC printed at the smallest size a pharmacy uses,
    /// about one percent of the frame. This is the case Nick was worried about.
    func testRenderedLabelWithTheSmallestPrintedNDCStillResolves() async throws {
        let draft = try await draft(forSmallPrintNDCSize: 16)

        XCTAssertEqual(draft.nameProvenance, .ndc, "evidence: \(draft.evidence.map(\.value))")
        XCTAssertEqual(draft.productIdentifier, "64406-0006-02")
    }

    /// A photo's worth of pixels, with the code at the size a phone camera
    /// actually delivers it from a bottle at reading distance: a few dozen pixels
    /// tall in a frame thousands tall. The first pass works the whole frame at a
    /// bounded resolution, so this is the case the zoomed second pass exists for.
    func testACameraSizedFrameWithTheCodeInTheSmallestPrintResolves() async throws {
        let image = renderedLabel(canvas: CGSize(width: 2400, height: 3200), pixelScale: 1, lines: [
            Line("SPRINGFIELD PHARMACY #2214", size: 88, bold: true),
            Line("450 ELM STREET, SPRINGFIELD MA", size: 68),
            Line("RX# 4402917", size: 80, bold: true),
            Line("PEMBERTON, ELLIS", size: 80),
            Line("DIMETHYL FUMARATE 240 MG DR CAPSULE", size: 100, bold: true),
            Line("MFR: BIOGEN   NDC 64406-006-02", size: 26),
            Line("TAKE 1 CAPSULE BY MOUTH TWICE DAILY", size: 84),
            Line("QTY: 60", size: 88, bold: true),
            Line("2 REFILLS REMAINING", size: 80),
            Line("DISCARD AFTER 07/14/26", size: 80, bold: true)
        ])
        let result = try await StillImageRecognizer.recognizeWithReport(image: image, origin: .photoLibrary)
        let draft = MedicationLabelInterpreter.offlineDraft(result.evidence)
        print("Camera-sized frame: \(result.report)")

        XCTAssertEqual(draft.nameProvenance, .ndc, "\(result.report); evidence: \(draft.evidence.map(\.value))")
        XCTAssertEqual(draft.productIdentifier, "64406-0006-02")
        XCTAssertEqual(draft.brandName, "Tecfidera")
        XCTAssertEqual(draft.currentSupply, 60, "the rest of the label still reads")
    }

    /// The same frame with the code at fourteen pixels, under half a percent of
    /// the frame: whichever pass reads it, the product must come out exact.
    func testACameraSizedFrameWithTheCodeUnderHalfAPercentResolves() async throws {
        let image = renderedLabel(canvas: CGSize(width: 2400, height: 3200), pixelScale: 1, lines: [
            Line("SPRINGFIELD PHARMACY #2214", size: 88, bold: true),
            Line("RX# 4402917", size: 80, bold: true),
            Line("DIMETHYL FUMARATE 240 MG DR CAPSULE", size: 100, bold: true),
            Line("MFR: BIOGEN   NDC 64406-006-02", size: 14),
            Line("TAKE 1 CAPSULE BY MOUTH TWICE DAILY", size: 84),
            Line("QTY: 60", size: 88, bold: true)
        ])
        let result = try await StillImageRecognizer.recognizeWithReport(image: image, origin: .photoLibrary)
        let draft = MedicationLabelInterpreter.offlineDraft(result.evidence)
        print("Half-percent frame: \(result.report)")

        XCTAssertEqual(draft.nameProvenance, .ndc, "\(result.report); evidence: \(draft.evidence.map(\.value))")
        XCTAssertEqual(draft.productIdentifier, "64406-0006-02")
    }

    /// The zoomed second pass on its own: a code line in the smallest print, cut
    /// out around a box the first pass might have drawn, scaled up and read
    /// without language correction, with its box mapped back onto the frame.
    func testTheZoomedSecondPassReadsTheSmallestPrintAndMapsItBack() throws {
        let canvas = CGSize(width: 2400, height: 3200)
        let text = "MFR: BIOGEN   NDC 64406-006-02"
        let font = UIFont.systemFont(ofSize: 12)
        let origin = CGPoint(x: 300, y: 2100)
        let image = renderedText(text, font: font, at: origin, canvas: canvas)
        let cgImage = try XCTUnwrap(image.cgImage)
        let textSize = NSString(string: text).size(withAttributes: [.font: font])
        // Vision's box: normalized, origin bottom-left. A deliberately loose box,
        // the way a first pass draws one around print it could not read.
        let box = CGRect(
            x: (origin.x + 20) / canvas.width,
            y: 1 - (origin.y + textSize.height) / canvas.height,
            width: (textSize.width - 40) / canvas.width,
            height: textSize.height / canvas.height
        )

        let readings = StillImageRecognizer.zoomedCodeReadings(around: box, in: cgImage)

        let reading = try XCTUnwrap(readings.first, "the zoomed pass read nothing")
        XCTAssertEqual(NationalDrugCode.readings(inLabelText: reading.text).first?.candidates.map(\.hyphenated), ["64406-0006-02"], reading.text)
        XCTAssertEqual(reading.box.midY, box.midY, accuracy: 0.01, "the line must land back where it was printed")
        XCTAssertEqual(reading.box.midX, box.midX, accuracy: 0.03)
    }

    /// The tiled fallback on its own: the same small line somewhere in a
    /// camera-sized frame, found by reading the frame in full-resolution tiles.
    func testTheTiledFallbackFindsTheSmallestPrintAnywhereInTheFrame() throws {
        let canvas = CGSize(width: 2400, height: 3200)
        let font = UIFont.systemFont(ofSize: 12)
        let origin = CGPoint(x: 1500, y: 2900)
        let image = renderedText("NDC 64406-006-02", font: font, at: origin, canvas: canvas)
        let cgImage = try XCTUnwrap(image.cgImage)

        let readings = StillImageRecognizer.tiledCodeReadings(in: cgImage)

        let reading = try XCTUnwrap(readings.first, "the tiled pass read nothing")
        XCTAssertEqual(NationalDrugCode.readings(inLabelText: reading.text).first?.candidates.map(\.hyphenated), ["64406-0006-02"], reading.text)
        XCTAssertEqual(reading.box.midY, 1 - (origin.y + 7) / canvas.height, accuracy: 0.01)
        XCTAssertGreaterThan(reading.box.midX, 0.6, "printed in the right-hand half")
    }

    /// The same frame with the code split around its hyphen onto a second line,
    /// which is what a curved bottle does to it.
    func testACodeWrappedOntoTwoLinesStillResolves() async throws {
        let image = renderedLabel(canvas: CGSize(width: 2400, height: 3200), pixelScale: 1, lines: [
            Line("DIMETHYL FUMARATE 240 MG DR CAPSULE", size: 100, bold: true),
            Line("MFR: BIOGEN  NDC 64406-", size: 30),
            Line("006-02", size: 30),
            Line("TAKE 1 CAPSULE BY MOUTH TWICE DAILY", size: 84),
            Line("QTY: 60", size: 88, bold: true)
        ])
        let result = try await StillImageRecognizer.recognizeWithReport(image: image, origin: .photoLibrary)
        let draft = MedicationLabelInterpreter.offlineDraft(result.evidence)
        print("Wrapped code: \(result.report)")

        XCTAssertEqual(draft.nameProvenance, .ndc, "\(result.report); evidence: \(draft.evidence.map(\.value))")
        XCTAssertEqual(draft.productIdentifier, "64406-0006-02")
    }

    private func draft(forSmallPrintNDCSize size: CGFloat) async throws -> MedicationDraft {
        let image = renderedLabel(lines: [
            Line("SPRINGFIELD PHARMACY #2214", size: 44, bold: true),
            Line("450 ELM STREET, SPRINGFIELD MA", size: 34),
            Line("RX# 4402917", size: 40, bold: true),
            Line("PEMBERTON, ELLIS", size: 40),
            Line("DIMETHYL FUMARATE 240 MG DR CAPSULE", size: 50, bold: true),
            Line("MFR: BIOGEN   NDC 64406-006-02", size: size),
            Line("TAKE 1 CAPSULE BY MOUTH TWICE DAILY", size: 42),
            Line("QTY: 60", size: 44, bold: true),
            Line("2 REFILLS REMAINING", size: 40),
            Line("DISCARD AFTER 07/14/26", size: 40, bold: true)
        ])
        let data = try XCTUnwrap(image.pngData())
        let evidence = try await StillImageRecognizer.recognize(data: data, origin: .photoLibrary)
        return MedicationLabelInterpreter.offlineDraft(evidence)
    }

    private func renderedText(_ text: String, font: UIFont, at origin: CGPoint, canvas: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            NSString(string: text).draw(at: origin, withAttributes: [.font: font, .foregroundColor: UIColor.black])
        }
    }

    private struct Line {
        let text: String
        let size: CGFloat
        let bold: Bool

        init(_ text: String, size: CGFloat, bold: Bool = false) {
            self.text = text
            self.size = size
            self.bold = bold
        }
    }

    /// `pixelScale` zero renders at the simulator's screen scale, as the original
    /// labels do; one pixel per point makes the canvas the photo's pixel size.
    private func renderedLabel(canvas: CGSize = CGSize(width: 1200, height: 1500), pixelScale: CGFloat = 0, lines: [Line]) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = pixelScale
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            var y: CGFloat = canvas.height * 0.04
            for line in lines {
                let font = line.bold
                    ? UIFont.boldSystemFont(ofSize: line.size)
                    : UIFont.systemFont(ofSize: line.size)
                NSString(string: line.text).draw(
                    at: CGPoint(x: canvas.width * 0.058, y: y),
                    withAttributes: [.font: font, .foregroundColor: UIColor.black]
                )
                y += line.size + canvas.height * 0.028
            }
        }
    }
}
