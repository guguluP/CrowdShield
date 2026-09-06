import Foundation
import CoreLocation

/// An edge between two zones the crowd can physically walk between.
struct ZoneConnection {
    let from: String   // zone name
    let to: String     // zone name
    let baseDistance: Double // meters, static venue layout distance
}

/// Static description of which zones connect to which, and which zones are exits.
/// This models the venue's walkable graph — in production this would be authored
/// once per venue (from floor plans) and loaded from configuration, not hardcoded.
struct VenueGraph {
    let connections: [ZoneConnection]
    let exitZoneNames: Set<String>

    static let festivalGrounds = VenueGraph(
        connections: [
            ZoneConnection(from: "Main Entrance Gate A", to: "Central Plaza", baseDistance: 60),
            ZoneConnection(from: "Central Plaza", to: "Stage Area", baseDistance: 80),
            ZoneConnection(from: "Central Plaza", to: "Food Court", baseDistance: 50),
            ZoneConnection(from: "Central Plaza", to: "VIP Lane", baseDistance: 40),
            ZoneConnection(from: "Central Plaza", to: "Bridge Corridor", baseDistance: 70),
            ZoneConnection(from: "Bridge Corridor", to: "Exit Gate B", baseDistance: 55),
            ZoneConnection(from: "Bridge Corridor", to: "South Stand", baseDistance: 65),
            ZoneConnection(from: "Stage Area", to: "North Stand", baseDistance: 90),
            ZoneConnection(from: "Stage Area", to: "South Stand", baseDistance: 90),
            ZoneConnection(from: "Food Court", to: "East Bottleneck", baseDistance: 45),
            ZoneConnection(from: "East Bottleneck", to: "Exit Gate B", baseDistance: 100),
            ZoneConnection(from: "North Stand", to: "Main Entrance Gate A", baseDistance: 110),
            ZoneConnection(from: "VIP Lane", to: "Stage Area", baseDistance: 35)
        ],
        exitZoneNames: ["Exit Gate B", "Main Entrance Gate A"]
    )
}

/// A step-by-step evacuation path from a zone to the nearest safe exit.
struct EvacuationRoute {
    let path: [CrowdZone]           // ordered zones to walk through
    let totalRiskWeightedCost: Double
    let estimatedWalkSeconds: Double
    let warnings: [String]          // e.g. "passes through a bottleneck zone"

    var destination: CrowdZone? { path.last }
}

/// Computes the safest (not just shortest) path out of the venue using Dijkstra's
/// algorithm over the venue graph, where edge cost is weighted by the destination
/// zone's current risk score — so the router actively avoids congested zones
/// rather than just minimizing distance.
enum EvacuationRoutingEngine {

    static func safestRoute(
        from originZoneName: String,
        zones: [CrowdZone],
        graph: VenueGraph = .festivalGrounds
    ) -> EvacuationRoute? {
        let zonesByName = Dictionary(uniqueKeysWithValues: zones.map { ($0.name, $0) })
        guard zonesByName[originZoneName] != nil else { return nil }

        // Build adjacency with risk-weighted costs.
        // Cost = distance * (1 + riskScore * riskPenaltyFactor)
        // A zone at riskScore 1.0 effectively costs ~4x its physical distance to
        // traverse, so the router strongly prefers safer, if longer, paths.
        let riskPenaltyFactor = 3.0
        var adjacency: [String: [(neighbor: String, cost: Double)]] = [:]

        func edgeCost(to destinationName: String, distance: Double) -> Double {
            let risk = zonesByName[destinationName]?.riskScore ?? 0.3
            let bottleneckPenalty = (zonesByName[destinationName]?.isBottleneck ?? false) ? 2.0 : 1.0
            return distance * (1 + risk * riskPenaltyFactor) * bottleneckPenalty
        }

        for connection in graph.connections {
            adjacency[connection.from, default: []].append(
                (connection.to, edgeCost(to: connection.to, distance: connection.baseDistance))
            )
            adjacency[connection.to, default: []].append(
                (connection.from, edgeCost(to: connection.from, distance: connection.baseDistance))
            )
        }

        // Dijkstra
        var distances: [String: Double] = [originZoneName: 0]
        var previous: [String: String] = [:]
        var visited: Set<String> = []
        var frontier: Set<String> = [originZoneName]

        while !frontier.isEmpty {
            guard let current = frontier.min(by: { (distances[$0] ?? .infinity) < (distances[$1] ?? .infinity) }) else { break }
            frontier.remove(current)
            if visited.contains(current) { continue }
            visited.insert(current)

            for edge in adjacency[current] ?? [] {
                guard !visited.contains(edge.neighbor) else { continue }
                let candidateDistance = (distances[current] ?? .infinity) + edge.cost
                if candidateDistance < (distances[edge.neighbor] ?? .infinity) {
                    distances[edge.neighbor] = candidateDistance
                    previous[edge.neighbor] = current
                    frontier.insert(edge.neighbor)
                }
            }
        }

        // Find the reachable exit with the lowest total cost.
        let reachableExits = graph.exitZoneNames
            .filter { distances[$0] != nil }
            .sorted { (distances[$0] ?? .infinity) < (distances[$1] ?? .infinity) }

        guard let bestExit = reachableExits.first else { return nil }

        // Reconstruct path.
        var pathNames: [String] = [bestExit]
        var cursor = bestExit
        while let prev = previous[cursor] {
            pathNames.append(prev)
            cursor = prev
            if prev == originZoneName { break }
        }
        pathNames.reverse()

        let pathZones = pathNames.compactMap { zonesByName[$0] }
        guard pathZones.count == pathNames.count else { return nil }

        var warnings: [String] = []
        for zone in pathZones {
            if zone.isBottleneck {
                warnings.append("Route passes through a known bottleneck: \(zone.name)")
            }
            if zone.riskLevel == .high || zone.riskLevel == .critical {
                warnings.append("\(zone.name) is currently at \(zone.riskLevel.rawValue.lowercased()) risk")
            }
        }

        // Rough walk-time estimate: sum physical distances / average walking speed,
        // slowed down proportionally where density is high.
        var totalDistance = 0.0
        for i in 0..<(pathNames.count - 1) {
            if let conn = graph.connections.first(where: {
                ($0.from == pathNames[i] && $0.to == pathNames[i + 1]) ||
                ($0.to == pathNames[i] && $0.from == pathNames[i + 1])
            }) {
                totalDistance += conn.baseDistance
            }
        }
        let avgSpeed = max(0.3, pathZones.map(\.movementSpeed).reduce(0, +) / Double(max(pathZones.count, 1)))
        let estimatedSeconds = totalDistance / avgSpeed

        return EvacuationRoute(
            path: pathZones,
            totalRiskWeightedCost: distances[bestExit] ?? 0,
            estimatedWalkSeconds: estimatedSeconds,
            warnings: warnings
        )
    }
}
