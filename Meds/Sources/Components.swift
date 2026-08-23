import SwiftUI

struct MedicationGlyph: View {
    let medication: Medication
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
                .fill(AppTheme.color(for: medication).gradient)
            Image(systemName: medication.form.symbolName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SupplyGauge: View {
    let daysRemaining: Int?
    let leadDays: Int
    var size: CGFloat = 46

    private var progress: Double {
        guard let daysRemaining else { return 0.18 }
        return min(1, max(0.06, Double(daysRemaining) / Double(max(leadDays * 3, 21))))
    }

    private var color: Color {
        guard let daysRemaining else { return .secondary }
        if daysRemaining <= 0 { return .red }
        if daysRemaining <= leadDays { return .orange }
        return AppTheme.accent
    }

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.13), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let daysRemaining {
                Text("\(daysRemaining)")
                    .font(.caption.weight(.bold))
                    .contentTransition(.numericText())
            } else {
                Image(systemName: "questionmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(daysRemaining.map { "\($0) days of supply remaining" } ?? "Supply forecast unavailable")
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
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .cardSurface()
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

extension Double {
    var medicationQuantityText: String {
        if rounded() == self { return String(Int(self)) }
        return formatted(.number.precision(.fractionLength(0...2)))
    }
}
