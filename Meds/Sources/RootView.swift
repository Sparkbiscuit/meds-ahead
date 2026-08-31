import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case today
    case supply
    case medications
    case add
}

struct RootView: View {
    // Deliberately no `@Query` here. This view owns the TabView, so an observed
    // query would re-render every tab on every ledger write — and these values are
    // only read at launch and on returning to the foreground. Every screen that
    // mutates data replans notifications itself, so a fetch at those two moments
    // is both cheaper and fresher than a query that also invalidates the world.
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
        TabView(selection: tabSelection) {
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
            medications: fetch(Medication.self),
            schedules: fetch(DoseSchedule.self),
            inventoryEvents: fetch(InventoryEvent.self),
            doseEvents: fetch(DoseEvent.self)
        )
        await NotificationService.shared.replaceAllNotifications(for: plans)
    }

    private func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
    }

    private func applyPendingNotificationRoute() {
        guard let destination = MedicationNotificationRouter.shared.consumeDestination() else { return }
        selection = destination
    }

    /// Add is a button wearing a tab's clothes. Committing `.add` as a selection
    /// switched the TabView to an empty tab and straight back while a sheet was
    /// presenting, and the tab it bounced off came back with its pushed detail
    /// view scrolled under the navigation bar and unable to scroll back up.
    /// Refusing the value keeps the person on the tab they were already on.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == .add {
                    isPresentingAdd = true
                } else {
                    selection = newValue
                }
            }
        )
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isPresentingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }
    }
}
