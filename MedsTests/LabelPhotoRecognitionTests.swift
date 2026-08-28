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
            Line("RX# 7719204", size: 40, bold: true),
            Line("CHRISTOFORAKIS, LUKAS", size: 40),
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

    private func renderedLabel(lines: [Line]) -> UIImage {
        let canvas = CGSize(width: 1200, height: 1500)
        return UIGraphicsImageRenderer(size: canvas).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            var y: CGFloat = 60
            for line in lines {
                let font = line.bold
                    ? UIFont.boldSystemFont(ofSize: line.size)
                    : UIFont.systemFont(ofSize: line.size)
                NSString(string: line.text).draw(
                    at: CGPoint(x: 70, y: y),
                    withAttributes: [.font: font, .foregroundColor: UIColor.black]
                )
                y += line.size + 42
            }
        }
    }
}
