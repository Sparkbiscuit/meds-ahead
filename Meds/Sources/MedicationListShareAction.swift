import SwiftData
import SwiftUI

/// The printable list a pharmacy counter or a specialist's intake form asks for.
/// Lives next to the medications it describes rather than in Settings.
struct MedicationListShareButton: View {
    // This button lives in the Medications toolbar, so it is mounted for the whole
    // session. Four unfiltered queries here re-fetched every dose and inventory
    // event on every SwiftData change — the entire ledger, continuously, for a
    // sheet that is almost always closed. Only the enablement check stays live;
    // the rest is fetched when the button is actually tapped.
    @Query(filter: #Predicate<Medication> { !$0.isArchived })
    private var activeMedications: [Medication]
    @Environment(\.modelContext) private var modelContext
    @State private var medicationListShare: MedicationListShareItem?
    @State private var showingExportUnavailable = false

    private struct MedicationListShareItem: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private var hasActiveMedications: Bool { !activeMedications.isEmpty }

    var body: some View {
        Button {
            shareMedicationList()
        } label: {
            Label("Share Medication List", systemImage: "square.and.arrow.up")
        }
        .disabled(!hasActiveMedications)
        .accessibilityLabel("Share Medication List")
        .sheet(item: $medicationListShare) { item in
            ActivityShareSheet(items: [item.url])
                .presentationDetents([.medium, .large])
        }
        .alert("Couldn't Create the List", isPresented: $showingExportUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The medication list PDF could not be created. Try again.")
        }
    }

    private func shareMedicationList() {
        let entries = MedicationListDocument.entries(
            medications: fetch(Medication.self),
            schedules: fetch(DoseSchedule.self),
            inventoryEvents: fetch(InventoryEvent.self),
            doseEvents: fetch(DoseEvent.self)
        )
        if let url = MedicationListPDFRenderer.render(entries: entries) {
            medicationListShare = MedicationListShareItem(url: url)
        } else {
            showingExportUnavailable = true
        }
    }

    private func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
    }
}
