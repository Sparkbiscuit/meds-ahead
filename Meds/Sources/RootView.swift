import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case today
    case supply
    case medications
    case add
}

struct RootView: View {
    @Query private var medications: [Medication]
    @Query private var schedules: [DoseSchedule]
    @Query private var inventoryEvents: [InventoryEvent]
    @Query private var doseEvents: [DoseEvent]
    @Environment(\.modelContext) private var modelContext
    @State private var selection: AppTab
    @State private var isPresentingAdd = false
    @State private var isPresentingSettings = false

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let initialSelection: AppTab = if arguments.contains("-start-supply") {
            .supply
        } else if arguments.contains("-start-medications") {
            .medications
        } else {
            .today
        }
        _selection = State(initialValue: initialSelection)
#else
        _selection = State(initialValue: .today)
#endif
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max.fill", value: .today) {
                NavigationStack {
                    TodayView(onAdd: { isPresentingAdd = true })
                        .toolbar { settingsToolbar }
                }
            }

            Tab("Supply", systemImage: "chart.bar.fill", value: .supply) {
                NavigationStack {
                    SupplyView(onAdd: { isPresentingAdd = true })
                        .toolbar { settingsToolbar }
                }
            }

            Tab("Medications", systemImage: "pills.fill", value: .medications) {
                NavigationStack {
                    MedicationsView(onAdd: { isPresentingAdd = true })
                        .toolbar { settingsToolbar }
                }
            }

            Tab("Add", systemImage: "viewfinder", value: .add) {
                Color.clear
            }
        }
        .onChange(of: selection) { _, newValue in
            if newValue == .add {
                isPresentingAdd = true
                selection = .today
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            AddMedicationFlow()
        }
        .sheet(isPresented: $isPresentingSettings) {
            NavigationStack { SettingsView() }
        }
        .task {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-seed-demo-data") {
                try? DemoData.seed(in: modelContext)
            }
#endif
            for medication in medications {
                let plan = NotificationPlanBuilder.make(
                    medication: medication,
                    schedules: schedules,
                    inventoryEvents: inventoryEvents,
                    doseEvents: doseEvents
                )
                await NotificationService.shared.replaceNotifications(for: plan)
            }
        }
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isPresentingSettings = true
            } label: {
                Image(systemName: "person.crop.circle")
            }
            .accessibilityLabel("Settings")
        }
    }
}
