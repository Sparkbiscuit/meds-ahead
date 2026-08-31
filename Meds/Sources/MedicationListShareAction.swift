import SwiftData
import SwiftUI

/// The printable list a pharmacy counter or a specialist's intake form asks for.
/// Lives next to the medications it describes rather than in Settings.
struct MedicationListShareButton: View {
    @Query private var medications: [Medication]
    @Query private var schedules: [DoseSchedule]
    @Query private var inventoryEvents: [InventoryEvent]
    @Query private var doseEvents: [DoseEvent]
    @State private var medicationListShare: MedicationListShareItem?
    @State private var showingExportUnavailable = false

    private struct MedicationListShareItem: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private var hasActiveMedications: Bool {
        medications.contains { !$0.isArchived }
    }

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
            medications: medications,
            schedules: schedules,
            inventoryEvents: inventoryEvents,
            doseEvents: doseEvents
        )
        if let url = MedicationListPDFRenderer.render(entries: entries) {
            medicationListShare = MedicationListShareItem(url: url)
        } else {
            showingExportUnavailable = true
        }
    }
}
