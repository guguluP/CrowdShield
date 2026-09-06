import SwiftUI

/// A small dot + label showing whether real-time push (Phase 4) is
/// currently connected. Deliberately unobtrusive — this is diagnostic
/// information for Command operators, not a primary UI element, since the
/// app's core simulation/dashboard functionality never depends on this
/// being connected (offline-first: see CrowdShieldRealtimeClient).
struct RealtimeStatusIndicator: View {
    let state: WebSocketConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityLabel("Real-time connection: \(label)")
    }

    private var color: Color {
        switch state {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .gray
        case .failed: return .red
        }
    }

    private var label: String {
        switch state {
        case .connected: return "Live"
        case .connecting: return "Connecting"
        case .disconnected: return "Offline"
        case .failed: return "Reconnecting"
        }
    }
}
