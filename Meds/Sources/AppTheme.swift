import SwiftUI

enum AppTheme {
    static let accent = Color.accentColor
    static let canvas = Color(uiColor: .systemGroupedBackground)

    static let medicationColors: [Color] = [
        Color(red: 0.16, green: 0.46, blue: 0.52),
        Color(red: 0.24, green: 0.48, blue: 0.35),
        Color(red: 0.47, green: 0.34, blue: 0.66),
        Color(red: 0.78, green: 0.39, blue: 0.25),
        Color(red: 0.76, green: 0.57, blue: 0.18),
        Color(red: 0.32, green: 0.42, blue: 0.72)
    ]

    static func color(for medication: Medication) -> Color {
        medicationColors[abs(medication.accentIndex) % medicationColors.count]
    }
}

extension Animation {
    static let medsSpring = Animation.spring(response: 0.38, dampingFraction: 1)
}

struct CanvasBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppTheme.canvas
            RadialGradient(
                colors: [AppTheme.accent.opacity(colorScheme == .dark ? 0.12 : 0.09), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 430
            )
        }
        .ignoresSafeArea()
    }
}

struct CardSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(
                reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)) : AnyShapeStyle(.background),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.primary.opacity(0.055), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.045), radius: 18, y: 8)
    }
}

extension View {
    func cardSurface() -> some View { modifier(CardSurface()) }
}
