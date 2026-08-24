import SwiftUI

struct OnboardingView: View {
    let completion: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            symbol: "pills.fill",
            eyebrow: "A calmer medication routine",
            title: "Know what runs out next.",
            message: "Meds Ahead brings schedules, dose history, and your real supply into one clear place.",
            accent: .blue
        ),
        OnboardingPage(
            symbol: "viewfinder",
            eyebrow: "Fast, not careless",
            title: "Scan. Then confirm.",
            message: "Text and barcodes are recognized on your iPhone. You review every detail before it becomes part of your routine.",
            accent: .mint
        ),
        OnboardingPage(
            symbol: "lock.shield.fill",
            eyebrow: "Private by design",
            title: "Your medications stay yours.",
            message: "No account, advertising, analytics, or cloud medication database. Label photos are not retained.",
            accent: .indigo
        )
    ]

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip", action: completion)
                        .font(.subheadline.weight(.semibold))
                        .opacity(page == pages.count - 1 ? 0 : 1)
                        .accessibilityHidden(page == pages.count - 1)
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        OnboardingPageView(page: item, reduceMotion: reduceMotion)
                            .tag(index)
                            .padding(.horizontal, 26)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? AppTheme.accent : .secondary.opacity(0.22))
                            .frame(width: index == page ? 24 : 8, height: 8)
                    }
                }
                .animation(reduceMotion ? nil : .medsSpring, value: page)
                .padding(.bottom, 24)

                Button {
                    if page == pages.count - 1 {
                        completion()
                    } else {
                        withAnimation(reduceMotion ? nil : .medsSpring) { page += 1 }
                    }
                } label: {
                    Text(page == pages.count - 1 ? "Get Started" : "Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
            }
        }
    }
}

private struct OnboardingPage: Hashable {
    let symbol: String
    let eyebrow: String
    let title: String
    let message: String
    let accent: Color
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(page.accent.opacity(0.12))
                    .frame(width: 180, height: 180)
                Circle()
                    .stroke(page.accent.opacity(0.16), lineWidth: 1)
                    .frame(width: 226, height: 226)
                Image(systemName: page.symbol)
                    .font(.system(size: 72, weight: .medium))
                    .foregroundStyle(page.accent.gradient)
                    .symbolEffect(.breathe, options: reduceMotion ? .nonRepeating : .repeat(2))
            }
            .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(page.eyebrow.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(AppTheme.accent)
                Text(page.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(page.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}
