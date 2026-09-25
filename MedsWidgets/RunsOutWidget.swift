import SwiftUI
import WidgetKit

struct RunsOutEntry: TimelineEntry {
    let date: Date
    let snapshot: RunsOutSnapshot?
    let needsApp: Bool

    static func placeholder(at date: Date = .now) -> RunsOutEntry {
        let calendar = Calendar.autoupdatingCurrent
        let items = [
            RunsOutSnapshot.Item(medicationID: UUID(), displayName: "Dimethyl fumarate", daysRemaining: 6,
                                 depletionDate: calendar.date(byAdding: .day, value: 6, to: date), refillLeadDays: 10,
                                 refillsRemaining: 0, refillInProgress: false, daysSinceRefillDate: nil, onHand: true,
                                 accentIndex: 2),
            RunsOutSnapshot.Item(medicationID: UUID(), displayName: "Furosemide", daysRemaining: 21,
                                 depletionDate: calendar.date(byAdding: .day, value: 21, to: date), refillLeadDays: 7,
                                 refillsRemaining: 2, refillInProgress: false, daysSinceRefillDate: nil, onHand: true,
                                 accentIndex: 0)
        ]
        return RunsOutEntry(date: date, snapshot: RunsOutSnapshot(items: items, now: date), needsApp: false)
    }
}

struct RunsOutProvider: TimelineProvider {
    func placeholder(in context: Context) -> RunsOutEntry {
        .placeholder()
    }

    func getSnapshot(in context: Context, completion: @escaping (RunsOutEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder())
            return
        }
        Task { @MainActor in
            completion(entry(now: .now))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RunsOutEntry>) -> Void) {
        Task { @MainActor in
            let now = Date.now
            // The day count moves at midnight; the app reloads the widget
            // whenever the ledger changes.
            let tomorrow = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: Calendar.autoupdatingCurrent.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
            completion(Timeline(entries: [entry(now: now)], policy: .after(tomorrow)))
        }
    }

    @MainActor
    private func entry(now: Date) -> RunsOutEntry {
        guard let contents = try? WidgetStore.load() else {
            return RunsOutEntry(date: now, snapshot: nil, needsApp: true)
        }
        return RunsOutEntry(
            date: now,
            snapshot: RunsOutSnapshot.make(
                medications: contents.medications,
                schedules: contents.schedules,
                inventoryEvents: contents.inventoryEvents,
                doseEvents: contents.doseEvents,
                now: now
            ),
            needsApp: false
        )
    }
}

struct RunsOutWidget: Widget {
    static let kind = "com.christoforakis.Meds.runsOut"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: RunsOutProvider()) { entry in
            RunsOutView(entry: entry)
        }
        .configurationDisplayName("Runs Out Next")
        .description("Which medication runs out first, and when.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct RunsOutView: View {
    let entry: RunsOutEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            inline
        case .accessoryRectangular:
            rectangular
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        default:
            home
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
    }

    private var soonest: RunsOutSnapshot.Item? { entry.snapshot?.soonest }

    private func color(for item: RunsOutSnapshot.Item) -> Color {
        switch item.tone {
        case .unknown: .secondary
        case .steady: AppTheme.accent
        case .attention: .orange
        case .out: .red
        }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Runs out next", systemImage: "chart.bar.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .lineLimit(1)
            Spacer(minLength: 0)
            if entry.needsApp {
                Text("Open Meds Ahead once to share your supply with this widget.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let item = soonest {
                Text(item.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .privacySensitive()
                HStack(spacing: 8) {
                    gauge(for: item)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.line)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(color(for: item))
                        if let date = item.depletionDate, item.daysRemaining ?? 0 > 0 {
                            Text("around \(date.formatted(.dateTime.month(.abbreviated).day()))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if family == .systemMedium, let snapshot = entry.snapshot, snapshot.items.count > 1 {
                    Divider()
                    ForEach(snapshot.items.dropFirst().prefix(2)) { next in
                        HStack {
                            Text(next.displayName)
                                .font(.caption)
                                .lineLimit(1)
                                .privacySensitive()
                            Spacer()
                            Text(next.daysRemaining.map { "\($0) d" } ?? "?")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color(for: next))
                        }
                    }
                }
            } else {
                Text("Add a medication with a count to see what runs out next.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func gauge(for item: RunsOutSnapshot.Item) -> some View {
        let color = color(for: item)
        let progress: Double = {
            guard let days = item.daysRemaining else { return 0.18 }
            return min(1, max(0.06, Double(days) / Double(max(item.refillLeadDays * 3, 21))))
        }()
        return ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(item.daysRemaining.map(String.init) ?? "?")
                .font(.caption2.weight(.bold))
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let item = soonest {
                HStack(spacing: 4) {
                    Image(systemName: item.needsAttention ? "exclamationmark.circle.fill" : "chart.bar.fill")
                    Text(item.displayName).lineLimit(1).privacySensitive()
                }
                .font(.headline)
                .widgetAccentable()
                Text(item.line).font(.caption2)
                if let date = item.depletionDate, item.daysRemaining ?? 0 > 0 {
                    Text("Runs out around \(date.formatted(.dateTime.month(.abbreviated).day()))").font(.caption2)
                }
            } else {
                Text("Meds Ahead").font(.headline)
                Text(entry.needsApp ? "Open the app once" : "No supply to forecast").font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Group {
            if let item = soonest {
                Text("\(Image(systemName: "chart.bar.fill")) \(item.displayName): \(item.line.lowercased())")
                    .privacySensitive()
            } else {
                Text("\(Image(systemName: "chart.bar.fill")) Meds Ahead")
            }
        }
    }
}
