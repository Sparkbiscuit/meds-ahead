import SwiftUI
import XCTest
@testable import Meds

/// A forecast whose assumed doses used up the ledger comes with zero days and
/// today's date. The screens that read a forecast must ask for a count there,
/// never say the supply is gone or give a date.
final class CountNeededDisplayTests: XCTestCase {
    private let countNeeded = SupplyForecast(currentSupply: 6, depletionDate: .now, daysRemaining: 0, confidence: .estimated,
                                             explanation: "", assumedDoses: 10, needsCount: true)
    private let empty = SupplyForecast(currentSupply: 0, depletionDate: .now, daysRemaining: 0, confidence: .high,
                                       explanation: "No confirmed supply remains.")

    func testTheGaugeAsksRatherThanReadingEmpty() {
        let gauge = SupplyGauge(daysRemaining: 0, leadDays: 7, needsCount: true)
        XCTAssertNil(gauge.shownDays)
        XCTAssertEqual(gauge.color, .orange, "the attention colour, not the red of an empty supply")
        XCTAssertEqual(gauge.accessibilityText, "Count needed")

        let out = SupplyGauge(daysRemaining: 0, leadDays: 7)
        XCTAssertEqual(out.shownDays, 0)
        XCTAssertEqual(out.color, .red)
        XCTAssertEqual(out.accessibilityText, "0 days of supply remaining")
    }

    func testTheDetailScreenTitleSaysACountIsNeeded() {
        XCTAssertEqual(MedicationDetailView.forecastTitle(for: countNeeded), "Count needed")
        XCTAssertEqual(MedicationDetailView.forecastTitle(for: empty), "Out of supply")
        let steady = SupplyForecast(currentSupply: 20, depletionDate: .now, daysRemaining: 9, confidence: .high, explanation: "")
        XCTAssertEqual(MedicationDetailView.forecastTitle(for: steady), "About 9 days left")
    }

    /// Prefilled with the ledger's number, one tap on Save Count confirmed a
    /// count nobody made and cleared the doses the forecast had assumed.
    func testCorrectCountOpensEmptyWhileACountIsNeeded() {
        XCTAssertNil(SupplyChangeQuantity.countPrefill(for: countNeeded))
        XCTAssertNil(SupplyChangeQuantity.value(from: "", prefilled: nil, requiresMoreThanZero: false), "an empty field cannot be saved")
        XCTAssertEqual(SupplyChangeQuantity.value(from: "6", prefilled: nil, requiresMoreThanZero: false, locale: Locale(identifier: "en_US")), 6,
                       "the same number, typed after counting, is a count")

        XCTAssertEqual(SupplyChangeQuantity.countPrefill(for: empty), 0)
        let steady = SupplyForecast(currentSupply: 27.125, depletionDate: nil, daysRemaining: nil, confidence: .unknown, explanation: "")
        XCTAssertEqual(SupplyChangeQuantity.countPrefill(for: steady), 27.125)
    }
}
