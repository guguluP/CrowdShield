import Foundation

/// A short rolling window of a zone's recent state, used to detect trends
/// (rising density, reversing flow) rather than just instantaneous snapshots.
/// This is what lets CrowdShield claim genuine *prediction* rather than a
/// static threshold classifier.
struct ZoneHistoryPoint {
    let density: Double
    let flowDirection: Double
    let movementSpeed: Double
    let timestamp: Date
}

final class ZoneHistoryTracker {
    private var history: [UUID: [ZoneHistoryPoint]] = [:]
    private let maxSamples = 8

    func record(_ zone: CrowdZone) {
        var points = history[zone.id] ?? []
        points.append(ZoneHistoryPoint(
            density: zone.density,
            flowDirection: zone.flowDirection,
            movementSpeed: zone.movementSpeed,
            timestamp: zone.lastUpdated
        ))
        if points.count > maxSamples {
            points.removeFirst(points.count - maxSamples)
        }
        history[zone.id] = points
    }

    func history(for zoneID: UUID) -> [ZoneHistoryPoint] {
        history[zoneID] ?? []
    }

    /// Density trend in people/m² per second over the recorded window.
    /// Positive = getting worse, used to drive predictedCrushInMinutes.
    func densityTrend(for zoneID: UUID) -> Double {
        guard let points = history[zoneID], points.count >= 2,
              let first = points.first, let last = points.last else { return 0 }
        let dt = last.timestamp.timeIntervalSince(first.timestamp)
        guard dt > 0 else { return 0 }
        return (last.density - first.density) / dt
    }
}

enum FlowIssueKind: String {
    case reverseMovement = "Reverse Crowd Movement"
    case routeBlockage = "Route Blockage"
    case rapidSurge = "Sudden Crowd Surge"
}

struct FlowIssue: Identifiable {
    let id = UUID()
    let zoneID: UUID
    let zoneName: String
    let kind: FlowIssueKind
    let detail: String
    let severity: RiskLevel
}

/// Analyzes recent zone history to surface the specific dangerous patterns the
/// brief calls out: reverse crowd movement, route blockage, and sudden surge —
/// which a single instantaneous density reading cannot distinguish.
enum FlowAnalysisEngine {

    static func detectIssues(currentZones: [CrowdZone], tracker: ZoneHistoryTracker) -> [FlowIssue] {
        var issues: [FlowIssue] = []

        for zone in currentZones {
            let points = tracker.history(for: zone.id)
            guard points.count >= 3 else { continue }

            // Reverse movement: flow direction has swung by more than 120° within
            // the recent window while density stayed high — people are being
            // pushed back against the general flow, a classic stampede precursor.
            if let earliest = points.first, let latest = points.last {
                let delta = angularDifference(earliest.flowDirection, latest.flowDirection)
                if delta > 120, zone.density > 3.0 {
                    issues.append(FlowIssue(
                        zoneID: zone.id,
                        zoneName: zone.name,
                        kind: .reverseMovement,
                        detail: "Flow direction shifted \(Int(delta))° in \(zone.name) — crowd may be pushing back against incoming flow.",
                        severity: zone.density > 5 ? .critical : .high
                    ))
                }
            }

            // Route blockage: movement speed has collapsed toward zero while
            // density keeps climbing — people have stopped moving forward.
            let recentSpeeds = points.suffix(4).map(\.movementSpeed)
            let avgRecentSpeed = recentSpeeds.reduce(0, +) / Double(max(recentSpeeds.count, 1))
            if avgRecentSpeed < 0.25, zone.density > 4.0 {
                issues.append(FlowIssue(
                    zoneID: zone.id,
                    zoneName: zone.name,
                    kind: .routeBlockage,
                    detail: "\(zone.name) has near-zero movement (\(String(format: "%.2f", avgRecentSpeed)) m/s) at high density — path likely blocked.",
                    severity: .high
                ))
            }

            // Rapid surge: density trend is sharply positive.
            let trend = tracker.densityTrend(for: zone.id)
            if trend > 0.6 {
                issues.append(FlowIssue(
                    zoneID: zone.id,
                    zoneName: zone.name,
                    kind: .rapidSurge,
                    detail: "\(zone.name) density rising at \(String(format: "%.1f", trend)) p/m² per second — sudden surge detected.",
                    severity: trend > 1.2 ? .critical : .high
                ))
            }
        }

        return issues
    }

    private static func angularDifference(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
        return diff > 180 ? 360 - diff : diff
    }
}
