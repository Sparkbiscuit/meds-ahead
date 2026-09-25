import SwiftUI

struct SupplyGauge: View {
    /// A course the supply sees through, or one already over. Nothing runs
    /// out either way, so the ring reads complete: no day count, and never
    /// the question mark of a forecast that could not be made.
    enum Course: Equatable {
        case covered
        case finished
        /// Over, but its supply ran out before its last day. Over all the
        /// same, so it reads complete, without the tick that says finished.
        case ranOutFirst

        init?(_ forecast: SupplyForecast, ranOutFirst: Bool = false) {
            if forecast.courseFinished {
                self = ranOutFirst ? .ranOutFirst : .finished
            } else if forecast.courseCovered {
                self = .covered
            } else {
                return nil
            }
        }
    }

    let daysRemaining: Int?
    let leadDays: Int
    /// The forecast's zero days are where its assumed doses ran out, not a
    /// runway: the ring asks for a count instead of reading empty and red.
    var needsCount = false
    var course: Course? = nil
    var size: CGFloat = 46

    /// The day count the ring prints, if any.
    var shownDays: Int? { needsCount || course != nil ? nil : daysRemaining }

    /// Whether the ring only says what the words beside it say first: a
    /// count needed and a course are what the title or summary it sits
    /// next to opens with, so VoiceOver passes over it then.
    var repeatsItsSummary: Bool { needsCount || course != nil }

    private var progress: Double {
        if course != nil { return 1 }
        guard let shownDays else { return 0.18 }
        return min(1, max(0.06, Double(shownDays) / Double(max(leadDays * 3, 21))))
    }

    var color: Color {
        if needsCount { return .orange }
        switch course {
        case .covered: return AppTheme.accent
        case .finished, .ranOutFirst: return .secondary
        case nil: break
        }
        guard let daysRemaining else { return .secondary }
        if daysRemaining <= 0 { return .red }
        if daysRemaining <= leadDays { return .orange }
        return AppTheme.accent
    }

    var accessibilityText: String {
        if needsCount { return "Count needed" }
        switch course {
        case .covered: return "Enough to finish the course"
        case .finished: return "Course finished"
        case .ranOutFirst: return "Course over"
        case nil: break
        }
        return daysRemaining.map { "\($0.dayCountText) of supply remaining" } ?? "Supply forecast unavailable"
    }

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.13), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let shownDays {
                Text("\(shownDays)")
                    .font(.caption.weight(.bold))
                    .contentTransition(.numericText())
            } else if course == .ranOutFirst {
                Image(systemName: "calendar")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
            } else if course != nil {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
            } else {
                Image(systemName: "questionmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(needsCount ? AnyShapeStyle(color) : AnyShapeStyle(.secondary))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

struct EmptyStateCard: View {
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(symbol: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .symbolEffect(.breathe, options: .repeat(2))
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(AppTheme.onAccent)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}

/// The one thing Today must say out loud when it is true: these reminders are not
/// going to arrive. It sits above the day's doses rather than inside Settings,
/// because nobody opens Settings to discover a problem they don't know they have.
struct NotificationHealthBanner: View {
    let state: NotificationHealth.State
    let onAllow: () -> Void
    let onOpenSettings: () -> Void
    let onRetry: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.orange)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        switch state {
        case .blocked: "bell.slash.fill"
        case .unasked: "bell.badge"
        case .partlyScheduled, .fine: "exclamationmark.triangle.fill"
        }
    }

    private var title: String {
        switch state {
        case .blocked: "Reminders are turned off"
        case .unasked: "Reminders need your permission"
        case .partlyScheduled, .fine: "Some reminders weren't set"
        }
    }

    private var message: String {
        switch state {
        case .blocked:
            "Meds Ahead can't send dose or refill reminders until notifications are allowed in Settings."
        case .unasked:
            "Your schedules are saved, but no reminder can be delivered until you allow notifications."
        case let .partlyScheduled(failed):
            "\(failed.counted("reminder", plural: "reminders")) couldn't be scheduled with iOS. Your medications and history are unaffected."
        case .fine:
            ""
        }
    }

    private var actionTitle: String {
        switch state {
        case .blocked: "Open Settings"
        case .unasked: "Allow Reminders"
        case .partlyScheduled, .fine: "Try Again"
        }
    }

    private var action: () -> Void {
        switch state {
        case .blocked: onOpenSettings
        case .unasked: onAllow
        case .partlyScheduled, .fine: onRetry
        }
    }
}

struct ConfidenceBadge: View {
    let confidence: ForecastConfidence

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.11), in: Capsule())
    }

    private var title: String {
        switch confidence {
        case .high: "Scheduled"
        case .estimated: "Estimated"
        case .unknown: "Needs info"
        }
    }

    private var symbol: String {
        switch confidence {
        case .high: "checkmark.seal.fill"
        case .estimated: "waveform.path.ecg"
        case .unknown: "questionmark.circle.fill"
        }
    }

    private var color: Color {
        switch confidence {
        case .high: AppTheme.accent
        case .estimated: .orange
        case .unknown: .secondary
        }
    }
}
