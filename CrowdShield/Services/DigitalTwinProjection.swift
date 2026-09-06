import CoreLocation
import Foundation

/// Projects the venue's real (lat, lon) zone coordinates into a flat 3D
/// layout plane for the Digital Twin scene. Kept separate from any
/// RealityKit code so the projection math itself — the part most likely to
/// have an off-by-scale or flipped-axis bug — can be reasoned about and
/// unit-tested without needing a 3D rendering context.
///
/// Uses an equirectangular-style local projection (flat-earth approximation
/// scaled by cos(latitude)) rather than a full geographic projection —
/// entirely adequate at venue scale (hundreds of meters), where the
/// curvature of the earth is not a meaningful source of error.
enum DigitalTwinProjection {
    /// Meters-per-degree-latitude is ~111,320m everywhere; longitude's
    /// meters-per-degree shrinks by cos(latitude), which matters even at
    /// venue scale if zones span a wide longitude range at high latitude.
    private static let metersPerDegreeLatitude = 111_320.0

    /// One real-world meter maps to this many RealityKit scene units.
    /// RealityKit's default unit is meters, so 1:1 keeps the scene
    /// physically-scaled — a venue spanning ~500m becomes a ~500-unit
    /// scene, which we then additionally scale down in the view itself for
    /// a comfortable default camera distance rather than baking an
    /// arbitrary scale factor into the projection math.
    private static let sceneUnitsPerMeter: Float = 1.0

    struct ProjectedZone {
        let name: String
        /// X (east-west) and Z (north-south) position in scene units.
        /// Y is deliberately not part of the projection — the Digital Twin
        /// view derives zone height from live risk data, not from static
        /// geography, so it stays a separate concern.
        let x: Float
        let z: Float
    }

    /// Projects a set of (name, coordinate) pairs into flat scene-space
    /// positions, centered on their own centroid so the resulting layout
    /// is centered near the scene origin regardless of the venue's real
    /// absolute latitude/longitude.
    static func project(_ zones: [(name: String, coordinate: CLLocationCoordinate2D)]) -> [ProjectedZone] {
        guard !zones.isEmpty else { return [] }

        let centroidLat = zones.map(\.coordinate.latitude).reduce(0, +) / Double(zones.count)
        let centroidLon = zones.map(\.coordinate.longitude).reduce(0, +) / Double(zones.count)
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(centroidLat * .pi / 180)

        return zones.map { zone in
            let dLat = zone.coordinate.latitude - centroidLat
            let dLon = zone.coordinate.longitude - centroidLon

            // North (increasing latitude) maps to -Z in RealityKit's
            // right-handed coordinate system (camera looks down -Z by
            // default), so a zone north of centroid should appear "further
            // into the scene" rather than inverted.
            let metersNorth = dLat * metersPerDegreeLatitude
            let metersEast = dLon * metersPerDegreeLongitude

            return ProjectedZone(
                name: zone.name,
                x: Float(metersEast * Double(sceneUnitsPerMeter)),
                z: Float(-metersNorth * Double(sceneUnitsPerMeter))
            )
        }
    }
}
