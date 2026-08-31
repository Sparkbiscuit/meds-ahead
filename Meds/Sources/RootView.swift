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
    @Environment(\.scenePhase) private var scenePhase
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
        .onChange(of: selection) { oldValue, newValue in
            if newValue == .add {
                isPresentingAdd = true
                // Return to the tab the person was on, so closing the add sheet
                // does not teleport them from Supply or Medications to Today.
                selection = oldValue == .add ? .today : oldValue
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            AddMedicationFlow()
        }
        .sheet(isPresented: $isPresentingSettings) {
            NavigationStack { SettingsView() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .medicationNotificationRouteDidChange)) { _ in
            applyPendingNotificationRoute()
        }
        .task {
            applyPendingNotificationRoute()
            MedicationListPDFRenderer.removePreviousExport()
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-seed-demo-data") {
                try? DemoData.seed(
                    in: modelContext,
                    backdatingSchedulesByDays: ProcessInfo.processInfo.arguments.contains("-seed-missed-doses") ? 3 : 0
                )
            }
#endif
            await replanNotifications()
        }
        // `task` runs once for the life of this view, which is not the same thing as
        // once per use: coming back after days in the background never re-ran it.
        // Dose reminders repeat and survive that, but a refill alert is a one-shot
        // date whose replacement is only ever scheduled while the app is open, so
        // lead time quietly stopped arriving for anyone who left the app closed.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await replanNotifications() }
        }
    }

    private func replanNotifications() async {
        let plans = NotificationPlanBuilder.makeAll(
            medications: medications,
            schedules: schedules,
            inventoryEvents: inventoryEvents,
            doseEvents: doseEvents
        )
        await NotificationService.shared.replaceAllNotifications(for: plans)
    }

    private func applyPendingNotificationRoute() {
        guard let destination = MedicationNotificationRouter.shared.consumeDestination() else { return }
        selection = destination
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
