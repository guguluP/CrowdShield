import XCTest
import CoreLocation
@testable import CrowdShield

final class DigitalTwinProjectionTests: XCTestCase {

    func test_emptyInput_returnsEmpty() {
        let result = DigitalTwinProjection.project([])
        XCTAssertTrue(result.isEmpty)
    }

    func test_singleZone_projectsToOrigin() {
        // A single zone's centroid IS itself, so it must land exactly at
        // (0, 0) regardless of its real-world coordinates.
        let zones = [(name: "Only Zone", coordinate: CLLocationCoordinate2D(latitude: 28.6139, longitude: 77.2090))]
        let result = DigitalTwinProjection.project(zones)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].x, 0, accuracy: 0.001)
        XCTAssertEqual(result[0].z, 0, accuracy: 0.001)
    }

    func test_allZonesPreserved_sameCountAndNames() {
        let zones = [
            (name: "A", coordinate: CLLocationCoordinate2D(latitude: 28.615, longitude: 77.207)),
            (name: "B", coordinate: CLLocationCoordinate2D(latitude: 28.613, longitude: 77.209)),
            (name: "C", coordinate: CLLocationCoordinate2D(latitude: 28.612, longitude: 77.211)),
        ]
        let result = DigitalTwinProjection.project(zones)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(Set(result.map(\.name)), Set(["A", "B", "C"]))
    }

    func test_northernZone_hasNegativeZ() {
        // Two zones at the same longitude, one north of the other. In
        // RealityKit's coordinate system (camera looks down -Z by
        // default), "further north" should map to more-negative Z so it
        // reads as "further into the scene" rather than inverted — this is
        // documented as intentional in DigitalTwinProjection's comments,
        // and is the exact convention DigitalTwinView relies on for the
        // scene to look geographically sane when orbited.
        let zones = [
            (name: "North", coordinate: CLLocationCoordinate2D(latitude: 28.620, longitude: 77.209)),
            (name: "South", coordinate: CLLocationCoordinate2D(latitude: 28.610, longitude: 77.209)),
        ]
        let result = DigitalTwinProjection.project(zones)

        let north = result.first(where: { $0.name == "North" })!
        let south = result.first(where: { $0.name == "South" })!

        XCTAssertLessThan(north.z, south.z, "A zone further north should have a smaller (more negative) Z than one further south.")
    }

    func test_easternZone_hasGreaterX() {
        let zones = [
            (name: "East", coordinate: CLLocationCoordinate2D(latitude: 28.614, longitude: 77.220)),
            (name: "West", coordinate: CLLocationCoordinate2D(latitude: 28.614, longitude: 77.200)),
        ]
        let result = DigitalTwinProjection.project(zones)

        let east = result.first(where: { $0.name == "East" })!
        let west = result.first(where: { $0.name == "West" })!

        XCTAssertGreaterThan(east.x, west.x, "A zone further east should have a larger X than one further west.")
    }

    func test_symmetricZones_areEquidistantFromCentroid() {
        // Two zones placed symmetrically around a shared centroid should
        // project to positions that are mirror images of each other,
        // confirming the centroid subtraction is correct (not offset or
        // scaled asymmetrically).
        let centerLat = 28.614
        let centerLon = 77.209
        let delta = 0.004

        let zones = [
            (name: "North", coordinate: CLLocationCoordinate2D(latitude: centerLat + delta, longitude: centerLon)),
            (name: "South", coordinate: CLLocationCoordinate2D(latitude: centerLat - delta, longitude: centerLon)),
        ]
        let result = DigitalTwinProjection.project(zones)

        let north = result.first(where: { $0.name == "North" })!
        let south = result.first(where: { $0.name == "South" })!

        XCTAssertEqual(north.z, -south.z, accuracy: 0.5, "Symmetric zones around the centroid should have mirrored Z values.")
        XCTAssertEqual(north.x, south.x, accuracy: 0.001, "Zones with identical longitude should have identical X regardless of latitude difference.")
    }

    func test_realVenueData_producesReasonableSceneScale() {
        // Locks in the actual venue seed data's projected scale, matching
        // the manual verification done during development (roughly ±250m
        // spread) — if this ever changes drastically (e.g. an accidental
        // unit conversion bug), this test catches it without needing to
        // manually re-run the projection and eyeball the numbers again.
        let zones: [(name: String, coordinate: CLLocationCoordinate2D)] = [
            ("Main Entrance Gate A", CLLocationCoordinate2D(latitude: 28.6155, longitude: 77.2075)),
            ("Central Plaza", CLLocationCoordinate2D(latitude: 28.6139, longitude: 77.2090)),
            ("Stage Area", CLLocationCoordinate2D(latitude: 28.6125, longitude: 77.2105)),
            ("Food Court", CLLocationCoordinate2D(latitude: 28.6148, longitude: 77.2112)),
            ("Exit Gate B", CLLocationCoordinate2D(latitude: 28.6120, longitude: 77.2070)),
        ]
        let result = DigitalTwinProjection.project(zones)

        for zone in result {
            XCTAssertLessThan(abs(zone.x), 500, "\(zone.name)'s X (\(zone.x)) is far outside the expected venue-scale range — possible unit conversion bug.")
            XCTAssertLessThan(abs(zone.z), 500, "\(zone.name)'s Z (\(zone.z)) is far outside the expected venue-scale range — possible unit conversion bug.")
        }
    }

    func test_longitudeScaling_accountsForLatitude() {
        // At higher latitudes, a degree of longitude covers fewer real
        // meters (cos(latitude) shrinkage). Two zones with the identical
        // longitude delta, but centered at very different latitudes,
        // should NOT produce the same X spread — if they did, the
        // cos(latitude) correction would be missing/broken.
        let lowLatZones: [(name: String, coordinate: CLLocationCoordinate2D)] = [
            ("A", CLLocationCoordinate2D(latitude: 1.0, longitude: 77.20)),
            ("B", CLLocationCoordinate2D(latitude: 1.0, longitude: 77.21)),
        ]
        let highLatZones: [(name: String, coordinate: CLLocationCoordinate2D)] = [
            ("A", CLLocationCoordinate2D(latitude: 60.0, longitude: 77.20)),
            ("B", CLLocationCoordinate2D(latitude: 60.0, longitude: 77.21)),
        ]

        let lowLatResult = DigitalTwinProjection.project(lowLatZones)
        let highLatResult = DigitalTwinProjection.project(highLatZones)

        let lowLatSpread = abs(lowLatResult[0].x - lowLatResult[1].x)
        let highLatSpread = abs(highLatResult[0].x - highLatResult[1].x)

        XCTAssertGreaterThan(
            lowLatSpread, highLatSpread,
            "The same 0.01° longitude difference should cover MORE real meters near the equator than near latitude 60°, confirming cos(latitude) scaling is applied."
        )
    }
}
