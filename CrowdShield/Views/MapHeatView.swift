import SwiftUI
import MapKit

struct MapHeatView: View {
    @EnvironmentObject var crowdService: CrowdSimulationService
    @EnvironmentObject var locationManager: LocationManager

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: VenueInfo.center,
            span: MKCoordinateSpan(latitudeDelta: VenueInfo.span, longitudeDelta: VenueInfo.span)
        )
    )
    @State private var selectedZone: CrowdZone?
    @State private var showLegend = true
    @State private var showRiskOnly = false
    @State private var pulse = false
    @State private var riskFlash = false
    @State private var showRouteSheet = false

    private var displayedZones: [CrowdZone] {
        if showRiskOnly {
            return crowdService.zones.filter { $0.riskScore >= 0.5 }
        }
        return crowdService.zones
    }

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                .ignoresSafeArea(edges: .bottom)

            if crowdService.isLoading {
                loadingOverlay
            } else {
                topChrome
                bottomChrome

                if let zone = selectedZone {
                    zoneDetailOverlay(zone: zone)
                }
            }
        }
        .sheet(isPresented: $showRouteSheet) {
            EvacuationRouteSheet(route: crowdService.activeRoute)
        }
        .animation(.easeInOut(duration: 0.55), value: crowdService.overallRisk)
        .animation(.easeInOut(duration: 0.4), value: crowdService.lastUpdate)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
            locationManager.requestLocation()
        }
        .onChange(of: crowdService.overallRisk) { _, newValue in
            guard newValue == .critical || newValue == .high else { return }
            withAnimation(.easeInOut(duration: 0.25)) { riskFlash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.easeInOut(duration: 0.35)) { riskFlash = false }
            }
        }
    }

    // MARK: - Map

    private var mapLayer: some View {
        Map(position: $cameraPosition) {
            ForEach(displayedZones) { zone in
                // Outer heat bloom
                MapCircle(center: zone.coordinate, radius: zone.heatRadius * 1.55)
                    .foregroundStyle(zone.densityColor.opacity(heatOpacity(for: zone) * 0.22))

                // Core heat circle
                MapCircle(center: zone.coordinate, radius: zone.heatRadius)
                    .foregroundStyle(zone.densityColor.opacity(heatOpacity(for: zone)))
                    .stroke(
                        zone.riskLevel.color.opacity(zone.riskScore > 0.6 ? 0.95 : 0.55),
                        lineWidth: strokeWidth(for: zone)
                    )

                Annotation(zone.name, coordinate: zone.coordinate) {
                    ZoneMarker(zone: zone, isPulsing: pulse && zone.riskScore > 0.7)
                        .onTapGesture {
                            HapticManager.trigger(.selection)
                            withAnimation {
                                selectedZone = zone
                            }
                        }
                }
            }

            if let route = crowdService.activeRoute, route.path.count > 1 {
                MapPolyline(coordinates: route.path.map(\.coordinate))
                    .stroke(CrowdShieldTheme.publicAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 8]))
            }

            if let userLoc = locationManager.userLocation {
                Annotation("You", coordinate: userLoc) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.25))
                            .frame(width: pulse ? 28 : 18, height: pulse ? 28 : 18)
                        Image(systemName: "location.fill")
                            .foregroundStyle(.blue)
                            .padding(6)
                            .background(Circle().fill(.white))
                            .shadow(radius: 2)
                    }
                }
            }
        }
    }

    private func heatOpacity(for zone: CrowdZone) -> Double {
        0.28 + min(0.55, zone.density / 10.0)
    }

    private func strokeWidth(for zone: CrowdZone) -> CGFloat {
        if zone.riskScore > 0.75 { return pulse ? 4.5 : 3.0 }
        if zone.riskScore > 0.55 { return 2.5 }
        return 1.2
    }

    // MARK: - Chrome

    private var topChrome: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(VenueInfo.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(crowdService.isSimulating ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                            .scaleEffect(crowdService.isSimulating && pulse ? 1.25 : 1.0)
                        Text("Updated \(crowdService.lastUpdate, style: .time)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }
                Spacer()
                RiskBadge(level: crowdService.overallRisk)
                    .scaleEffect(riskFlash ? 1.08 : 1.0)
                    .shadow(color: crowdService.overallRisk.color.opacity(riskFlash ? 0.7 : 0), radius: riskFlash ? 10 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.5)
            }

            if let minutes = crowdService.predictedCrushInMinutes {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .symbolEffect(.pulse, options: .repeating, value: pulse)
                    Text("Predicted crush risk in ~\(minutes) min")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color.red.opacity(0.95), Color.orange.opacity(0.9)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var bottomChrome: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                if showLegend {
                    DensityLegend()
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                Spacer()
                VStack(spacing: 10) {
                    mapControlButton(
                        icon: showRiskOnly ? "flame.fill" : "flame",
                        tint: showRiskOnly ? .orange : .secondary
                    ) {
                        HapticManager.trigger(.selection)
                        withAnimation { showRiskOnly.toggle() }
                    }
                    mapControlButton(
                        icon: showLegend ? "list.bullet.rectangle.fill" : "list.bullet.rectangle",
                        tint: .secondary
                    ) {
                        withAnimation { showLegend.toggle() }
                    }
                    mapControlButton(icon: "location.fill", tint: CrowdShieldTheme.publicAccent) {
                        HapticManager.trigger(.light)
                        withAnimation {
                            cameraPosition = .region(
                                MKCoordinateRegion(
                                    center: locationManager.userLocation ?? VenueInfo.center,
                                    span: MKCoordinateSpan(latitudeDelta: VenueInfo.span, longitudeDelta: VenueInfo.span)
                                )
                            )
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func mapControlButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func zoneDetailOverlay(zone: CrowdZone) -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { selectedZone = nil }
                }

            VStack {
                Spacer()
                ZoneDetailCard(zone: zone, onClose: {
                    withAnimation { selectedZone = nil }
                }, onFindRoute: {
                    HapticManager.trigger(.medium)
                    crowdService.computeSafestRoute(from: zone.name)
                    withAnimation {
                        selectedZone = nil
                        showRouteSheet = true
                    }
                })
                .padding()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(CrowdShieldTheme.publicAccent)
                Text("Loading live heat map…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .adaptiveGlassCard(cornerRadius: 18)
        }
    }
}

// MARK: - Supporting Views

struct ZoneMarker: View {
    let zone: CrowdZone
    var isPulsing: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if isPulsing {
                    Circle()
                        .stroke(zone.riskLevel.color.opacity(0.55), lineWidth: 2)
                        .frame(width: 36, height: 36)
                        .scaleEffect(isPulsing ? 1.35 : 1.0)
                        .opacity(isPulsing ? 0.35 : 0.8)
                }
                Image(systemName: zone.isBottleneck ? "exclamationmark.triangle.fill" : "person.3.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(9)
                    .background(zone.riskLevel.color)
                    .clipShape(Circle())
                    .shadow(color: zone.riskLevel.color.opacity(0.5), radius: isPulsing ? 8 : 3)
            }

            Text(String(format: "%.1f", zone.density))
                .font(.system(size: 10, weight: .bold))
                .monospacedDigit()
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .contentTransition(.numericText())
        }
        .animation(.easeInOut(duration: 0.5), value: zone.density)
        .animation(.easeInOut(duration: 0.5), value: zone.riskScore)
    }
}

struct RiskBadge: View {
    let level: RiskLevel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: level.icon)
            Text(level.rawValue.uppercased())
                .font(.caption.bold())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(level.color)
        .clipShape(Capsule())
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: level)
    }
}

struct DensityLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Density (p/m²)")
                .font(.caption.bold())
            HStack(spacing: 8) {
                legendItem(color: .green, label: "<2")
                legendItem(color: .yellow, label: "2–4")
                legendItem(color: .orange, label: "4–6")
                legendItem(color: .red, label: ">6")
            }
            Text("Circles = heat · Pulse = high risk")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .adaptiveGlassCard(cornerRadius: 12)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).font(.caption2)
        }
    }
}

struct ZoneDetailCard: View {
    let zone: CrowdZone
    let onClose: () -> Void
    var onFindRoute: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(zone.name)
                        .font(.title3.bold())
                    Label(zone.riskLevel.rawValue, systemImage: zone.riskLevel.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(zone.riskLevel.color)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close")
            }

            // Risk progress
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Risk score")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(zone.riskScore * 100))%")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(zone.riskLevel.color)
                        .contentTransition(.numericText())
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.2))
                        Capsule()
                            .fill(zone.riskLevel.color)
                            .frame(width: max(8, geo.size.width * zone.riskScore))
                            .animation(.easeInOut(duration: 0.5), value: zone.riskScore)
                    }
                }
                .frame(height: 8)
            }

            HStack(spacing: 12) {
                metric(title: "Density", value: String(format: "%.1f p/m²", zone.density), color: zone.densityColor)
                metric(title: "Speed", value: String(format: "%.2f m/s", zone.movementSpeed), color: CrowdShieldTheme.publicAccent)
                metric(title: "Flow", value: "\(Int(zone.flowDirection))°", color: .purple)
            }

            if zone.isBottleneck {
                Label("Bottleneck detected — prioritize alternate exits", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline.bold())
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if let onFindRoute {
                Button(action: onFindRoute) {
                    Label("Find Safest Exit Route", systemImage: "figure.walk.motion")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CrowdShieldTheme.publicAccent)
            }

            Text("Last zone update \(zone.lastUpdated, style: .relative) ago")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .adaptiveGlassCard(cornerRadius: 24)
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }

    private func metric(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(color)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct EvacuationRouteSheet: View {
    let route: EvacuationRoute?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let route, let destination = route.destination {
                    List {
                        Section {
                            HStack(spacing: 14) {
                                Image(systemName: "figure.walk.motion")
                                    .font(.title)
                                    .foregroundStyle(CrowdShieldTheme.publicAccent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Safest route to \(destination.name)")
                                        .font(.headline)
                                    Text("Est. \(Int(route.estimatedWalkSeconds / 60)) min \(Int(route.estimatedWalkSeconds.truncatingRemainder(dividingBy: 60)))s on foot")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        if !route.warnings.isEmpty {
                            Section("Warnings") {
                                ForEach(route.warnings, id: \.self) { warning in
                                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                }
                            }
                        }

                        Section("Path") {
                            ForEach(Array(route.path.enumerated()), id: \.element.id) { index, zone in
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(zone.riskLevel.color.opacity(0.2)).frame(width: 28, height: 28)
                                        Text("\(index + 1)").font(.caption.bold()).foregroundStyle(zone.riskLevel.color)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(zone.name).font(.subheadline.weight(.semibold))
                                        Text("\(zone.riskLevel.rawValue) · \(String(format: "%.1f", zone.density)) p/m²")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if index == route.path.count - 1 {
                                        Image(systemName: "flag.checkered.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Route Found",
                        systemImage: "xmark.octagon",
                        description: Text("Could not compute a safe path from this zone — all connected exits may be unreachable.")
                    )
                }
            }
            .navigationTitle("Evacuation Route")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    MapHeatView()
        .environmentObject(CrowdSimulationService())
        .environmentObject(LocationManager())
}
