import Foundation
import CoreLocation
import Combine

@MainActor
class CrowdSimulationService: ObservableObject {
    @Published var zones: [CrowdZone] = []
    @Published var alerts: [CrowdAlert] = []
    @Published var recommendations: [Recommendation] = []
    @Published var incidents: [IncidentReport] = []
    @Published var overallRisk: RiskLevel = .safe
    @Published var predictedCrushInMinutes: Int? = nil
    @Published var isSimulating = false
    @Published var isLoading = true
    @Published var lastUpdate = Date()

    // Stampede likelihood & panic propagation (TechNova risk-prediction requirements)
    @Published var overallStampedeLikelihood: Double = 0
    @Published var stampedePredictions: [StampedePrediction] = []
    @Published var panicStates: [PanicState] = []
    @Published var panicPropagationFronts: [String] = []
    /// Carried across ticks so panic can diffuse along the venue graph over time.
    private var panicIntensityByZoneID: [UUID: Double] = [:]

    // New: flow analysis + prediction
    @Published var flowIssues: [FlowIssue] = []
    let historyTracker = ZoneHistoryTracker()

    // New: evacuation routing
    @Published var activeRoute: EvacuationRoute?

    // New: sensing pipeline
    private let sensorCoordinator = SensorFusionCoordinator()
    var activeSensorDescription: String { sensorCoordinator.activeSourceDescription }

    // New: GenAI incident summaries — on-device Foundation Models when
    // available (iOS 26+/macOS 26+ with Apple Intelligence enabled), falling
    // back to the deterministic template provider otherwise so the feature
    // always works, including in Simulator or on older OS versions.
    @Published var latestSummary: IncidentSummary?
    @Published var isGeneratingSummary = false
    private let summaryProvider: IncidentSummaryProvider = {
        if #available(iOS 26.0, macOS 26.0, *) {
            return FoundationModelsSummaryProvider()
        } else {
            return TemplateSummaryProvider()
        }
    }()

    // New: offline resilience
    let reachability = NetworkReachabilityMonitor()
    private(set) lazy var offlineSync: OfflineSyncManager = {
        OfflineSyncManager(reachability: reachability) { [weak self] report in
            self?.deliverIncident(report)
        }
    }()

    /// Set by CrowdShieldApp once both StateObjects exist. Weak to avoid a
    /// retain cycle (UserSession does not need to know about this service).
    /// Used to read the current IdToken for authenticated backend calls —
    /// syncing is best-effort: if there's no session or a call fails, the
    /// local simulation still works exactly as before (offline-first).
    weak var userSession: UserSession?
    private let apiClient = CrowdShieldAPIClient.shared

    /// Requires a risk/flow-issue condition to persist across consecutive
    /// ticks and enforces a cooldown between repeat alerts for the same
    /// condition — see AlertDebouncer's doc comment for why this exists
    /// (TechNova brief's explicit "false alarm reduction" constraint).
    private let alertDebouncer = AlertDebouncer()

    /// The venue every backend call in this service operates on (Phase 6).
    /// Falls back to the config default defensively — in normal operation
    /// this should always be set by the time any sync call fires, since
    /// VenueSelectionView requires a selection before the main app (and
    /// therefore the simulation loop) is reachable at all.
    private var currentVenueId: String {
        userSession?.selectedVenue?.venueId ?? CrowdShieldConfig.defaultVenueId
    }

    // New: real-time push (Phase 4)
    let realtimeClient = CrowdShieldRealtimeClient()
    /// Recent pushes from other clients (e.g. another Command operator
    /// acknowledging a recommendation), most recent first. Capped so this
    /// doesn't grow unbounded over a long session — it's a live feed, not
    /// a persisted history (DynamoDB is the source of truth for that).
    @Published var recentRealtimeEvents: [RealtimePush] = []
    private let maxRealtimeEvents = 30

    private var timer: AnyCancellable?
    private let updateInterval: TimeInterval = 3.0
    private var previousOverallRisk: RiskLevel = .safe

    // MARK: - Active relief tracking
    //
    // Acknowledging a recommendation in the Command Dashboard is meant to
    // represent a real-world action (opening a gate, redeploying staff, etc.).
    // Previously, acknowledgement only flipped a flag on the Recommendation —
    // it had no effect on the simulated crowd, so density never visibly
    // responded to anything the operator did. This tracks zones currently
    // benefiting from an acknowledged action so the simulation loop can apply
    // a real, decaying relief effect to them.
    private struct ActiveRelief {
        let actionType: Recommendation.ActionType
        let startedAt: Date
        let duration: TimeInterval
    }
    private var activeReliefByZoneName: [String: ActiveRelief] = [:]

    /// How long a single acknowledged action keeps relieving its zone before
    /// the effect fully decays. Chosen so the effect is clearly visible within
    /// a few simulation ticks (3s each) but isn't a permanent fix — matching
    /// how a real crowd would settle gradually, not snap to safe instantly.
    private let reliefDuration: TimeInterval = 45

    // Simulated venue zones (Delhi example coordinates)
    private let baseZones: [(name: String, lat: Double, lon: Double)] = [
        ("Main Entrance Gate A", 28.6155, 77.2075),
        ("Central Plaza", 28.6139, 77.2090),
        ("Stage Area", 28.6125, 77.2105),
        ("Food Court", 28.6148, 77.2112),
        ("Exit Gate B", 28.6120, 77.2070),
        ("Bridge Corridor", 28.6130, 77.2080),
        ("VIP Lane", 28.6150, 77.2095),
        ("North Stand", 28.6160, 77.2090),
        ("South Stand", 28.6115, 77.2090),
        ("East Bottleneck", 28.6139, 77.2115)
    ]

    init() {
        // Brief loading state so UI can show indicators on first launch
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            generateInitialZones()
            generateInitialRecommendations()
            isLoading = false
            lastUpdate = Date()
        }
    }

    func startSimulation() {
        guard !isSimulating else { return }
        isSimulating = true

        timer = Timer.publish(every: updateInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateSimulation()
            }
    }

    func stopSimulation() {
        isSimulating = false
        timer?.cancel()
        timer = nil
    }

    private func generateInitialZones() {
        zones = baseZones.map { base in
            CrowdZone(
                name: base.name,
                coordinate: CLLocationCoordinate2D(latitude: base.lat, longitude: base.lon),
                density: Double.random(in: 1.0...4.5),
                movementSpeed: Double.random(in: 0.3...1.4),
                flowDirection: Double.random(in: 0...360),
                isBottleneck: false,
                riskScore: Double.random(in: 0.1...0.5),
                lastUpdated: Date()
            )
        }
        recalculateOverallRisk(triggerHaptic: false)
    }

    private func updateSimulation() {
        var newAlerts: [CrowdAlert] = []

        for i in zones.indices {
            let change = Double.random(in: -0.6...0.9)
            let relief = reliefFactor(for: zones[i].name)
            // Relief pulls density down proportional to how fresh the acknowledged
            // action is (1.0 = just acknowledged, 0.0 = fully decayed), on top of
            // the normal random walk — so an operator's action visibly and
            // immediately starts bringing a zone's density down, then the effect
            // fades out over `reliefDuration` rather than being permanent.
            let reliefPull = relief * Double.random(in: 1.2...2.2)
            zones[i].density = max(0.5, min(9.0, zones[i].density + change - reliefPull))
            zones[i].movementSpeed = max(0.1, 1.8 - (zones[i].density * 0.18) + Double.random(in: -0.15...0.15))
            zones[i].flowDirection = (zones[i].flowDirection + Double.random(in: -25...25))
                .truncatingRemainder(dividingBy: 360)
            if zones[i].flowDirection < 0 { zones[i].flowDirection += 360 }

            // Relief also directly suppresses bottleneck/risk formation, since a
            // real intervention (e.g. opening an exit) reduces congestion risk
            // even before density fully drops.
            zones[i].isBottleneck = zones[i].density > 5.5 && zones[i].movementSpeed < 0.45 && relief < 0.5

            let densityFactor = min(1.0, zones[i].density / 7.0)
            let speedFactor = zones[i].movementSpeed < 0.5 ? 0.3 : 0.0
            let bottleneckFactor = zones[i].isBottleneck ? 0.25 : 0.0
            let riskReliefDiscount = relief * 0.35
            zones[i].riskScore = max(0.0, min(1.0, densityFactor * 0.7 + speedFactor + bottleneckFactor + Double.random(in: -0.05...0.1) - riskReliefDiscount))
            zones[i].lastUpdated = Date()

            if zones[i].riskScore > 0.75 && Bool.random() {
                let alert = CrowdAlert(
                    title: "High Risk Zone Detected",
                    message: "\(zones[i].name) showing critical density (\(String(format: "%.1f", zones[i].density)) p/m²). Possible crush risk.",
                    severity: zones[i].riskLevel,
                    timestamp: Date(),
                    coordinate: zones[i].coordinate,
                    recommendedAction: zones[i].isBottleneck ? "Open alternate exit & redirect flow" : "Deploy additional security"
                )
                newAlerts.append(alert)
            }
        }

        if !newAlerts.isEmpty {
            alerts.insert(contentsOf: newAlerts, at: 0)
            if alerts.count > 20 { alerts = Array(alerts.prefix(20)) }

            if newAlerts.contains(where: { $0.severity == .critical || $0.severity == .high }) {
                HapticManager.criticalAlert()
            }
        }

        // Sensor fusion: in this build the simulated source is authoritative,
        // but any ready real source (Vision, crowd-sourced) would be blended in
        // here via sensorCoordinator.fusedReadings — the update loop doesn't
        // change when real sensors are attached, only the coordinator's inputs do.
        _ = sensorCoordinator.fusedReadings(for: zones)

        for zone in zones {
            historyTracker.record(zone)
        }
        flowIssues = FlowAnalysisEngine.detectIssues(currentZones: zones, tracker: historyTracker)

        if !flowIssues.isEmpty {
            promoteFlowIssuesToAlertsAndRecommendations()
        }

        // Stampede likelihood + panic propagation across the venue graph
        applyRiskPredictions()

        recalculateOverallRisk(triggerHaptic: true)
        updateRecommendations()
        pruneExpiredRelief()
        lastUpdate = Date()
        syncVenueStateToBackendIfDue()
    }

    private var lastVenueStateSyncAt: Date = .distantPast
    /// Venue-state is a venue-level aggregate in the backend schema (not
    /// per-zone), and ticks run every 3s — syncing every tick would be both
    /// wasteful and unnecessary for a dashboard consumer. 30s keeps the
    /// Command dashboard reasonably current without hammering the API.
    private let venueStateSyncInterval: TimeInterval = 30

    /// Starts the live WebSocket connection so this device receives pushes
    /// for changes made by other clients (e.g. another Command operator's
    /// device). Call once a valid IdToken exists (see UserSession.apply /
    /// CrowdShieldApp). Safe to call again after a token refresh — it just
    /// reconnects with the new token.
    func startRealtimeUpdates() {
        guard let token = userSession?.idToken, !token.isEmpty else { return }
        let venueId = userSession?.selectedVenue?.venueId ?? CrowdShieldConfig.defaultVenueId
        realtimeClient.onPush = { [weak self] push in
            self?.handleRealtimePush(push)
        }
        realtimeClient.connect(idToken: token, venueId: venueId)
    }

    func stopRealtimeUpdates() {
        realtimeClient.disconnect()
    }

    /// Server pushes are informational only — they never mutate local
    /// simulation state directly. The local simulation remains the single
    /// source of truth for this device's own view (matching the brief's
    /// offline-first / network-outage constraint: a lost connection here
    /// only means missing *other* devices' updates, never breaking this
    /// device's own experience). This just surfaces a live feed so the
    /// Command dashboard can show "another operator just did X".
    private func handleRealtimePush(_ push: RealtimePush) {
        recentRealtimeEvents.insert(push, at: 0)
        if recentRealtimeEvents.count > maxRealtimeEvents {
            recentRealtimeEvents.removeLast(recentRealtimeEvents.count - maxRealtimeEvents)
        }
    }

    private func syncVenueStateToBackendIfDue() {
        guard Date().timeIntervalSince(lastVenueStateSyncAt) >= venueStateSyncInterval else { return }
        guard let token = userSession?.idToken, !token.isEmpty else { return }
        lastVenueStateSyncAt = Date()

        let avgDensity = zones.map(\.density).reduce(0, +) / Double(max(zones.count, 1))
        let avgSpeed = zones.map(\.movementSpeed).reduce(0, +) / Double(max(zones.count, 1))
        let hotspots = zones.filter { $0.isBottleneck }.map(\.name)

        // Per-zone detail, matching the fields FoundationModelsSummaryProvider's
        // prompt actually uses — this is what lets the Bedrock summary Lambda
        // (Stage 1) produce a comparable-quality brief server-side, since it
        // has no access to the client's in-memory zone state otherwise.
        let zoneDetails: [[String: Any]] = zones.map { zone in
            [
                "name": zone.name,
                "density": zone.density,
                "riskScore": zone.riskScore,
                "isBottleneck": zone.isBottleneck,
                "stampedeLikelihood": zone.stampedeLikelihood,
                "panicIntensity": zone.panicIntensity,
            ]
        }

        Task {
            do {
                try await apiClient.putVenueState(
                    venueId: currentVenueId,
                    density: avgDensity,
                    movementSpeed: avgSpeed,
                    hotspots: hotspots,
                    zones: zoneDetails,
                    idToken: token
                )
            } catch {
                #if DEBUG
                print("CrowdShield: venue-state sync failed — \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Returns 1.0 for a just-acknowledged action on this zone, linearly
    /// decaying to 0.0 as `reliefDuration` elapses, or 0.0 if no active
    /// relief exists for the zone.
    private func reliefFactor(for zoneName: String) -> Double {
        guard let relief = activeReliefByZoneName[zoneName] else { return 0.0 }
        let elapsed = Date().timeIntervalSince(relief.startedAt)
        guard elapsed < relief.duration else { return 0.0 }
        return 1.0 - (elapsed / relief.duration)
    }

    private func pruneExpiredRelief() {
        let now = Date()
        activeReliefByZoneName = activeReliefByZoneName.filter {
            now.timeIntervalSince($0.value.startedAt) < $0.value.duration
        }
    }

    /// Best-effort match from a recommendation's title/detail to the zone it
    /// concerns, since Recommendation doesn't carry a zone reference directly.
    /// Falls back to matching on zone name substring within the title/detail.
    private func inferZoneName(from recommendation: Recommendation) -> String? {
        zones.first {
            recommendation.title.contains($0.name) || recommendation.detail.contains($0.name)
        }?.name
    }

    private func promoteFlowIssuesToAlertsAndRecommendations() {
        // Every key seen this tick — used to reset streaks for issues that
        // cleared, so "sustained" genuinely means consecutive ticks, not
        // just cumulative occurrences (see AlertDebouncer.resetAbsentKeys).
        var activeKeysThisTick: Set<String> = []

        for issue in flowIssues {
            let key = "flow:\(issue.kind.rawValue):\(issue.zoneName)"
            activeKeysThisTick.insert(key)

            guard alertDebouncer.shouldFire(for: key) else { continue }

            alerts.insert(CrowdAlert(
                title: "\(issue.kind.rawValue) Detected",
                message: issue.detail,
                severity: issue.severity,
                timestamp: Date(),
                coordinate: zones.first(where: { $0.id == issue.zoneID })?.coordinate,
                recommendedAction: recommendedAction(for: issue.kind)
            ), at: 0)

            let recTitle = "\(issue.kind.rawValue): \(issue.zoneName)"
            if !recommendations.contains(where: { $0.title == recTitle }) {
                recommendations.insert(Recommendation(
                    title: recTitle,
                    detail: issue.detail,
                    priority: 1,
                    icon: icon(for: issue.kind),
                    actionType: actionType(for: issue.kind)
                ), at: 0)
            }
        }

        alertDebouncer.resetAbsentKeys(inNamespace: "flow:", currentlyActive: activeKeysThisTick)

        if alerts.count > 20 { alerts = Array(alerts.prefix(20)) }
    }

    private func recommendedAction(for kind: FlowIssueKind) -> String {
        switch kind {
        case .reverseMovement: return "Deploy staff to restore one-way flow immediately"
        case .routeBlockage: return "Open alternate route and clear the blockage"
        case .rapidSurge: return "Redirect incoming visitors away from this zone"
        }
    }

    private func icon(for kind: FlowIssueKind) -> String {
        switch kind {
        case .reverseMovement: return "arrow.triangle.swap"
        case .routeBlockage: return "exclamationmark.octagon.fill"
        case .rapidSurge: return "chart.line.uptrend.xyaxis"
        }
    }

    private func actionType(for kind: FlowIssueKind) -> Recommendation.ActionType {
        switch kind {
        case .reverseMovement: return .redirect
        case .routeBlockage: return .openExit
        case .rapidSurge: return .redeploy
        }
    }

    // MARK: - Evacuation Routing

    func computeSafestRoute(from zoneName: String) {
        activeRoute = EvacuationRoutingEngine.safestRoute(from: zoneName, zones: zones)
    }

    // MARK: - Incident Summary (GenAI)

    /// Tries the Bedrock-backed server summary first (Stage 1) when a valid
    /// session exists, since it has access to richer cross-device context
    /// (other operators' alerts, the full DynamoDB-persisted zone history)
    /// than any single device's local state. Falls back to the on-device
    /// provider chain (FoundationModels or TemplateSummaryProvider) on any
    /// failure — network outage, Bedrock access not yet enabled, etc. —
    /// so this feature never leaves the operator without a summary, matching
    /// the offline-first principle used throughout the rest of the app.
    func generateSummary() async {
        isGeneratingSummary = true
        defer { isGeneratingSummary = false }

        if let token = userSession?.idToken, !token.isEmpty {
            do {
                latestSummary = try await apiClient.postGeneratedSummary(
                    venueId: currentVenueId,
                    idToken: token
                )
                return
            } catch {
                #if DEBUG
                print("CrowdShield: remote summary failed, falling back to on-device — \(error.localizedDescription)")
                #endif
            }
        }

        latestSummary = await summaryProvider.summarize(
            overallRisk: overallRisk,
            zones: zones,
            flowIssues: flowIssues,
            recentAlerts: alerts
        )
    }

    // MARK: - Offline-aware incident delivery

    private func deliverIncident(_ report: IncidentReport) {
        addIncident(report)
        syncIncidentToBackend(report)
    }

    /// Best-effort sync: local simulation state is always updated first
    /// (above), so a failed or missing network call never blocks the UI or
    /// loses the report — it just means the Command dashboard on another
    /// device won't see it until connectivity/auth is restored. This is the
    /// same offline-first guarantee OfflineSyncManager already provides for
    /// queuing; this adds the actual network destination behind it.
    private func syncIncidentToBackend(_ report: IncidentReport) {
        guard let token = userSession?.idToken, !token.isEmpty else { return }
        Task {
            do {
                try await apiClient.postIncident(venueId: currentVenueId, report: report, idToken: token)
            } catch {
                #if DEBUG
                print("CrowdShield: incident sync failed — \(error.localizedDescription)")
                #endif
            }
        }
    }

    private func recalculateOverallRisk(triggerHaptic: Bool) {
        let maxRisk = zones.map(\.riskScore).max() ?? 0
        let criticalCount = zones.filter { $0.riskScore > 0.75 }.count
        let maxStampede = overallStampedeLikelihood
        let maxPanic = zones.map(\.panicIntensity).max() ?? 0

        let newRisk: RiskLevel
        // Stampede likelihood and spreading panic can escalate overall risk
        // even when instantaneous density alone is still moderate.
        if maxRisk > 0.85 || criticalCount >= 2 || maxStampede >= 0.8 || maxPanic >= 0.85 {
            newRisk = .critical
            predictedCrushInMinutes = stampedePredictions.first?.estimatedMinutesToCritical
                ?? Int.random(in: 4...9)
        } else if maxRisk > 0.65 || maxStampede >= 0.55 || maxPanic >= 0.6 {
            newRisk = .high
            predictedCrushInMinutes = stampedePredictions.first?.estimatedMinutesToCritical
                ?? Int.random(in: 10...18)
        } else if maxRisk > 0.4 || maxStampede >= 0.3 || maxPanic >= 0.35 {
            newRisk = .moderate
            predictedCrushInMinutes = nil
        } else {
            newRisk = .safe
            predictedCrushInMinutes = nil
        }

        if triggerHaptic, newRisk != previousOverallRisk, newRisk.sortOrder > previousOverallRisk.sortOrder {
            HapticManager.riskLevelChanged(to: newRisk)
        }

        previousOverallRisk = newRisk
        overallRisk = newRisk
    }

    /// Runs RiskPredictionEngine each tick: writes stampede likelihood and panic
    /// intensity back onto zones, publishes venue-level forecasts, and raises
    /// alerts when likelihood or propagation crosses command thresholds.
    private func applyRiskPredictions() {
        let forecast = RiskPredictionEngine.forecast(
            zones: zones,
            flowIssues: flowIssues,
            tracker: historyTracker,
            previousPanic: panicIntensityByZoneID,
            recentIncidents: Array(incidents.prefix(15))
        )

        overallStampedeLikelihood = forecast.overallStampedeLikelihood
        stampedePredictions = forecast.perZoneStampede
        panicStates = forecast.panicStates
        panicPropagationFronts = forecast.activePropagationFronts

        // Persist panic for the next tick and mirror metrics onto zones for UI/map.
        var nextPanic: [UUID: Double] = [:]
        let panicByID = Dictionary(uniqueKeysWithValues: forecast.panicStates.map { ($0.id, $0) })
        let stampedeByID = Dictionary(uniqueKeysWithValues: forecast.perZoneStampede.map { ($0.id, $0) })

        for i in zones.indices {
            let id = zones[i].id
            if let s = stampedeByID[id] {
                zones[i].stampedeLikelihood = s.likelihood
            }
            if let p = panicByID[id] {
                zones[i].panicIntensity = p.intensity
                nextPanic[id] = p.intensity
            }
        }
        panicIntensityByZoneID = nextPanic

        promoteStampedeAndPanicAlerts(forecast: forecast)
    }

    private func promoteStampedeAndPanicAlerts(forecast: VenueRiskForecast) {
        var activeKeysThisTick: Set<String> = []

        // High stampede likelihood
        if let top = forecast.perZoneStampede.first, top.likelihood >= 0.6 {
            let key = "stampede:\(top.zoneName)"
            activeKeysThisTick.insert(key)

            if alertDebouncer.shouldFire(for: key) {
                let title = "Stampede Likelihood Elevated"
                let drivers = top.primaryDrivers.prefix(3).joined(separator: "; ")
                let etaText = top.estimatedMinutesToCritical.map { " ~\($0) min to critical." } ?? ""
                alerts.insert(CrowdAlert(
                    title: title,
                    message: "\(top.zoneName) stampede likelihood \(Int(top.likelihood * 100))%.\(etaText) Drivers: \(drivers).",
                    severity: top.level,
                    timestamp: Date(),
                    coordinate: zones.first(where: { $0.id == top.id })?.coordinate,
                    recommendedAction: "Open alternate exits, redeploy staff, broadcast calm announcement"
                ), at: 0)
            }
        }

        // Active panic propagation fronts
        for frontName in forecast.activePropagationFronts.prefix(2) {
            guard let state = forecast.panicStates.first(where: { $0.zoneName == frontName }),
                  state.intensity >= 0.45 else { continue }

            let key = "panic:\(frontName)"
            activeKeysThisTick.insert(key)

            guard alertDebouncer.shouldFire(for: key) else { continue }

            let title = "Panic Propagation"
            let hopNames = state.projectedSpread.prefix(3).map(\.zoneName).joined(separator: " → ")
            alerts.insert(CrowdAlert(
                title: title,
                message: "Panic intensity \(Int(state.intensity * 100))% at \(frontName), spreading toward \(hopNames).",
                severity: state.intensity >= 0.7 ? .critical : .high,
                timestamp: Date(),
                coordinate: zones.first(where: { $0.name == frontName })?.coordinate,
                recommendedAction: "Contain with staff cordon and multilingual calm broadcast"
            ), at: 0)

            let recTitle = "Contain panic spread from \(frontName)"
            if !recommendations.contains(where: { $0.title == recTitle }) {
                recommendations.insert(Recommendation(
                    title: recTitle,
                    detail: "Panic propagating toward \(hopNames). Redeploy staff and announce calm instructions.",
                    priority: 1,
                    icon: "waveform.path.ecg",
                    actionType: .announce
                ), at: 0)
            }
        }

        alertDebouncer.resetAbsentKeys(
            inNamespace: "stampede:",
            currentlyActive: activeKeysThisTick.filter { $0.hasPrefix("stampede:") }
        )
        alertDebouncer.resetAbsentKeys(
            inNamespace: "panic:",
            currentlyActive: activeKeysThisTick.filter { $0.hasPrefix("panic:") }
        )

        if alerts.count > 20 { alerts = Array(alerts.prefix(20)) }
    }

    private func generateInitialRecommendations() {
        recommendations = [
            Recommendation(
                title: "Open Exit Gate C",
                detail: "Relieve pressure on Main Entrance and Bridge Corridor",
                priority: 1,
                icon: "door.left.hand.open",
                actionType: .openExit
            ),
            Recommendation(
                title: "Close Entry Gate A temporarily",
                detail: "Density at Gate A exceeds safe threshold",
                priority: 2,
                icon: "door.left.hand.closed",
                actionType: .closeGate
            ),
            Recommendation(
                title: "Deploy 12 officers to East Bottleneck",
                detail: "Critical congestion forming near food court approach",
                priority: 1,
                icon: "person.3.fill",
                actionType: .redeploy
            ),
            Recommendation(
                title: "Broadcast multilingual calm announcement",
                detail: "Hindi + English + regional languages via PA & app",
                priority: 2,
                icon: "megaphone.fill",
                actionType: .announce
            ),
            Recommendation(
                title: "Enforce one-way flow on Bridge Corridor",
                detail: "Reverse movement detected — high collision risk",
                priority: 1,
                icon: "arrow.right.circle.fill",
                actionType: .redirect
            ),
            Recommendation(
                title: "Reconfigure barricades at Central Plaza",
                detail: "Widen pedestrian lanes to reduce crush points",
                priority: 3,
                icon: "rectangle.split.3x1.fill",
                actionType: .barricade
            )
        ]
    }

    private func updateRecommendations() {
        let criticalZones = zones.filter { $0.riskScore > 0.7 }.sorted { $0.riskScore > $1.riskScore }
        guard let top = criticalZones.first else { return }

        // Inject a dynamic recommendation when a new critical bottleneck appears
        if top.isBottleneck {
            let title = "Relieve bottleneck at \(top.name)"
            let exists = recommendations.contains { $0.title == title }
            if !exists {
                let rec = Recommendation(
                    title: title,
                    detail: String(
                        format: "Density %.1f p/m² · speed %.2f m/s — open alternate path & redeploy staff",
                        top.density,
                        top.movementSpeed
                    ),
                    priority: 1,
                    icon: "exclamationmark.triangle.fill",
                    actionType: .redirect
                )
                recommendations.insert(rec, at: 0)
                if recommendations.count > 12 {
                    // Drop oldest acknowledged first, else trim tail
                    if let idx = recommendations.lastIndex(where: { $0.isAcknowledged }) {
                        recommendations.remove(at: idx)
                    } else {
                        recommendations = Array(recommendations.prefix(12))
                    }
                }
            }
        }
    }

    func acknowledgeRecommendation(_ id: UUID, by officer: String = "Command Officer") {
        guard let idx = recommendations.firstIndex(where: { $0.id == id }) else { return }
        recommendations[idx].isAcknowledged = true
        recommendations[idx].acknowledgedAt = Date()
        recommendations[idx].acknowledgedBy = officer

        // This is the actual fix for "the crowd isn't decreasing after taking
        // actions": acknowledging used to only set a flag with no effect on
        // the simulation. Now it registers real, decaying relief on the zone
        // the recommendation concerns, which updateSimulation() applies on
        // every tick until it fully decays.
        if let zoneName = inferZoneName(from: recommendations[idx]) {
            activeReliefByZoneName[zoneName] = ActiveRelief(
                actionType: recommendations[idx].actionType,
                startedAt: Date(),
                duration: reliefDuration
            )
        }

        syncRecommendationAckToBackend(recommendations[idx])
        HapticManager.trigger(.success)
    }

    /// Recommendation writes are Command-only server-side (require_command()
    /// in the Lambda) — if this user isn't in the Command Cognito group, the
    /// call fails with 403 and is silently ignored here, since the local
    /// acknowledgement already happened and that's what the UI reflects.
    private func syncRecommendationAckToBackend(_ recommendation: Recommendation) {
        guard let token = userSession?.idToken, !token.isEmpty else { return }
        Task {
            do {
                try await apiClient.postRecommendationAck(
                    venueId: currentVenueId,
                    action: recommendation.title,
                    reason: recommendation.detail,
                    priority: recommendation.priority <= 1 ? "high" : "medium",
                    idToken: token
                )
            } catch {
                #if DEBUG
                print("CrowdShield: recommendation sync failed — \(error.localizedDescription)")
                #endif
            }
        }
    }

    func unacknowledgeRecommendation(_ id: UUID) {
        guard let idx = recommendations.firstIndex(where: { $0.id == id }) else { return }
        if let zoneName = inferZoneName(from: recommendations[idx]) {
            activeReliefByZoneName.removeValue(forKey: zoneName)
        }
        recommendations[idx].isAcknowledged = false
        recommendations[idx].acknowledgedAt = nil
        recommendations[idx].acknowledgedBy = nil
        HapticManager.trigger(.selection)
    }

    /// Exposes which zones currently have an acknowledged action relieving
    /// them, and how strong that effect currently is (1.0 → 0.0 as it decays),
    /// so the UI can show operators that their action is actually working.
    func activeReliefInfo() -> [(zoneName: String, strength: Double)] {
        activeReliefByZoneName.keys.compactMap { name in
            let strength = reliefFactor(for: name)
            guard strength > 0 else { return nil }
            return (zoneName: name, strength: strength)
        }
    }

    func addIncident(_ report: IncidentReport) {
        incidents.insert(report, at: 0)
        let severity: RiskLevel
        switch report.severity.lowercased() {
        case "critical": severity = .critical
        case "high": severity = .high
        case "low": severity = .safe
        default: severity = .moderate
        }

        let alert = CrowdAlert(
            title: "Citizen Report: \(report.type)",
            message: report.description,
            severity: severity,
            timestamp: Date(),
            coordinate: report.coordinate,
            recommendedAction: "Verify with ground team"
        )
        alerts.insert(alert, at: 0)

        if severity == .critical || severity == .high {
            HapticManager.criticalAlert()
        } else {
            HapticManager.trigger(.warning)
        }
    }

    func clearAlerts() {
        alerts.removeAll()
    }
}
