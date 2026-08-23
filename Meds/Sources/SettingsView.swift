import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @State private var notificationStatus = "Checking…"
    @State private var showingSafety = false
    @State private var showingPrivacy = false

    var body: some View {
        List {
            Section {
                LabeledContent("Notifications", value: notificationStatus)
                Button("Review Notification Access") {
                    Task { await reviewNotificationAccess() }
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Meds uses local notifications. Delivery also depends on your iPhone notification and Focus settings.")
            }

            Section("About") {
                Button("Privacy by Design") { showingPrivacy = true }
                Button("Safety & Intended Use") { showingSafety = true }
                Link("Privacy Policy", destination: URL(string: "https://sparkbiscuit.me/meds/privacy/")!)
                Link("Support", destination: URL(string: "https://sparkbiscuit.me/meds/support/")!)
                LabeledContent("Version", value: appVersion)
            }

            Section {
                Button("Show Introduction Again") {
                    hasCompletedOnboarding = false
                    dismiss()
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task { await refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshNotificationStatus() }
        }
        .sheet(isPresented: $showingPrivacy) {
            InformationSheet(
                title: "Private by Design",
                symbol: "lock.shield.fill",
                paragraphs: [
                    "Medication records stay in the protected local app container. Meds has no account, advertising, analytics, or cloud medication service.",
                    "Label photos are processed on device and are not retained. Pharmacy links found in codes are never opened automatically.",
                    "Deleting a medication removes its schedule, inventory ledger, and dose history from this iPhone."
                ]
            )
        }
        .sheet(isPresented: $showingSafety) {
            InformationSheet(
                title: "Organization, Not Medical Advice",
                symbol: "checkmark.shield.fill",
                paragraphs: [
                    "Meds records information you enter or confirm. It does not prescribe, diagnose, recommend a dose, or decide when a pharmacy can fill a prescription.",
                    "Always follow the current prescription label and instructions from your clinician or pharmacist.",
                    "Forecasts depend on the counts, schedules, and logs you provide. When information is missing, Meds shows uncertainty instead of inventing precision."
                ]
            )
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    @MainActor
    private func reviewNotificationAccess() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .denied,
           let url = URL(string: UIApplication.openSettingsURLString) {
            await UIApplication.shared.open(url)
            return
        }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshNotificationStatus()
    }

    @MainActor
    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Off"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }
}

private struct InformationSheet: View {
    let title: String
    let symbol: String
    let paragraphs: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: symbol)
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityHidden(true)
                    ForEach(paragraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .font(.body)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
