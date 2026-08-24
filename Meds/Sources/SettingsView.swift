import StoreKit
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
    @State private var showingTips = false
    @State private var tipProducts: [Product] = []

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
                Text("Meds Ahead uses local notifications. Delivery also depends on your iPhone notification and Focus settings.")
            }

            if !tipProducts.isEmpty {
                Section {
                    Button {
                        showingTips = true
                    } label: {
                        Label("Leave an Optional Tip", systemImage: "heart.fill")
                    }
                } header: {
                    Text("Support Meds Ahead")
                } footer: {
                    Text("Meds Ahead is fully functional and free for everyone. Tips support continued improvements and never unlock features.")
                }
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
        .task {
            async let notificationRefresh: Void = refreshNotificationStatus()
            async let productRefresh: Void = refreshTipProducts()
            _ = await (notificationRefresh, productRefresh)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshNotificationStatus() }
        }
        .sheet(isPresented: $showingPrivacy) {
            InformationSheet(
                title: "Private by Design",
                symbol: "lock.shield.fill",
                paragraphs: [
                    "Medication records stay in the protected local app container. Meds Ahead has no account, advertising, analytics, or cloud medication service.",
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
                    "Meds Ahead records information you enter or confirm. It does not prescribe, diagnose, recommend a dose, or decide when a pharmacy can fill a prescription.",
                    "Always follow the current prescription label and instructions from your clinician or pharmacist.",
                    "Forecasts depend on the counts, schedules, and logs you provide. When information is missing, Meds Ahead shows uncertainty instead of inventing precision.",
                    "This product uses publicly available data courtesy of the U.S. National Library of Medicine (NLM), National Institutes of Health, Department of Health and Human Services; NLM is not responsible for the product and does not endorse or recommend this or any other product."
                ]
            )
        }
        .sheet(isPresented: $showingTips) {
            TipJarView(products: tipProducts)
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

    @MainActor
    private func refreshTipProducts() async {
        tipProducts = await TipStore.availableProducts()
    }
}

private struct TipJarView: View {
    let products: [Product]
    @Environment(\.dismiss) private var dismiss
    @State private var purchasingProductID: String?
    @State private var resultMessage: String?
    @State private var purchaseFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: resultMessage == nil ? "heart.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 54, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)

                    VStack(spacing: 8) {
                        Text(resultMessage == nil ? "Support Meds Ahead" : (purchaseFailed ? "Tip Unavailable" : "Thank You"))
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text(resultMessage ?? "If Meds Ahead makes medication management a little easier, you can leave an optional tip toward its continued development.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if resultMessage == nil {
                        VStack(spacing: 10) {
                            ForEach(products, id: \.id) { product in
                                Button {
                                    Task { await purchase(product) }
                                } label: {
                                    HStack {
                                        Text(TipStore.displayNames[product.id] ?? product.displayName)
                                        Spacer()
                                        if purchasingProductID == product.id {
                                            ProgressView()
                                        } else {
                                            Text(product.displayPrice)
                                                .fontWeight(.semibold)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(purchasingProductID != nil)
                            }
                        }
                    }

                    Text("Tips are processed by Apple, are not recurring, and do not unlock app features.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }
            .navigationTitle("Optional Tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @MainActor
    private func purchase(_ product: Product) async {
        purchasingProductID = product.id
        defer { purchasingProductID = nil }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseFailed = true
                    resultMessage = "Apple could not verify this purchase. You were not credited with a completed tip."
                    return
                }
                await transaction.finish()
                purchaseFailed = false
                resultMessage = "Your support helps keep Meds Ahead thoughtful, private, and improving."
            case .pending:
                purchaseFailed = false
                resultMessage = "Apple is still processing this tip. It will finish automatically after approval."
            case .userCancelled:
                break
            @unknown default:
                purchaseFailed = true
                resultMessage = "The tip could not be completed right now. Please try again later."
            }
        } catch {
            purchaseFailed = true
            resultMessage = "The tip could not be completed right now. Please try again later."
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
