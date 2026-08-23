import Foundation
import SwiftData
import SwiftUI

@main
struct MedsApp: App {
    @UIApplicationDelegateAdaptor(MedsAppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer?

    init() {
        if var applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
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
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? applicationSupport.setResourceValues(values)
        }
        let schema = Schema([
            Medication.self,
            DoseSchedule.self,
            DoseEvent.self,
            InventoryEvent.self
        ])
        let configuration = ModelConfiguration(
            "Meds",
            schema: schema,
            isStoredInMemoryOnly: ProcessInfo.processInfo.arguments.contains("-ui-testing"),
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
            Text("Your medication data could not be opened. It has not been deleted. Unlock this iPhone, close Meds, and try again.")
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
        let arguments = ProcessInfo.processInfo.arguments
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
