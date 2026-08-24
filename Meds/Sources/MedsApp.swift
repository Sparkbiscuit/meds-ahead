import Foundation
import SwiftData
import SwiftUI

@main
struct MedsApp: App {
    @UIApplicationDelegateAdaptor(MedsAppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer?

    init() {
        // Medication history is entered by hand and cannot be recreated, so the
        // store stays eligible for encrypted device and iCloud backup. It is
        // protected at rest instead, which is what keeps it private on a locked
        // or lost iPhone.
        if let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let protection = FileProtectionType.completeUntilFirstUserAuthentication
            try? FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
            try? FileManager.default.setAttributes(
                [.protectionKey: protection],
                ofItemAtPath: applicationSupport.path
            )
            if let existingFiles = try? FileManager.default.contentsOfDirectory(
                at: applicationSupport,
                includingPropertiesForKeys: nil
            ) {
                for file in existingFiles {
                    try? FileManager.default.setAttributes(
                        [.protectionKey: protection],
                        ofItemAtPath: file.path
                    )
                }
            }
        }
        let schema = Schema([
            Medication.self,
            DoseSchedule.self,
            DoseEvent.self,
            InventoryEvent.self
        ])
#if DEBUG
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
#else
        let isUITesting = false
#endif
        let configuration = ModelConfiguration(
            "Meds",
            schema: schema,
            isStoredInMemoryOnly: isUITesting,
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            modelContainer = container
            appDelegate.modelContainer = container
        } catch {
            modelContainer = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                AppEntryView()
                    .modelContainer(modelContainer)
                    .task { await TipStore.observeTransactions() }
            } else {
                StoreUnavailableView()
            }
        }
    }
}

private struct StoreUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Medication Data Unavailable", systemImage: "lock.trianglebadge.exclamationmark")
        } description: {
            Text("Your medication data could not be opened. It has not been deleted. Unlock this iPhone, close Meds Ahead, and try again.")
        } actions: {
            Link("Contact Support", destination: URL(string: "https://sparkbiscuit.me/meds/support/")!)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

private struct AppEntryView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var completedForcedOnboarding = false

    var body: some View {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
#else
        let arguments: [String] = []
#endif
        let shouldForceOnboarding = arguments.contains("-show-onboarding") && !completedForcedOnboarding
        Group {
            if !shouldForceOnboarding && (hasCompletedOnboarding || arguments.contains("-skip-onboarding")) {
                RootView()
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                    completedForcedOnboarding = true
                }
            }
        }
        .tint(AppTheme.accent)
    }
}
