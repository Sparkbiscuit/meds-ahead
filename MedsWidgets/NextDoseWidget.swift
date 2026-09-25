import SwiftUI
import WidgetKit

struct NextDoseEntry: TimelineEntry {
    let date: Date
    let snapshot: NextDoseSnapshot?
    /// True when the store could not be read, which is not the same as having
    /// nothing scheduled.
    let needsApp: Bool

    static func placeholder(at date: Date = .now) -> NextDoseEntry {
        let item = NextDoseSnapshot.Item(medicationID: UUID(), scheduleID: UUID(), displayName: "Furosemide", quantityText: "1 tablet", accentIndex: 0)
        let time = Calendar.autoupdatingCurrent.date(bySettingHour: 20, minute: 0, second: 0, of: date) ?? date
        return NextDoseEntry(date: date, snapshot: NextDoseSnapshot(state: .next(time: time, items: [item]), now: date), needsApp: false)
    }
}

struct NextDoseProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextDoseEntry {
        .placeholder()
    }

    func getSnapshot(in context: Context, completion: @escaping (NextDoseEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder())
            return
        }
        Task { @MainActor in
            completion(entries(now: .now).first ?? .placeholder())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextDoseEntry>) -> Void) {
        Task { @MainActor in
            let now = Date.now
            completion(Timeline(entries: entries(now: now), policy: .atEnd))
        }
    }

    /// One entry now, then one at every moment the answer changes on its own.
    @MainActor
    private func entries(now: Date) -> [NextDoseEntry] {
        guard let contents = try? WidgetStore.load() else {
            return [NextDoseEntry(date: now, snapshot: nil, needsApp: true)]
        }
        let times = [now] + NextDoseSnapshot.changeTimes(
            medications: contents.medications,
            schedules: contents.schedules,
            doseEvents: contents.doseEvents,
            now: now
        )
        return times.map { date in
            NextDoseEntry(
                date: date,
                snapshot: NextDoseSnapshot.make(
                    medications: contents.medications,
                    schedules: contents.schedules,
                    doseEvents: contents.doseEvents,
                    now: date
                ),
                needsApp: false
            )
        }
    }
}

struct NextDoseWidget: Widget {
    static let kind = "com.christoforakis.Meds.nextDose"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NextDoseProvider()) { entry in
            NextDoseView(entry: entry)
        }
        .configurationDisplayName("Next Dose")
        .description("The next scheduled dose, and a tap to log it.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct NextDoseView: View {
    let entry: NextDoseEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            inline
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        default:
            home
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
    }

    // MARK: - Home Screen

    private var home: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(headline, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(entry.snapshot?.isOverdue == true ? Color.orange : AppTheme.accent)
                .lineLimit(1)
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
            if let item = entry.snapshot?.actionable, case let .next(time, _) = entry.snapshot?.state {
                // Bordered rather than prominent: the Home Screen's accented and
                // clear rendering modes flatten a prominent button into a solid
                // pill whose label disappears into it.
                Button(intent: LogNextDoseIntent(medicationID: item.medicationID, scheduleID: item.scheduleID, scheduledAt: time)) {
                    Label("Taken", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .widgetAccentable()
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        if entry.needsApp {
            Text("Open Meds Ahead once to share your schedule with this widget.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if let snapshot = entry.snapshot {
            switch snapshot.state {
            case .noMedications:
                Text("Add a medication to see what's next.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .nothingScheduled:
                Text("Nothing scheduled today")
                    .font(.headline)
            case let .allLogged(count):
                Text("All \(count) logged")
                    .font(.headline)
                Text("Every scheduled dose is accounted for.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case let .next(time, items):
                Text(time, style: .time)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                ForEach(items.prefix(family == .systemMedium ? 3 : 2)) { item in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AppTheme.medicationColors[Int(item.accentIndex.magnitude % UInt(AppTheme.medicationColors.count))])
                            .frame(width: 8, height: 8)
                        Text(item.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if family == .systemMedium {
                            Text(item.quantityText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .privacySensitive()
                }
                if items.count > (family == .systemMedium ? 3 : 2) {
                    Text("+\(items.count - (family == .systemMedium ? 3 : 2)) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var headline: String {
        guard let snapshot = entry.snapshot, case .next = snapshot.state else { return "Meds Ahead" }
        return snapshot.isOverdue ? "Overdue" : "Next dose"
    }

    private var symbol: String {
        guard let snapshot = entry.snapshot, case .next = snapshot.state else { return "pills.fill" }
        return snapshot.isOverdue ? "exclamationmark.circle.fill" : "clock.fill"
    }

    // MARK: - Lock Screen

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if entry.needsApp {
                Text("Meds Ahead").font(.headline)
                Text("Open the app once").font(.caption2)
            } else if let snapshot = entry.snapshot {
                switch snapshot.state {
                case .noMedications, .nothingScheduled:
                    Text("Meds Ahead").font(.headline)
                    Text("Nothing scheduled today").font(.caption2)
                case let .allLogged(count):
                    Text("All \(count) logged").font(.headline)
                    Text("Meds Ahead").font(.caption2)
                case let .next(time, items):
                    HStack(spacing: 4) {
                        Image(systemName: snapshot.isOverdue ? "exclamationmark.circle.fill" : "clock.fill")
                        Text(time, style: .time).monospacedDigit()
                    }
                    .font(.headline)
                    .widgetAccentable()
                    Text(items.map(\.displayName).joined(separator: ", "))
                        .font(.caption2)
                        .lineLimit(2)
                        .privacySensitive()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "pills.fill")
                    .font(.caption)
                if let snapshot = entry.snapshot, case let .next(time, _) = snapshot.state {
                    Text(time, style: .time)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                } else if let snapshot = entry.snapshot, case .allLogged = snapshot.state {
                    Image(systemName: "checkmark").font(.caption2)
                } else {
                    Text("—").font(.caption2)
                }
            }
            .widgetAccentable()
        }
    }

    private var inline: some View {
        Group {
            if let snapshot = entry.snapshot, case let .next(time, items) = snapshot.state {
                Text("\(Image(systemName: "pills.fill")) \(time, style: .time) \(items.count == 1 ? items[0].displayName : "\(items.count) medications")")
                    .privacySensitive()
            } else if let snapshot = entry.snapshot, case let .allLogged(count) = snapshot.state {
                Text("\(Image(systemName: "checkmark.circle")) All \(count.counted("dose", plural: "doses")) logged")
            } else {
                Text("\(Image(systemName: "pills.fill")) Meds Ahead")
            }
        }
    }
}
