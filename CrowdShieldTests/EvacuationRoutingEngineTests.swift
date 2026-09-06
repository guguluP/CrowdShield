import XCTest
import CoreLocation
@testable import CrowdShield

final class EvacuationRoutingEngineTests: XCTestCase {

    /// Builds a CrowdZone with sensible defaults, overriding only what a
    /// given test cares about — keeps each test's setup focused on the
    /// specific risk/bottleneck values it's actually testing.
    private func zone(
        _ name: String,
        riskScore: Double = 0.1,
        isBottleneck: Bool = false,
        movementSpeed: Double = 1.2
    ) -> CrowdZone {
        CrowdZone(
            name: name,
            coordinate: CLLocationCoordinate2D(latitude: 28.614, longitude: 77.209),
            density: 2.0,
            movementSpeed: movementSpeed,
            flowDirection: 0,
            isBottleneck: isBottleneck,
            riskScore: riskScore,
            lastUpdated: Date()
        )
    }

    /// All 10 zones from the real venue graph (festivalGrounds), all at
    /// low/safe risk by default — individual tests override specific
    /// zones' risk to exercise the routing logic.
    private func allZonesAtLowRisk() -> [CrowdZone] {
        [
            zone("Main Entrance Gate A"),
            zone("Central Plaza"),
            zone("Stage Area"),
            zone("Food Court"),
            zone("Exit Gate B"),
            zone("Bridge Corridor"),
            zone("VIP Lane"),
            zone("North Stand"),
            zone("South Stand"),
            zone("East Bottleneck"),
        ]
    }

    // MARK: - Basic routing

    func test_unknownOriginZone_returnsNil() {
        let route = EvacuationRoutingEngine.safestRoute(from: "Nonexistent Zone", zones: allZonesAtLowRisk())
        XCTAssertNil(route, "An origin not present in the zones array has no defined route.")
    }

    func test_routeFromCentralPlaza_reachesAnExit() {
        let route = EvacuationRoutingEngine.safestRoute(from: "Central Plaza", zones: allZonesAtLowRisk())

        XCTAssertNotNil(route)
        let exitNames: Set<String> = ["Exit Gate B", "Main Entrance Gate A"]
        XCTAssertTrue(exitNames.contains(route!.destination?.name ?? ""), "Route should terminate at one of the graph's defined exit zones.")
    }

    func test_routeStartsAtOrigin() {
        let route = EvacuationRoutingEngine.safestRoute(from: "Stage Area", zones: allZonesAtLowRisk())
        XCTAssertEqual(route?.path.first?.name, "Stage Area", "The path's first zone should be the origin itself.")
    }

    func test_originThatIsItselfAnExit_returnsTrivialRoute() {
        // "Main Entrance Gate A" is one of the graph's exitZoneNames — if
        // you're already at an exit, the route should just be that single
        // zone, not fail or wander elsewhere first.
        let route = EvacuationRoutingEngine.safestRoute(from: "Main Entrance Gate A", zones: allZonesAtLowRisk())

        XCTAssertNotNil(route)
        XCTAssertEqual(route?.path.count, 1)
        XCTAssertEqual(route?.destination?.name, "Main Entrance Gate A")
        XCTAssertEqual(route?.totalRiskWeightedCost, 0, "Cost to reach your own current zone should be zero.")
    }

    // MARK: - Risk-aware routing (the actual point of this engine)

    func test_highRiskZoneOnShortestPath_isAvoidedInFavorOfLongerSaferPath() {
        // Verified independently (not just hand-computed) via a standalone
        // Dijkstra port: from "South Stand", the safe/low-risk route goes
        // South Stand -> Bridge Corridor -> Exit Gate B. Making Bridge
        // Corridor extremely high-risk + a bottleneck should force a
        // reroute all the way around via Stage Area -> VIP Lane -> Central
        // Plaza -> Main Entrance Gate A instead — a genuinely longer
        // physical path chosen specifically to avoid danger, which is the
        // entire premise of "safest, not shortest" routing.
        //
        // (Central Plaza was tried first as an origin but rejected: it has
        // a direct edge straight to Main Entrance Gate A, an exit, making
        // Bridge Corridor's risk irrelevant to its routing regardless of
        // value — always verify graph topology programmatically rather
        // than by inspection, exactly the mistake corrected here.)
        var zones = allZonesAtLowRisk()
        if let idx = zones.firstIndex(where: { $0.name == "Bridge Corridor" }) {
            zones[idx] = zone("Bridge Corridor", riskScore: 0.95, isBottleneck: true)
        }

        let route = EvacuationRoutingEngine.safestRoute(from: "South Stand", zones: zones)

        XCTAssertNotNil(route)
        let pathNames = route!.path.map(\.name)
        XCTAssertFalse(
            pathNames.contains("Bridge Corridor"),
            "With Bridge Corridor at extreme risk + bottleneck, the router should route around it via Stage Area/VIP Lane/Central Plaza rather than straight through danger."
        )
        XCTAssertEqual(route?.destination?.name, "Main Entrance Gate A", "The reroute should terminate at the alternate exit, not Exit Gate B (which is only reachable through the dangerous Bridge Corridor from this origin).")
    }

    func test_allSafeZones_prefersShorterPath() {
        // With nothing risky anywhere, the router should behave like plain
        // shortest-path — confirms the risk weighting doesn't introduce
        // bizarre detours when there's no actual risk signal to respond to.
        // Verified: South Stand -> Bridge Corridor -> Exit Gate B (cost
        // 156) is cheaper than the long way around via Stage Area (cost
        // 292.5+ at equal risk), so the direct route should win.
        let route = EvacuationRoutingEngine.safestRoute(from: "South Stand", zones: allZonesAtLowRisk())

        XCTAssertNotNil(route)
        XCTAssertTrue(
            route!.path.map(\.name).contains("Bridge Corridor"),
            "With all zones equally low-risk, the shorter physical path (via Bridge Corridor) should be preferred over the longer alternate route."
        )
        XCTAssertEqual(route?.destination?.name, "Exit Gate B")
    }

    func test_bottleneckZone_addsWarning() {
        // Verified: with Bridge Corridor flagged as a bottleneck but only
        // moderate risk (0.2), it's still cheaper than the long way
        // around (279.5 vs 292.5+), so the router still routes through it
        // — letting us check the bottleneck warning text specifically,
        // independent of whether risk alone would have avoided it.
        var zones = allZonesAtLowRisk()
        if let idx = zones.firstIndex(where: { $0.name == "Bridge Corridor" }) {
            zones[idx] = zone("Bridge Corridor", riskScore: 0.2, isBottleneck: true)
        }

        let route = EvacuationRoutingEngine.safestRoute(from: "South Stand", zones: zones)

        guard let route, route.path.map(\.name).contains("Bridge Corridor") else {
            XCTFail("Expected the route to pass through Bridge Corridor for this test to be meaningful.")
            return
        }
        XCTAssertTrue(
            route.warnings.contains(where: { $0.contains("Bridge Corridor") && $0.contains("bottleneck") }),
            "A bottleneck zone on the path should produce a specific warning mentioning it."
        )
    }

    func test_highRiskZoneOnPath_addsRiskWarning() {
        // Verified independently: from "Food Court", blocking off Central
        // Plaza (the only other way out from this side of the venue)
        // forces the route through East Bottleneck at riskScore 0.7
        // ("High" level) to reach Exit Gate B — letting us confirm the
        // warning text reflects that zone's actual risk level.
        var zones = allZonesAtLowRisk()
        if let idx = zones.firstIndex(where: { $0.name == "Central Plaza" }) {
            zones[idx] = zone("Central Plaza", riskScore: 0.99, isBottleneck: true)
        }
        if let idx = zones.firstIndex(where: { $0.name == "East Bottleneck" }) {
            zones[idx] = zone("East Bottleneck", riskScore: 0.7)
        }

        let route = EvacuationRoutingEngine.safestRoute(from: "Food Court", zones: zones)

        XCTAssertNotNil(route)
        let pathNames = route!.path.map(\.name)
        XCTAssertTrue(pathNames.contains("East Bottleneck"), "With Central Plaza blocked, East Bottleneck is the only remaining path to an exit from Food Court.")
        XCTAssertTrue(
            route!.warnings.contains(where: { $0.contains("East Bottleneck") && $0.contains("risk") }),
            "A high-risk zone (riskScore 0.7 = 'High' level) on the path should produce a risk warning."
        )
    }

    // MARK: - Walk time estimate sanity

    func test_walkTimeEstimate_isPositiveForMultiZoneRoute() {
        let route = EvacuationRoutingEngine.safestRoute(from: "Stage Area", zones: allZonesAtLowRisk())
        XCTAssertNotNil(route)
        if (route?.path.count ?? 0) > 1 {
            XCTAssertGreaterThan(route!.estimatedWalkSeconds, 0, "A multi-zone route covering real distance should have a positive estimated walk time.")
        }
    }

    func test_walkTimeEstimate_isZeroForTrivialSameZoneRoute() {
        let route = EvacuationRoutingEngine.safestRoute(from: "Exit Gate B", zones: allZonesAtLowRisk())
        XCTAssertEqual(route?.path.count, 1)
        XCTAssertEqual(route?.estimatedWalkSeconds, 0, accuracy: 0.001, "Zero distance traveled should mean zero estimated walk time.")
    }

    func test_verySlowMovementSpeed_stillProducesFiniteWalkTime() {
        // avgSpeed is clamped to a minimum of 0.3 in the implementation —
        // confirms a near-zero movementSpeed doesn't produce a
        // division-by-zero / infinite walk time estimate.
        var zones = allZonesAtLowRisk()
        for i in zones.indices {
            zones[i].movementSpeed = 0.0
        }
        let route = EvacuationRoutingEngine.safestRoute(from: "Central Plaza", zones: zones)

        XCTAssertNotNil(route)
        XCTAssertTrue(route!.estimatedWalkSeconds.isFinite, "Even with zero movement speed input, the clamped minimum should prevent an infinite/NaN result.")
    }
}
