import SwiftUI
import RealityKit
import CoreLocation

/// TechNova brief bonus feature: "Digital Twin of the venue." Renders the
/// live venue as a 3D scene where each zone is a column whose HEIGHT and
/// COLOR both encode current risk — height gives an at-a-glance silhouette
/// of "where is this venue dangerous right now" that a flat 2D heat map
/// can't convey as immediately, and color reuses RiskLevel's existing
/// green/yellow/orange/red scheme so it reads consistently with every
/// other risk display in the app.
///
/// Positions come from DigitalTwinProjection, which maps each zone's real
/// (lat, lon) into a flat scene-space plane — this is a true reflection of
/// the venue's actual relative geography, not an arbitrary layout, which
/// is what makes this a *twin* of the venue rather than a generic 3D
/// dashboard widget.
///
/// Updates live: this view holds no snapshot of zone data — every entity's
/// height/color is rebuilt from CrowdSimulationService.zones whenever that
/// published array changes, so the twin tracks the same 3-second
/// simulation tick as the rest of the app with no separate refresh logic.
struct DigitalTwinView: View {
    @EnvironmentObject var crowdService: CrowdSimulationService
    @State private var selectedZoneName: String?
    @State private var riskOnly = false

    /// Real-world meters are projected 1:1 into scene units by
    /// DigitalTwinProjection; this additionally compresses the whole scene
    /// so a ~500m venue fits comfortably in view at a sensible default
    /// camera distance, without changing the projection math itself (which
    /// stays in real meters for any future use, e.g. distance queries).
    private let sceneCompression: Float = 0.04

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                RealityView { content in
                    content.add(buildScene())
                } update: { content in
                    // Rebuild is cheap at this venue's zone count (≤ ~10) and
                    // keeps the update path simple/robust — a more granular
                    // per-entity diff would save little here and adds real
                    // risk of entities drifting out of sync with zone data.
                    content.entities.removeAll()
                    content.add(buildScene())
                }
                .realityViewCameraControls(.orbit)
                .background(Color.black)
                .ignoresSafeArea(edges: .bottom)

                legend
                    .padding()

                if let selectedZoneName, let zone = crowdService.zones.first(where: { $0.name == selectedZoneName }) {
                    zoneInfoCard(zone)
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Digital Twin")
            .toolbar {
#if os(macOS)
                ToolbarItem(placement: .automatic) {
                    Toggle(isOn: $riskOnly) {
                        Text("Risk only")
                    }
                    .toggleStyle(.button)
                    .font(.caption)
                }
                ToolbarItem(placement: .automatic) {
                    if let name = selectedZoneName {
                        Button {
                            crowdService.computeSafestRoute(from: name)
                        } label: {
                            Label("Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                    }
                }
#else
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $riskOnly) {
                        Text("Risk only")
                    }
                    .toggleStyle(.button)
                    .font(.caption)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let name = selectedZoneName {
                        Button {
                            crowdService.computeSafestRoute(from: name)
                        } label: {
                            Label("Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                    }
                }
#endif
            }
            .onTapGesture {
                // RealityView hit-testing for entity taps requires more setup
                // (CollisionComponent + gesture-to-entity mapping) than this
                // first pass includes; selecting via the legend list below is
                // the reliable interaction path for now, tap-to-dismiss here.
                withAnimation { selectedZoneName = nil }
            }
        }
    }

    // MARK: - Scene construction

    private func buildScene() -> Entity {
        let root = Entity()

        let sunlight = DirectionalLight()
        sunlight.light.intensity = 4000
        sunlight.orientation = simd_quatf(angle: -.pi / 3, axis: [1, 0, 0])
        root.addChild(sunlight)

        let ground = groundPlaneEntity()
        root.addChild(ground)

        let displayedZones = riskOnly
            ? crowdService.zones.filter { $0.riskScore >= 0.5 }
            : crowdService.zones

        let projected = DigitalTwinProjection.project(
            displayedZones.map { (name: $0.name, coordinate: $0.coordinate) }
        )

        for zone in displayedZones {
            guard let position = projected.first(where: { $0.name == zone.name }) else { continue }
            let columnEntity = zoneColumnEntity(zone: zone, projectedX: position.x, projectedZ: position.z)
            root.addChild(columnEntity)
        }

        // Evacuation route as a thin elevated path connecting zone columns.
        if let route = crowdService.activeRoute {
            let pathNames: [String] = route.path.map { element in
                // If `route.path` is already [String], this map is a no-op via identity.
                // If it contains `CrowdZone` or another type with a `name` property, extract it here.
                if let zone = element as? CrowdZone { return zone.name }
                if let name = element as? String { return name }
                // Fallback: use String(describing:) to avoid type mismatch; unmatched items will be skipped later.
                return String(describing: element)
            }
            var points: [SIMD3<Float>] = []
            for name in pathNames {
                guard let position = projected.first(where: { $0.name == name }),
                      let zone = displayedZones.first(where: { $0.name == name }) else { continue }
                let h = 0.3 + Float(zone.riskScore) * 3.2
                points.append(SIMD3<Float>(
                    position.x * sceneCompression,
                    h * 0.55,
                    position.z * sceneCompression
                ))
            }
            if points.count >= 2 {
                for i in 0..<(points.count - 1) {
                    let a = points[i]
                    let b = points[i + 1]
                    let mid = (a + b) / 2
                    let delta = b - a
                    let length = simd_length(delta)
                    guard length > 0.01 else { continue }
                    let mesh = MeshResource.generateBox(width: 0.08, height: 0.06, depth: length)
                    var mat = SimpleMaterial()
                    mat.color = .init(tint: .cyan)
                    mat.metallic = .float(0.4)
                    let entity = ModelEntity(mesh: mesh, materials: [mat])
                    entity.position = mid
                    // Orient box along the segment (simplified: face along Z then rotate).
                    let dir = simd_normalize(delta)
                    let angle = atan2(dir.x, dir.z)
                    entity.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
                    root.addChild(entity)
                }
            }
        }

        return root
    }

    private func groundPlaneEntity() -> Entity {
        let mesh = MeshResource.generatePlane(width: 30, depth: 30)
        var material = SimpleMaterial()
        material.color = .init(tint: .init(white: 0.12, alpha: 1))
        material.roughness = .float(0.9)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "ground"
        return entity
    }

    /// A single zone's column: base footprint plus a height that scales
    /// with risk score, colored by the same RiskLevel scheme used
    /// throughout the app. Column height is the primary "twin" signal —
    /// a dangerous zone visibly rises out of the venue's skyline rather
    /// than only being distinguishable by color, which matters for
    /// quick recognition and for colorblind accessibility.
    private func zoneColumnEntity(zone: CrowdZone, projectedX: Float, projectedZ: Float) -> Entity {
        let baseHeight: Float = 0.3
        let riskHeight = baseHeight + Float(zone.riskScore) * 3.2
        let footprint: Float = 0.9

        let mesh = MeshResource.generateBox(width: footprint, height: riskHeight, depth: footprint, cornerRadius: 0.05)
        let riskColor = PlatformColor(zone.riskLevel.color)

        let entity: ModelEntity
        if zone.riskLevel == .critical {
            // Critical zones get a genuine emissive glow rather than an
            // animated pulse — the RealityView update closure fully
            // rebuilds the scene every simulation tick (see the `update`
            // block above), which would restart/stutter any in-flight
            // animation every 3 seconds anyway. A static glow is visually
            // distinct, immediately recognizable, and has no
            // animation-lifecycle edge cases to get wrong.
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: riskColor.withAlphaComponent(0.95))
            material.emissiveColor = .init(color: riskColor)
            material.emissiveIntensity = 1.4
            material.roughness = .init(floatLiteral: 0.4)
            material.metallic = .init(floatLiteral: 0.05)
            entity = ModelEntity(mesh: mesh, materials: [material])
        } else {
            var material = SimpleMaterial()
            material.color = .init(tint: riskColor.withAlphaComponent(0.92))
            material.roughness = .float(0.4)
            material.metallic = .float(0.05)
            entity = ModelEntity(mesh: mesh, materials: [material])
        }

        entity.name = zone.name
        entity.position = [
            projectedX * sceneCompression,
            riskHeight / 2, // box origin is centered; lift so it sits on the ground plane
            projectedZ * sceneCompression,
        ]

        return entity
    }

    // MARK: - Overlay UI

    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zones")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(crowdService.zones) { zone in
                Button {
                    withAnimation { selectedZoneName = zone.name }
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(zone.riskLevel.color)
                            .frame(width: 9, height: 9)
                        Text(zone.name)
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(zone.riskLevel.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: 220, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func zoneInfoCard(_ zone: CrowdZone) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(zone.name)
                    .font(.headline)
                Spacer()
                Label(zone.riskLevel.rawValue, systemImage: zone.riskLevel.icon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(zone.riskLevel.color)
            }
            HStack(spacing: 16) {
                statPair("Density", String(format: "%.0f%%", zone.density * 100))
                statPair("Risk", String(format: "%.0f%%", zone.riskScore * 100))
                if zone.isBottleneck {
                    Label("Bottleneck", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func statPair(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
    }
}

/// UIColor/NSColor both already provide a native `init(Color)` via
/// SwiftUI's platform-bridging extensions — PlatformColor is just a
/// same-named alias so call sites above don't need their own #if os()
/// branching to pick which one applies.
#if os(macOS)
fileprivate typealias PlatformColor = NSColor
#else
fileprivate typealias PlatformColor = UIColor
#endif

