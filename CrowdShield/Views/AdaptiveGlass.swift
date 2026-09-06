import SwiftUI

/// Applies Liquid Glass (iOS 26+/macOS 26+) where available, falling back to
/// the previous `.ultraThinMaterial` treatment on older OS versions so the
/// app still looks correct on devices/simulators that can't run the new
/// material. Centralized here so every card across the app picks up the
/// current-generation Apple design language consistently.
extension View {
    @ViewBuilder
    func adaptiveGlassCard(cornerRadius: CGFloat = 16, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint.opacity(0.14)), in: .rect(cornerRadius: cornerRadius, style: .continuous))
            } else {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }
}
