import Foundation
import SwiftData
import SwiftUI

@main
struct MedsApp: App {
    private let modelContainer: ModelContainer

    init() {
        if var applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: applicationSupport.path
            )
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
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create the protected local medication store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppEntryView()
        }
        .modelContainer(modelContainer)
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
