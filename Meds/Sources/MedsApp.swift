import Foundation
import SwiftData
import SwiftUI

@main
struct MedsApp: App {
    @UIApplicationDelegateAdaptor(MedsAppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer?

    init() {
        let schema = Schema([
            Medication.self,
            DoseSchedule.self,
            DoseEvent.self,
            InventoryEvent.self
        ])
        // The store lives in the app group container so the widgets can read
        // it; a store from 1.0 is moved there once, before it is opened.
        // UI tests keep their in-memory store and never touch either location.
#if DEBUG
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        let storeURL = isUITesting ? nil : Self.resolveStoreURL()
#else
        let isUITesting = false
        let storeURL = Self.resolveStoreURL()
#endif
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration("Meds", schema: schema, url: storeURL, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(
                "Meds",
                schema: schema,
                isStoredInMemoryOnly: isUITesting,
                cloudKitDatabase: .none
            )
        }
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            modelContainer = container
            appDelegate.modelContainer = container
            if let storeURL { Self.protect(storeURL) }
        } catch {
            modelContainer = nil
        }
    }

    /// The shared store, with a legacy store moved into it first. When the
    /// group container is unavailable, or the move could not be trusted, the
    /// store stays where 1.0 kept it and the widgets simply have nothing to show.
    private static func resolveStoreURL() -> URL? {
        guard let shared = StoreLocation.sharedURL else { return StoreLocation.legacyURL }
        if let legacy = StoreLocation.legacyURL {
            if case .keptLegacy = StoreLocation.migrate(from: legacy, to: shared) {
                return legacy
            }
        }
        return shared
    }

    /// Medication history is entered by hand and cannot be recreated, so the
    /// store stays eligible for encrypted device and iCloud backup. It is
    /// protected at rest instead, which is what keeps it private on a locked or
    /// lost iPhone; the class still lets a reminder action log a dose while the
    /// iPhone is locked, and lets a widget read the store after the first unlock.
    private static func protect(_ storeURL: URL) {
        let protection = FileProtectionType.completeUntilFirstUserAuthentication
        try? FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: storeURL.deletingLastPathComponent().path)
        for suffix in StoreLocation.sidecarSuffixes {
            try? FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: storeURL.path + suffix)
        }
        if let legacy = StoreLocation.legacyURL {
            for suffix in StoreLocation.sidecarSuffixes {
                try? FileManager.default.setAttributes(
                    [.protectionKey: protection],
                    ofItemAtPath: legacy.path + StoreLocation.retiredSuffix + suffix
                )
            }
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
