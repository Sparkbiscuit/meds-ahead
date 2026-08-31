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
    @State private var showingStory = false
    @State private var showingTips = false
    @State private var tipAvailability: TipAvailability = .loading

    /// App Review must always be able to find the in-app purchases, so the tip row
    /// is present in every state rather than appearing only once StoreKit answers.
    private enum TipAvailability {
        case loading
        case available([Product])
        case unavailable
    }

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

            Section {
                switch tipAvailability {
                case .loading:
                    HStack {
                        Label("Leave an Optional Tip", systemImage: "heart.fill")
                        Spacer()
                        ProgressView()
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Leave an optional tip, loading")
                case let .available(products):
                    Button {
                        showingTips = true
                    } label: {
                        Label("Leave an Optional Tip", systemImage: "heart.fill")
                    }
                    .disabled(products.isEmpty)
                case .unavailable:
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Tips Are Unavailable", systemImage: "heart.slash")
                        Text("The App Store did not return the tip options on this device.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                    Button("Try Again") {
                        Task { await refreshTipProducts() }
                    }
                }
            } header: {
                Text("Support Meds Ahead")
            } footer: {
                Text("Meds Ahead is fully functional and free for everyone. Tips support continued improvements and never unlock features.")
            }

            Section("About") {
                Button("Why I Made Meds Ahead") { showingStory = true }
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
        .sheet(isPresented: $showingStory) {
            InformationSheet(
                title: "Why I Made Meds Ahead",
                symbol: "heart.fill",
                paragraphs: [
                    "My mother was managing more than a dozen medications for my 9-year-old brother Lukas through his lung transplant care. Refills came due on different days, in different amounts, from different places. Running out of one of them was not a small problem.",
                    "Every app we tried was built around reminders, telling you to take something at eight in the morning. None of them answered the question she was actually asking, standing at the pharmacy counter or lying awake on a Sunday night: what runs out next, and when do I have to do something about it?",
                    "So I built the app we needed. Meds Ahead keeps an honest count of what is actually on hand, asks you to confirm everything before it believes it, and tells you plainly which medication needs attention next. It has no account, no advertising, and no analytics, and your medication information never leaves your iPhone.",
                    "If you are keeping track of medications for someone you love, I hope this takes one thing off your plate."
                ],
                signature: "Nick Christoforakis"
            )
        }
        .sheet(isPresented: $showingPrivacy) {
            InformationSheet(
                title: "Private by Design",
                symbol: "lock.shield.fill",
                paragraphs: [
                    "Medication records stay in the protected local app container, readable only after you unlock this iPhone. Meds Ahead has no account, advertising, analytics, or cloud medication service.",
                    "Your records are included in your own encrypted device and iCloud backups, so the history you build survives restoring or replacing an iPhone.",
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
            if case let .available(products) = tipAvailability {
                TipJarView(products: products)
            }
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
        tipAvailability = .loading
        let products = await TipStore.availableProducts()
        tipAvailability = products.isEmpty ? .unavailable : .available(products)
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
    var signature: String? = nil
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
                    if let signature {
                        Text(signature)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
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
