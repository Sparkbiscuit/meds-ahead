import SwiftData
import SwiftUI

/// The medications a person shares from Apple Health, each a tap away from the
/// same review screen a scanned label reaches.
@available(iOS 26.0, *)
struct HealthImportView: View {
    let onReview: (MedicationDraft) -> Void

    @Query private var medications: [Medication]
    @State private var phase: Phase = .notAsked
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum Phase: Equatable {
        case notAsked
        case loading
        case loaded([HealthMedicationSummary])
        case failed
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.title2)
                            .foregroundStyle(AppTheme.accent)
                            .accessibilityHidden(true)
                        Text("Health shows you its own list and you tick the medications to share. Meds Ahead reads only those, along with the doses you logged for them in the last 30 days, and keeps bringing over doses you log in Health for them from then on. It never writes to Health, and everything stays on this iPhone.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        Task { await load() }
                    } label: {
                        Label(phase == .notAsked ? "Choose Medications in Health" : "Choose Again",
                              systemImage: "checklist")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(AppTheme.onAccent)
                    .controlSize(.large)
                    .disabled(phase == .loading)
                    .accessibilityIdentifier("choose-health-medications")
                }
                .padding(.vertical, 4)
            }

            switch phase {
            case .notAsked:
                EmptyView()
            case .loading:
                Section {
                    HStack {
                        ProgressView()
                        Text("Reading the medications you shared…")
                            .foregroundStyle(.secondary)
                    }
                }
            case .failed:
                Section {
                    Label("Health didn’t return any medications", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text("Check that Health is available on this iPhone, then try again.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case let .loaded(summaries):
                if summaries.isEmpty {
                    Section {
                        Text("No medications are shared with Meds Ahead yet. Choose Again shows Health’s list.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(summaries) { summary in
                            row(for: summary)
                        }
                    } header: {
                        Text("Shared from Health")
                    } footer: {
                        Text("Each medication is reviewed before it is saved. You enter what you have on hand and the schedule Meds Ahead should keep count of.")
                    }
                }
            }
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(for summary: HealthMedicationSummary) -> some View {
        let draft = HealthMedicationMapper.draft(for: summary)
        let existing = HealthMedicationMapper.existingMedication(for: draft, among: medications)
        Button {
            onReview(draft)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.displayText)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle(for: summary, draft: draft, existing: existing))
                        .font(.subheadline)
                        .foregroundStyle(existing == nil ? .secondary : AppTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: existing == nil ? "chevron.right" : "checkmark.circle.fill")
                    .foregroundStyle(existing == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(AppTheme.accent))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(existing == nil ? "Review and add to Meds Ahead" : "Already in Meds Ahead; opens the review screen to add it again")
    }

    private func subtitle(for summary: HealthMedicationSummary, draft: MedicationDraft, existing: Medication?) -> String {
        if let existing {
            return "Already in Meds Ahead as \(existing.displayName)"
        }
        var parts: [String] = []
        if !summary.nickname.isEmpty { parts.append("“\(summary.nickname)”") }
        parts.append(draft.form.displayName)
        parts.append(summary.hasSchedule ? "Scheduled in Health" : "As needed in Health")
        if !summary.recentTakenDoses.isEmpty {
            let count = summary.recentTakenDoses.count
            parts.append("\(count.counted("dose", plural: "doses")) logged in 30 days")
        }
        if summary.isArchived { parts.append("Archived in Health") }
        return parts.joined(separator: " · ")
    }

    @MainActor
    private func load() async {
        phase = .loading
        do {
            let summaries = try await HealthMedicationImporter.chooseMedications()
            phase = .loaded(summaries.sorted { $0.displayText.localizedCaseInsensitiveCompare($1.displayText) == .orderedAscending })
        } catch {
            phase = .failed
        }
    }
}
