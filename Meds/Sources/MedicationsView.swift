import SwiftData
import SwiftUI

struct MedicationsView: View {
    @Query(sort: \Medication.name) private var medications: [Medication]
    @State private var searchText = ""
    @State private var showsArchived = false
    let onAdd: () -> Void

    private var filtered: [Medication] {
        medications.filter { medication in
            medication.isArchived == showsArchived &&
            (searchText.isEmpty || medication.name.localizedCaseInsensitiveContains(searchText) || medication.nickname.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            if filtered.isEmpty && searchText.isEmpty {
                ScrollView {
                    EmptyStateCard(
                        symbol: showsArchived ? "archivebox" : "pills.fill",
                        title: showsArchived ? "No archived medications" : "No medications yet",
                        message: showsArchived ? "Medications you archive will remain available here until you restore or delete them." : "Scan a bottle or enter a medication manually. Nothing is saved until you confirm it.",
                        actionTitle: showsArchived ? nil : "Add Medication",
                        action: showsArchived ? nil : onAdd
                    )
                    .padding(16)
                }
            } else {
                List {
                    ForEach(filtered) { medication in
                        NavigationLink {
                            MedicationDetailView(medication: medication)
                        } label: {
                            HStack(spacing: 13) {
                                MedicationGlyph(medication: medication, size: 44)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(medication.displayName)
                                        .font(.headline)
                                    Text(medication.subtitle.isEmpty ? medication.form.displayName : medication.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(showsArchived ? "Archived" : "Medications")
        .searchable(text: $searchText, prompt: "Search medications")
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                if !showsArchived {
                    Button(action: onAdd) {
                        Label("Add Medication", systemImage: "plus")
                    }
                }
                Button {
                    showsArchived.toggle()
                } label: {
                    Label(showsArchived ? "Show Active" : "Show Archived", systemImage: showsArchived ? "pills" : "archivebox")
                }
            }
        }
    }
}
