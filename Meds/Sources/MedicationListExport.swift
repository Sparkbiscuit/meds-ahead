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
        if !medication.brandName.isEmpty { subtitleParts.append("Brand: \(medication.brandName)") }
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

/// Renders the document as a real US Letter PDF, paginated.
///
/// It used to emit one page sized to its own content, which for the household this
/// was built for — a dozen medications and more — meant a single page some three
/// feet tall. Printing that scales it to illegibility, which is precisely the moment
/// the sheet is meant to be useful. Entries are measured and packed onto Letter-sized
/// pages instead, and nothing is broken across a page boundary.
@MainActor
enum MedicationListPDFRenderer {
    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 44
    private static let entrySpacing: CGFloat = 14
    private static let pageNumberAllowance: CGFloat = 24

    private static var exportURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Meds Ahead Medication List.pdf")
    }

    /// The rendered list is a full medication history in the clear, and it used to be
    /// left in the temporary directory indefinitely. Sweeping it at launch bounds how
    /// long it survives without racing a share that may still be reading it — an
    /// AirDrop finishes long after the sheet that started it has gone.
    static func removePreviousExport() {
        try? FileManager.default.removeItem(at: exportURL)
    }

    static func render(entries: [MedicationListEntry], generatedAt: Date = .now) -> URL? {
        guard !entries.isEmpty else { return nil }
        let contentWidth = pageSize.width - margin * 2
        let usableHeight = pageSize.height - margin * 2 - pageNumberAllowance

        let headerHeight = measuredHeight(MedicationListHeaderView(generatedAt: generatedAt), width: contentWidth)
        let disclaimerHeight = measuredHeight(MedicationListDisclaimerView(), width: contentWidth)
        let pages = paginate(
            entries: entries,
            heights: entries.map { measuredHeight(MedicationListEntryView(entry: $0), width: contentWidth) },
            headerHeight: headerHeight,
            disclaimerHeight: disclaimerHeight,
            usableHeight: usableHeight
        )

        let url = exportURL
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return nil }
        for (index, pageEntries) in pages.enumerated() {
            let page = MedicationListPageView(
                entries: pageEntries,
                generatedAt: index == 0 ? generatedAt : nil,
                showsDisclaimer: index == pages.count - 1,
                pageNumber: index + 1,
                pageCount: pages.count,
                size: pageSize,
                margin: margin,
                spacing: entrySpacing
            )
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(pageSize)
            context.beginPDFPage(nil)
            renderer.render { _, draw in draw(context) }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    /// Greedy packing. An entry taller than a whole page is left to overflow its own
    /// page rather than being split mid-medication, which would be worse to read.
    private static func paginate(
        entries: [MedicationListEntry],
        heights: [CGFloat],
        headerHeight: CGFloat,
        disclaimerHeight: CGFloat,
        usableHeight: CGFloat
    ) -> [[MedicationListEntry]] {
        var pages: [[MedicationListEntry]] = []
        var current: [MedicationListEntry] = []
        var used = headerHeight + entrySpacing

        for (entry, height) in zip(entries, heights) {
            let needed = height + entrySpacing
            if !current.isEmpty, used + needed > usableHeight {
                pages.append(current)
                current = []
                used = 0
            }
            current.append(entry)
            used += needed
        }
        if !current.isEmpty, used + disclaimerHeight > usableHeight {
            pages.append(current)
            current = []
        }
        pages.append(current)
        return pages
    }

    private static func measuredHeight(_ view: some View, width: CGFloat) -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: width, alignment: .leading))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        var height: CGFloat = 0
        renderer.render { size, _ in height = size.height }
        return height
    }
}

/// Print styling: deliberately monochrome, ink-on-paper, and fixed to a US Letter
/// page so it reads as a document rather than a screenshot.
struct MedicationListPageView: View {
    let entries: [MedicationListEntry]
    let generatedAt: Date?
    let showsDisclaimer: Bool
    let pageNumber: Int
    let pageCount: Int
    let size: CGSize
    let margin: CGFloat
    let spacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let generatedAt {
                MedicationListHeaderView(generatedAt: generatedAt)
            }
            ForEach(entries) { entry in
                MedicationListEntryView(entry: entry)
            }
            if showsDisclaimer {
                MedicationListDisclaimerView()
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Text("Page \(pageNumber) of \(pageCount)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.45))
            }
        }
        .padding(margin)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(.black)
        .environment(\.colorScheme, .light)
    }
}

struct MedicationListHeaderView: View {
    let generatedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Medication List")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("As recorded in Meds Ahead on \(generatedAt.formatted(date: .long, time: .shortened))")
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.35))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.black)
    }
}

struct MedicationListEntryView: View {
    let entry: MedicationListEntry

    var body: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
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

struct MedicationListDisclaimerView: View {
    var body: some View {
        Text("Recorded by the person using Meds Ahead; not a pharmacy or clinical record. Confirm details against current labels.")
            .font(.system(size: 10))
            .foregroundStyle(Color(white: 0.45))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
