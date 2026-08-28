import SwiftUI
import UIKit

/// A printable snapshot of the active medications — the sheet of paper the
/// pharmacy counter and the specialist's intake form keep asking for. Built as
/// plain values first so the content is testable apart from rendering.
struct MedicationListEntry: Identifiable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String
    let directions: String
    let scheduleLines: [String]
    let supplyLine: String
    let detailLine: String
}

enum MedicationListDocument {
    static func entries(
        medications: [Medication],
        schedules: [DoseSchedule],
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [MedicationListEntry] {
        medications
            .filter { !$0.isArchived }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { medication in
                entry(
                    for: medication,
                    schedules: schedules.filter { $0.medicationID == medication.id },
                    inventoryEvents: inventoryEvents,
                    doseEvents: doseEvents,
                    allSchedules: schedules,
                    now: now,
                    calendar: calendar
                )
            }
    }

    private static func entry(
        for medication: Medication,
        schedules: [DoseSchedule],
        inventoryEvents: [InventoryEvent],
        doseEvents: [DoseEvent],
        allSchedules: [DoseSchedule],
        now: Date,
        calendar: Calendar
    ) -> MedicationListEntry {
        var subtitleParts: [String] = []
        if !medication.nickname.isEmpty { subtitleParts.append(medication.name) }
        if !medication.strength.isEmpty { subtitleParts.append(medication.strength) }
        subtitleParts.append(medication.form.displayName)

        let scheduleLines: [String]
        if medication.isAsNeeded {
            scheduleLines = ["Taken as needed"]
        } else if schedules.isEmpty {
            scheduleLines = ["No schedule entered"]
        } else {
            scheduleLines = schedules
                .sorted { $0.minutesAfterMidnight < $1.minutesAfterMidnight }
                .map { schedule in
                    let quantity = "\(schedule.doseQuantity.medicationQuantityText) \(medication.form.unitName)\(schedule.doseQuantity == 1 ? "" : "s")"
                    return "\(timeText(minutes: schedule.minutesAfterMidnight, calendar: calendar)) — \(quantity) · \(weekdaySummary(mask: schedule.weekdayMask, calendar: calendar))"
                }
        }

        let forecast = ForecastEngine.forecast(
            medication: medication,
            schedules: allSchedules,
            inventoryEvents: inventoryEvents,
            doseEvents: doseEvents,
            now: now,
            calendar: calendar
        )
        let onHand = "\(forecast.currentSupply.medicationQuantityText) \(medication.form.unitName)\(forecast.currentSupply == 1 ? "" : "s") on hand"
        let supplyLine: String
        if let date = forecast.depletionDate, forecast.currentSupply > 0 {
            supplyLine = "\(onHand) · runs out around \(date.formatted(date: .abbreviated, time: .omitted))"
        } else {
            supplyLine = onHand
        }

        var detailParts: [String] = []
        if let refills = medication.refillsRemaining {
            detailParts.append("\(refills) refill\(refills == 1 ? "" : "s") remaining")
        }
        if let expiration = medication.expirationDate {
            detailParts.append("Package expires \(expiration.formatted(date: .abbreviated, time: .omitted))")
        }

        return MedicationListEntry(
            id: medication.id,
            title: medication.displayName,
            subtitle: subtitleParts.joined(separator: " · "),
            directions: medication.directions,
            scheduleLines: scheduleLines,
            supplyLine: supplyLine,
            detailLine: detailParts.joined(separator: " · ")
        )
    }

    /// Bit 0 is Sunday, matching `Calendar.component(.weekday)`. Days print in
    /// the locale's week order so "Mon, Wed, Fri" reads naturally everywhere.
    static func weekdaySummary(mask: Int, calendar: Calendar = .autoupdatingCurrent) -> String {
        if mask & 0b1111111 == 0b1111111 { return "Every day" }
        let first = calendar.firstWeekday - 1
        let ordered = (0..<7).map { (first + $0) % 7 }.filter { mask & (1 << $0) != 0 }
        guard !ordered.isEmpty else { return "No days selected" }
        return ordered.map { calendar.shortWeekdaySymbols[$0] }.joined(separator: ", ")
    }

    private static func timeText(minutes: Int, calendar: Calendar) -> String {
        let date = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Renders the document to a single-page PDF sized to its content. Returns nil
/// rather than sharing a blank or clipped page when rendering fails.
@MainActor
enum MedicationListPDFRenderer {
    static func render(entries: [MedicationListEntry], generatedAt: Date = .now) -> URL? {
        guard !entries.isEmpty else { return nil }
        let document = MedicationListDocumentView(entries: entries, generatedAt: generatedAt)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: document)
        renderer.proposedSize = ProposedViewSize(width: 612, height: nil)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Meds Ahead Medication List.pdf")
        var rendered = false
        renderer.render { size, render in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return }
            context.beginPDFPage(nil)
            render(context)
            context.endPDFPage()
            context.closePDF()
            rendered = true
        }
        return rendered ? url : nil
    }
}

/// Print styling: deliberately monochrome, ink-on-paper, and fixed to a US
/// Letter width so it reads as a document rather than a screenshot.
struct MedicationListDocumentView: View {
    let entries: [MedicationListEntry]
    let generatedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Medication List")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("As recorded in Meds Ahead on \(generatedAt.formatted(date: .long, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.35))
            }

            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.title)
                        .font(.system(size: 16, weight: .semibold))
                    Text(entry.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.35))
                    if !entry.directions.isEmpty {
                        documentLine(label: "Directions", value: entry.directions)
                    }
                    documentLine(label: "Schedule", value: entry.scheduleLines.joined(separator: "\n"))
                    documentLine(label: "Supply", value: entry.supplyLine)
                    if !entry.detailLine.isEmpty {
                        documentLine(label: "Prescription", value: entry.detailLine)
                    }
                    Divider()
                }
            }

            Text("Recorded by the person using Meds Ahead; not a pharmacy or clinical record. Confirm details against current labels.")
                .font(.system(size: 10))
                .foregroundStyle(Color(white: 0.45))
        }
        .padding(44)
        .frame(width: 612, alignment: .leading)
        .background(Color.white)
        .foregroundStyle(.black)
    }

    private func documentLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(white: 0.35))
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
