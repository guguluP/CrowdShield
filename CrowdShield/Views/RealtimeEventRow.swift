import SwiftUI

/// Renders one RealtimePush in the Live Activity feed. Reads fields
/// defensively from the loose `raw` payload (see RealtimePush) since these
/// come straight from the backend's DynamoDB Streams broadcast rather than
/// a strongly-typed model — a missing or renamed field degrades to a
/// generic label rather than crashing or showing "nil".
struct RealtimeEventRow: View {
    let event: RealtimePush

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(Circle().fill(iconColor.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(relativeTime)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .adaptiveGlassCard(cornerRadius: 12)
        .padding(.horizontal)
    }

    private var icon: String {
        switch event.resource {
        case .venueState: return "chart.bar.fill"
        case .alert: return "exclamationmark.triangle.fill"
        case .incident: return "person.fill.questionmark"
        case .recommendation: return "checkmark.seal.fill"
        case .unknown: return "dot.radiowaves.up.forward"
        }
    }

    private var iconColor: Color {
        switch event.resource {
        case .venueState: return CrowdShieldTheme.publicAccent
        case .alert: return .orange
        case .incident: return .red
        case .recommendation: return .green
        case .unknown: return .gray
        }
    }

    private var title: String {
        switch event.resource {
        case .venueState: return "Venue state updated"
        case .alert: return (event.raw["severity"] as? String).map { "Alert (\($0.capitalized))" } ?? "New alert"
        case .incident: return "Incident reported"
        case .recommendation: return "Recommendation acknowledged"
        case .unknown: return "Update received"
        }
    }

    private var subtitle: String? {
        switch event.resource {
        case .venueState:
            let hotspots = event.raw["hotspots"] as? [String] ?? []
            return hotspots.isEmpty ? nil : "Hotspots: \(hotspots.joined(separator: ", "))"
        case .alert:
            return event.raw["message"] as? String
        case .incident:
            return event.raw["description"] as? String
        case .recommendation:
            return event.raw["action"] as? String
        case .unknown:
            return nil
        }
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: event.receivedAt, relativeTo: Date())
    }
}
