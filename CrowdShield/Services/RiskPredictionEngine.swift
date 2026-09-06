import Foundation
import CoreLocation
import _LocationEssentials

// MARK: - Stampede & Panic Models

/// Explicit stampede-likelihood prediction for one zone (0.0 – 1.0).
/// Combines density, mobility collapse, flow anomalies, and short-term trend
/// into a single operator-facing probability rather than leaving it implicit
/// inside riskScore.
struct StampedePrediction: Identifiable, Equatable {
    let id: UUID           // zone id
    let zoneName: String
    /// Probability-like score in [0, 1] that a stampede/crush develops in this zone
    /// within the next few minutes if no intervention occurs.
    let likelihood: Double
    let primaryDrivers: [String]
    let estimatedMinutesToCritical: Int?

    var level: RiskLevel {
        switch likelihood {
        case 0.0..<0.25: return .safe
        case 0.25..<0.5: return .moderate
        case 0.5..<0.75: return .high
        default: return .critical
        }
    }
}

/// Panic intensity at a zone and how it is expected to spread through the venue graph.
struct PanicState: Identifiable, Equatable {
    let id: UUID           // zone id
    let zoneName: String
    /// Current panic intensity in [0, 1]. Seeds from high density, reverse flow,
    /// surges, and citizen "Panic" reports; then propagates to neighbors.
    var intensity: Double
    /// Zones this panic is projected to reach next (ordered by expected arrival strength).
    var projectedSpread: [PanicSpreadHop]
    var lastUpdated: Date
}

struct PanicSpreadHop: Equatable {
    let zoneName: String
    /// Expected intensity contribution arriving at the neighbor in the next tick window.
    let incomingIntensity: Double
    /// Rough seconds until that contribution becomes material, based on edge distance.
    let etaSeconds: Double
}

struct VenueRiskForecast: Equatable {
    /// Max stampede likelihood across all zones.
    var overallStampedeLikelihood: Double
    var perZoneStampede: [StampedePrediction]
    var panicStates: [PanicState]
    /// Zones where panic is actively spreading outward this cycle.
    var activePropagationFronts: [String]
    var generatedAt: Date
}

// MARK: - Engine

/// Computes the two risk predictions called out in the TechNova brief that were
/// previously missing as first-class outputs:
///   1. Stampede likelihood
///   2. Panic propagation across connected zones
///
/// Uses the same venue graph as evacuation routing so propagation follows
/// walkable paths, not arbitrary geographic distance.
enum RiskPredictionEngine {

    /// Density (p/m²) above which crush mechanics dominate over free movement.
    private static let criticalDensity: Double = 6.0
    /// Movement speed (m/s) below which a dense crowd is effectively locked.
    private static let lockedSpeed: Double = 0.35
    /// Panic decay per simulation tick when no local stressors remain.
    private static let panicDecayPerTick: Double = 0.08
    /// Fraction of a zone's panic that can leak to each neighbor per tick.
    private static let propagationFraction: Double = 0.22
    /// Cap so a single zone cannot ignite the whole venue in one tick.
    private static let maxIncomingPerTick: Double = 0.35

    // MARK: Public entry

    /// Full forecast for the current venue state. Call once per simulation tick
    /// after zones and flow issues have been updated.
    static func forecast(
        zones: [CrowdZone],
        flowIssues: [FlowIssue],
        tracker: ZoneHistoryTracker,
        previousPanic: [UUID: Double],
        graph: VenueGraph = .festivalGrounds,
        recentIncidents: [IncidentReport] = []
    ) -> VenueRiskForecast {
        let stampede = zones.map { zone in
            stampedePrediction(
                for: zone,
                flowIssues: flowIssues.filter { $0.zoneID == zone.id },
                tracker: tracker
            )
        }

        let panic = propagatePanic(
            zones: zones,
            flowIssues: flowIssues,
            previousPanic: previousPanic,
            graph: graph,
            recentIncidents: recentIncidents
        )

        let fronts = panic
            .filter { !$0.projectedSpread.isEmpty && $0.intensity >= 0.35 }
            .map(\.zoneName)

        let overall = stampede.map(\.likelihood).max() ?? 0

        return VenueRiskForecast(
            overallStampedeLikelihood: overall,
            perZoneStampede: stampede.sorted { $0.likelihood > $1.likelihood },
            panicStates: panic.sorted { $0.intensity > $1.intensity },
            activePropagationFronts: fronts,
            generatedAt: Date()
        )
    }

    // MARK: - Stampede likelihood

    /// Weighted blend of crush precursors. Weights tuned so a zone needs
    /// several concurrent signals (not just high density) to score near 1.0 —
    /// reducing single-signal false alarms.
    private static func stampedePrediction(
        for zone: CrowdZone,
        flowIssues: [FlowIssue],
        tracker: ZoneHistoryTracker
    ) -> StampedePrediction {
        var drivers: [String] = []
        var score = 0.0

        // 1. Density relative to critical crush threshold (0 – 0.35)
        let densityRatio = min(1.0, zone.density / criticalDensity)
        let densityComponent = densityRatio * 0.35
        score += densityComponent
        if densityRatio > 0.7 {
            drivers.append(String(format: "Density %.1f p/m²", zone.density))
        }

        // 2. Mobility collapse — slow movement at high density (0 – 0.25)
        if zone.density > 3.5 {
            let speedCollapse = max(0, 1.0 - (zone.movementSpeed / 1.2))
            let mobilityComponent = speedCollapse * 0.25
            score += mobilityComponent
            if zone.movementSpeed < lockedSpeed {
                drivers.append(String(format: "Near-zero movement (%.2f m/s)", zone.movementSpeed))
            }
        }

        // 3. Bottleneck multiplier (0 – 0.15)
        if zone.isBottleneck {
            score += 0.15
            drivers.append("Active bottleneck")
        }

        // 4. Flow anomalies in this zone (0 – 0.20)
        let hasReverse = flowIssues.contains { $0.kind == .reverseMovement }
        let hasBlockage = flowIssues.contains { $0.kind == .routeBlockage }
        let hasSurge = flowIssues.contains { $0.kind == .rapidSurge }
        if hasReverse {
            score += 0.10
            drivers.append("Reverse crowd movement")
        }
        if hasBlockage {
            score += 0.06
            drivers.append("Route blockage")
        }
        if hasSurge {
            score += 0.04
            drivers.append("Rapid density surge")
        }

        // 5. Short-term density trend — rising is worse (0 – 0.12)
        let trend = tracker.densityTrend(for: zone.id)
        if trend > 0.15 {
            let trendComponent = min(0.12, trend * 0.08)
            score += trendComponent
            drivers.append(String(format: "Rising +%.2f p/m²/s", trend))
        }

        // 6. Existing risk score as a soft prior (0 – 0.08)
        score += zone.riskScore * 0.08

        let likelihood = min(1.0, max(0.0, score))

        // ETA: only meaningful when likelihood is elevated and density is climbing
        // or already critical.
        let eta: Int?
        if likelihood >= 0.5 {
            let remaining = max(0.1, criticalDensity - zone.density)
            let climbRate = max(0.05, trend)
            // Convert trend (per second) into minutes, clamp to a useful command window.
            let minutes = Int((remaining / climbRate) / 60.0)
            if trend > 0.1 {
                eta = max(2, min(20, minutes == 0 ? 3 : minutes))
            } else if likelihood >= 0.75 {
                eta = Int.random(in: 3...8) // locked high-risk: short window
            } else {
                eta = Int.random(in: 8...15)
            }
        } else {
            eta = nil
        }

        if drivers.isEmpty && likelihood > 0.15 {
            drivers.append("Elevated composite risk")
        }

        return StampedePrediction(
            id: zone.id,
            zoneName: zone.name,
            likelihood: likelihood,
            primaryDrivers: drivers,
            estimatedMinutesToCritical: eta
        )
    }

    // MARK: - Panic propagation

    /// Seeds panic from local stressors, decays calm zones, then diffuses
    /// intensity along the venue graph to neighbors (distance-weighted).
    private static func propagatePanic(
        zones: [CrowdZone],
        flowIssues: [FlowIssue],
        previousPanic: [UUID: Double],
        graph: VenueGraph,
        recentIncidents: [IncidentReport]
    ) -> [PanicState] {
        let zonesByName = Dictionary(uniqueKeysWithValues: zones.map { ($0.name, $0) })
        var intensity: [UUID: Double] = [:]

        // --- Seed / update local intensity ---
        for zone in zones {
            var local = previousPanic[zone.id] ?? 0.0

            // Natural decay toward calm when stressors ease.
            local = max(0, local - panicDecayPerTick)

            // Density stress
            if zone.density > 5.0 {
                local += min(0.25, (zone.density - 5.0) * 0.08)
            }
            // Bottleneck / locked flow
            if zone.isBottleneck {
                local += 0.12
            }
            if zone.movementSpeed < lockedSpeed && zone.density > 4.0 {
                local += 0.10
            }
            // Flow anomalies are strong panic triggers
            for issue in flowIssues where issue.zoneID == zone.id {
                switch issue.kind {
                case .reverseMovement: local += 0.18
                case .routeBlockage:   local += 0.14
                case .rapidSurge:      local += 0.12
                }
            }
            // Citizen panic reports near this zone (last few minutes)
            let panicReports = recentIncidents.filter {
                $0.type.localizedCaseInsensitiveContains("panic")
                    && $0.timestamp.timeIntervalSinceNow > -300
            }
            if !panicReports.isEmpty {
                // Boost the zone closest to each report, or all if no coordinate.
                for report in panicReports {
                    if let coord = report.coordinate {
                        let dlat = zone.coordinate.latitude - coord.latitude
                        let dlon = zone.coordinate.longitude - coord.longitude
                        let dist = (dlat * dlat + dlon * dlon).squareRoot()
                        if dist < 0.003 { // ~300m-ish at this latitude scale
                            local += 0.20
                        }
                    } else {
                        local += 0.05
                    }
                }
            }

            intensity[zone.id] = min(1.0, local)
        }

        // --- Propagate along venue graph ---
        // Build undirected adjacency with distance.
        var adjacency: [String: [(neighbor: String, distance: Double)]] = [:]
        for edge in graph.connections {
            adjacency[edge.from, default: []].append((edge.to, edge.baseDistance))
            adjacency[edge.to, default: []].append((edge.from, edge.baseDistance))
        }

        var incoming: [UUID: Double] = [:]
        var projected: [UUID: [PanicSpreadHop]] = [:]

        for zone in zones {
            let sourceIntensity = intensity[zone.id] ?? 0
            guard sourceIntensity >= 0.25 else { continue }

            let neighbors = adjacency[zone.name] ?? []
            for neighbor in neighbors {
                guard let neighborZone = zonesByName[neighbor.neighbor] else { continue }
                // Closer edges transmit panic faster and stronger.
                let distanceFactor = max(0.25, 1.0 - (neighbor.distance / 150.0))
                let leak = sourceIntensity * propagationFraction * distanceFactor
                let capped = min(maxIncomingPerTick, leak)

                incoming[neighborZone.id, default: 0] += capped

                let eta = neighbor.distance / max(0.4, zone.movementSpeed)
                projected[zone.id, default: []].append(
                    PanicSpreadHop(
                        zoneName: neighbor.neighbor,
                        incomingIntensity: capped,
                        etaSeconds: eta
                    )
                )
            }
        }

        // Apply incoming panic after computing all leaks (simultaneous update).
        for zone in zones {
            let add = incoming[zone.id] ?? 0
            intensity[zone.id] = min(1.0, (intensity[zone.id] ?? 0) + add)
        }

        // Build result states
        return zones.map { zone in
            let hops = (projected[zone.id] ?? []).sorted { $0.incomingIntensity > $1.incomingIntensity }
            return PanicState(
                id: zone.id,
                zoneName: zone.name,
                intensity: intensity[zone.id] ?? 0,
                projectedSpread: hops,
                lastUpdated: Date()
            )
        }
    }
}

