import SwiftUI

/// A month of taken and skipped doses for one medication, the way a clinician
/// asks about them: not "did you take it" but "which days".
struct AdherenceCalendarCard: View {
    let medication: Medication
    let schedules: [DoseSchedule]
    let doseEvents: [DoseEvent]
    @State private var month = Date.now
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var calendar: Calendar { .autoupdatingCurrent }

    private var days: [AdherenceDay] {
        AdherenceSummary.month(
            containing: month,
            medicationID: medication.id,
            schedules: schedules,
            doseEvents: doseEvents,
            calendar: calendar
        )
    }

    /// Whether the person can page forward: never past the current month, since
    /// the future has nothing logged in it.
    private var canGoForward: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { return false }
        return calendar.compare(next, to: .now, toGranularity: .month) != .orderedDescending
    }

    private var summaryLine: String {
        let past = days.filter { $0.state != .upcoming && $0.state != .none }
        let taken = past.reduce(0) { $0 + $1.taken }
        let skipped = past.reduce(0) { $0 + $1.skipped }
        let missed = past.filter { $0.state == .missed }.count
        guard taken + skipped + missed > 0 else { return "Nothing logged this month yet." }
        var parts = ["\(taken) taken"]
        if skipped > 0 { parts.append("\(skipped) skipped") }
        if missed > 0 { parts.append("\(missed) day\(missed == 1 ? "" : "s") with nothing logged") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Doses by day", systemImage: "calendar.badge.checkmark")
                    .font(.headline)
                Spacer()
                Button {
                    if let previous = calendar.date(byAdding: .month, value: -1, to: month) { month = previous }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Previous month")
                Button {
                    if let next = calendar.date(byAdding: .month, value: 1, to: month) { month = next }
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 32)
                }
                .disabled(!canGoForward)
                .accessibilityLabel("Next month")
            }
            .buttonStyle(.plain)

            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.subheadline.weight(.semibold))

            grid

            Text(summaryLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            legend
        }
        .padding(18)
        .cardSurface()
        .accessibilityElement(children: .contain)
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let order = (0..<7).map { (first + $0) % 7 }
        // Empty cells before the first, so the first of the month lands on its weekday.
        let leading = days.first.map { (calendar.component(.weekday, from: $0.date) - 1 - first + 7) % 7 } ?? 0
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(order, id: \.self) { index in
                Text(symbols[index])
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            ForEach(0..<leading, id: \.self) { _ in
                Color.clear.frame(height: 30)
            }
            ForEach(days) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: AdherenceDay) -> some View {
        let number = calendar.component(.day, from: day.date)
        return Text("\(number)")
            .font(.caption.weight(day.state == .none || day.state == .upcoming ? .regular : .semibold))
            .monospacedDigit()
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(fill(for: day.state), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay { outline(for: day.state) }
            .overlay(alignment: .topTrailing) { glyph(for: day.state) }
            .foregroundStyle(textColor(for: day.state))
            .accessibilityLabel(accessibilityText(for: day))
    }

    /// The states differ by more than their fill: a missed day is always
    /// outlined, and with Differentiate Without Color on, every logged state
    /// carries its own mark as well.
    @ViewBuilder
    private func outline(for state: AdherenceDay.State) -> some View {
        switch state {
        case .upcoming:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
        case .missed:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.onWarning.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
        case .complete, .partial, .skipped, .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func glyph(for state: AdherenceDay.State) -> some View {
        if differentiateWithoutColor, let name = glyphName(for: state) {
            Image(systemName: name)
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(textColor(for: state))
                .padding(3)
                .accessibilityHidden(true)
        }
    }

    private func glyphName(for state: AdherenceDay.State) -> String? {
        switch state {
        case .complete: "checkmark"
        case .partial: "minus"
        case .skipped: "xmark"
        case .missed: "exclamationmark"
        case .upcoming, .none: nil
        }
    }

    private func fill(for state: AdherenceDay.State) -> Color {
        switch state {
        case .complete: AppTheme.accent
        case .partial: AppTheme.accent.opacity(0.45)
        case .skipped: Color.secondary.opacity(0.35)
        case .missed: Color.orange.opacity(0.85)
        case .upcoming, .none: Color.clear
        }
    }

    private func textColor(for state: AdherenceDay.State) -> Color {
        switch state {
        case .complete: AppTheme.onAccent
        case .missed: AppTheme.onWarning
        case .partial, .skipped: .primary
        case .upcoming: .primary
        case .none: .secondary
        }
    }

    private func accessibilityText(for day: AdherenceDay) -> String {
        let date = day.date.formatted(.dateTime.month(.wide).day())
        switch day.state {
        case .none: return "\(date), nothing scheduled"
        case .complete: return "\(date), \(day.taken) taken"
        case .partial: return "\(date), \(day.taken) of \(day.scheduled) taken, \(day.skipped) skipped"
        case .skipped: return "\(date), skipped"
        case .missed: return "\(date), nothing logged"
        case .upcoming: return "\(date), upcoming"
        }
    }

    private var legend: some View {
        let items: [(String, AdherenceDay.State)] = [("Taken", .complete), ("Some", .partial), ("Skipped", .skipped), ("Nothing logged", .missed)]
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            ForEach(items, id: \.0) { title, state in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(fill(for: state))
                        .frame(width: 12, height: 12)
                        .overlay { outline(for: state) }
                        .overlay {
                            if differentiateWithoutColor, let name = glyphName(for: state) {
                                Image(systemName: name)
                                    .font(.system(size: 7, weight: .black))
                                    .foregroundStyle(textColor(for: state))
                            }
                        }
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
