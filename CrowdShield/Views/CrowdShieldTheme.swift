import SwiftUI

/// CrowdShield visual language: atmospheric dark, liquid glass, role-aware
/// accents, and SF-style type. Shared so every surface reads as one product.
enum CrowdShieldTheme {
    static let publicAccent = Color(red: 0.20, green: 0.82, blue: 0.92)
    static let commandAccent = Color(red: 1.00, green: 0.62, blue: 0.22)
    static let canvasTop = Color(red: 0.04, green: 0.06, blue: 0.09)
    static let canvasBottom = Color(red: 0.02, green: 0.02, blue: 0.04)
    static let hairline = Color.white.opacity(0.10)

    static func accent(for role: UserRole?) -> Color {
        role == .commandControl ? commandAccent : publicAccent
    }
}

struct CrowdShieldAtmosphere: View {
    var accent: Color = CrowdShieldTheme.publicAccent

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [CrowdShieldTheme.canvasTop, CrowdShieldTheme.canvasBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [accent.opacity(0.22), Color.clear],
                center: UnitPoint(x: 0.15, y: 0.08),
                startRadius: 20,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color(red: 0.18, green: 0.12, blue: 0.42).opacity(0.35), Color.clear],
                center: UnitPoint(x: 0.92, y: 0.22),
                startRadius: 10,
                endRadius: 380
            )
            RadialGradient(
                colors: [accent.opacity(0.08), Color.clear],
                center: UnitPoint(x: 0.5, y: 1.05),
                startRadius: 40,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

struct CrowdShieldFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(CrowdShieldTheme.hairline, lineWidth: 1)
            )
    }
}

struct CrowdShieldPrimaryButtonStyle: ButtonStyle {
    var tint: Color
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.35))
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

extension View {
    func crowdShieldField() -> some View {
        modifier(CrowdShieldFieldStyle())
    }

    func crowdShieldScreenBackground(accent: Color = CrowdShieldTheme.publicAccent) -> some View {
        background { CrowdShieldAtmosphere(accent: accent) }
    }
}
