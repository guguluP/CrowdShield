import SwiftUI

struct CommandDashboardView: View {
    @EnvironmentObject var crowdService: CrowdSimulationService
    
    var body: some View {
        NavigationStack {
            Group {
                if crowdService.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(CrowdShieldTheme.commandAccent)
                        Text("Initializing command feeds…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    dashboardScroll
                }
            }
            .navigationTitle("Command Center")
        }
    }

    private var dashboardScroll: some View {
            ScrollView {
                VStack(spacing: 16) {
                    // Overall Status
                    OverallStatusCard(
                        risk: crowdService.overallRisk,
                        predictedMinutes: crowdService.predictedCrushInMinutes,
                        zoneCount: crowdService.zones.count,
                        criticalCount: crowdService.zones.filter { $0.riskScore > 0.7 }.count,
                        stampedeLikelihood: crowdService.overallStampedeLikelihood,
                        maxPanic: crowdService.zones.map(\.panicIntensity).max() ?? 0
                    )

                    // Live activity — real-time pushes (Phase 4) from other
                    // clients on this venue (e.g. another Command operator's
                    // device, or a citizen's incident report), separate from
                    // this device's own local simulation state. Header always
                    // shown (not gated on having events yet) so the
                    // connection status badge stays visible even right after
                    // sign-in, before any pushes have arrived.
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Live Activity")
                                .font(.headline)
                            Spacer()
                            RealtimeStatusIndicator(state: crowdService.realtimeClient.connectionState)
                        }
                        .padding(.horizontal)

                        if crowdService.recentRealtimeEvents.isEmpty {
                            HStack {
                                Image(systemName: "dot.radiowaves.up.forward")
                                    .foregroundStyle(.secondary)
                                Text("No activity yet — updates from other devices will appear here.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .adaptiveGlassCard(cornerRadius: 12)
                            .padding(.horizontal)
                        } else {
                            ForEach(crowdService.recentRealtimeEvents.prefix(8)) { event in
                                RealtimeEventRow(event: event)
                            }
                        }
                    }

                    // Quick Stats
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatCard(title: "Avg Density", value: averageDensity, icon: "person.3", color: CrowdShieldTheme.publicAccent)
                        StatCard(title: "Bottlenecks", value: "\(bottleneckCount)", icon: "exclamationmark.triangle", color: .orange)
                        StatCard(
                            title: "Stampede Risk",
                            value: "\(Int(crowdService.overallStampedeLikelihood * 100))%",
                            icon: "figure.fall",
                            color: crowdService.overallStampedeLikelihood >= 0.6 ? .red : (crowdService.overallStampedeLikelihood >= 0.35 ? .orange : .green)
                        )
                        StatCard(
                            title: "Panic Fronts",
                            value: "\(crowdService.panicPropagationFronts.count)",
                            icon: "waveform.path.ecg",
                            color: crowdService.panicPropagationFronts.isEmpty ? .green : .purple
                        )
                    }
                    .padding(.horizontal)

                    // Stampede likelihood breakdown
                    if !crowdService.stampedePredictions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Stampede Likelihood")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(crowdService.stampedePredictions.prefix(5)) { pred in
                                StampedePredictionRow(prediction: pred)
                            }
                        }
                    }

                    // Panic propagation
                    let elevatedPanic = crowdService.panicStates.filter { $0.intensity >= 0.25 }
                    if !elevatedPanic.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Panic Propagation")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(elevatedPanic.prefix(5)) { state in
                                PanicStateRow(state: state)
                            }
                        }
                    }

                    // AI Situation Summary
                    IncidentSummaryCard(
                        summary: crowdService.latestSummary,
                        isGenerating: crowdService.isGeneratingSummary,
                        onGenerate: {
                            Task { await crowdService.generateSummary() }
                        }
                    )
                    .padding(.horizontal)

                    // Flow Issues (reverse movement / blockage / surge)
                    if !crowdService.flowIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Flow Anomalies")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(crowdService.flowIssues) { issue in
                                FlowIssueRow(issue: issue)
                            }
                        }
                    }

                    // Active Relief — direct visual confirmation that
                    // acknowledged actions are actually reducing density,
                    // rather than just marking a checkbox with no effect.
                    let activeRelief = crowdService.activeReliefInfo()
                    if !activeRelief.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Actions In Effect")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(activeRelief, id: \.zoneName) { relief in
                                ActiveReliefRow(zoneName: relief.zoneName, strength: relief.strength)
                            }
                        }
                    }

                    // High Risk Zones
                    VStack(alignment: .leading, spacing: 10) {
                        Text("High Risk Zones")
                            .font(.headline)
                            .padding(.horizontal)

                        let highRisk = crowdService.zones.filter { $0.riskScore > 0.5 }.sorted { $0.riskScore > $1.riskScore }
                        if highRisk.isEmpty {
                            HStack {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundStyle(.green)
                                Text("No elevated risk zones right now")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .adaptiveGlassCard(cornerRadius: 12)
                            .padding(.horizontal)
                        } else {
                            ForEach(highRisk) { zone in
                                ZoneRiskRow(zone: zone)
                                    .animation(.easeInOut(duration: 0.4), value: zone.riskScore)
                            }
                        }
                    }

                    // Simulation Control
                    VStack(spacing: 8) {
                        Text("Simulation Control")
                            .font(.headline)

                        HStack(spacing: 16) {
                            Button {
                                if crowdService.isSimulating {
                                    crowdService.stopSimulation()
                                } else {
                                    crowdService.startSimulation()
                                }
                                HapticManager.trigger(.medium)
                            } label: {
                                Label(
                                    crowdService.isSimulating ? "Pause Simulation" : "Resume Simulation",
                                    systemImage: crowdService.isSimulating ? "pause.fill" : "play.fill"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(crowdService.isSimulating ? .orange : .green)
                        }
                    }
                    .padding()
                    .adaptiveGlassCard(cornerRadius: 12)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .crowdShieldScreenBackground(accent: CrowdShieldTheme.commandAccent)
    }

    private var averageDensity: String {
        guard !crowdService.zones.isEmpty else { return "0.0" }
        let avg = crowdService.zones.map(\.density).reduce(0, +) / Double(crowdService.zones.count)
        return String(format: "%.1f", avg)
    }
    
    private var bottleneckCount: Int {
        crowdService.zones.filter(\.isBottleneck).count
    }
}

struct OverallStatusCard: View {
    let risk: RiskLevel
    let predictedMinutes: Int?
    let zoneCount: Int
    let criticalCount: Int
    var stampedeLikelihood: Double = 0
    var maxPanic: Double = 0

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: risk.icon)
                    .font(.system(size: 36))
                    .foregroundStyle(risk.color)
                    .symbolEffect(.pulse, options: .repeating, isActive: risk == .critical || risk == .high)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading) {
                    Text("Overall Venue Risk")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(risk.rawValue.uppercased())
                        .font(.title.bold())
                        .foregroundStyle(risk.color)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: risk)
                }
                Spacer()
            }

            // Stampede + panic metrics row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stampede likelihood")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(Int(stampedeLikelihood * 100))%")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(stampedeLikelihood >= 0.6 ? .red : (stampedeLikelihood >= 0.35 ? .orange : .primary))
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Peak panic")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(Int(maxPanic * 100))%")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(maxPanic >= 0.6 ? .purple : .primary)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if let minutes = predictedMinutes {
                HStack {
                    Image(systemName: "clock.badge.exclamationmark.fill")
                    Text("Estimated time to critical crush: \(minutes) minutes")
                        .font(.subheadline.weight(.medium))
                        .contentTransition(.numericText())
                }
                .foregroundStyle(.white)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack {
                Label("\(zoneCount) zones", systemImage: "square.grid.2x2")
                Spacer()
                Label("\(criticalCount) critical", systemImage: "exclamationmark.octagon")
                    .foregroundStyle(criticalCount > 0 ? .red : .secondary)
                    .contentTransition(.numericText())
            }
            .font(.caption)
        }
        .padding(18)
        .adaptiveGlassCard(cornerRadius: 22, tint: risk.color)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(risk.color.opacity(risk == .critical ? 0.85 : 0.45), lineWidth: risk == .critical ? 2 : 1)
        )
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.45), value: risk)
        .animation(.easeInOut(duration: 0.4), value: predictedMinutes)
        .animation(.easeInOut(duration: 0.35), value: stampedeLikelihood)
        .animation(.easeInOut(duration: 0.35), value: maxPanic)
    }
}

struct StampedePredictionRow: View {
    let prediction: StampedePrediction

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "figure.fall")
                .foregroundStyle(prediction.level.color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(prediction.zoneName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(prediction.likelihood * 100))%")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(prediction.level.color)
                        .contentTransition(.numericText())
                }

                ProgressView(value: prediction.likelihood)
                    .tint(prediction.level.color)

                if !prediction.primaryDrivers.isEmpty {
                    Text(prediction.primaryDrivers.prefix(3).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let eta = prediction.estimatedMinutesToCritical {
                    Label("~\(eta) min to critical if unchecked", systemImage: "clock")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .adaptiveGlassCard(cornerRadius: 12)
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.35), value: prediction.likelihood)
    }
}

struct PanicStateRow: View {
    let state: PanicState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(state.intensity >= 0.6 ? .purple : .orange)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(state.zoneName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(state.intensity * 100))%")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.purple)
                        .contentTransition(.numericText())
                }

                ProgressView(value: state.intensity)
                    .tint(.purple)

                if !state.projectedSpread.isEmpty {
                    let hops = state.projectedSpread.prefix(3).map(\.zoneName).joined(separator: " → ")
                    Text("Spreading toward \(hops)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .adaptiveGlassCard(cornerRadius: 12, tint: .purple)
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.35), value: state.intensity)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.35), value: value)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .adaptiveGlassCard(cornerRadius: 18, tint: color)
    }
}

struct ZoneRiskRow: View {
    let zone: CrowdZone

    var body: some View {
        HStack {
            Circle()
                .fill(zone.riskLevel.color)
                .frame(width: 12, height: 12)
                .shadow(color: zone.riskLevel.color.opacity(0.6), radius: zone.riskScore > 0.75 ? 4 : 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(zone.name)
                    .font(.subheadline.weight(.medium))
                Text("Density \(String(format: "%.1f", zone.density)) • Speed \(String(format: "%.2f", zone.movementSpeed)) m/s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if zone.stampedeLikelihood >= 0.35 || zone.panicIntensity >= 0.25 {
                    Text("Stampede \(Int(zone.stampedeLikelihood * 100))% · Panic \(Int(zone.panicIntensity * 100))%")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(zone.stampedeLikelihood >= 0.6 ? .red : .orange)
                        .monospacedDigit()
                }
            }

            Spacer()

            Text("\(Int(zone.riskScore * 100))%")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(zone.riskLevel.color)
                .contentTransition(.numericText())
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .adaptiveGlassCard(cornerRadius: 10)
        .padding(.horizontal)
    }
}

struct IncidentSummaryCard: View {
    let summary: IncidentSummary?
    let isGenerating: Bool
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("AI Situation Summary", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Button(action: onGenerate) {
                    if isGenerating {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Generate", systemImage: "arrow.clockwise")
                            .font(.caption.bold())
                    }
                }
                .buttonStyle(.bordered)
                .tint(CrowdShieldTheme.publicAccent)
                .disabled(isGenerating)
            }

            if let summary {
                VStack(alignment: .leading, spacing: 8) {
                    Text(summary.headline)
                        .font(.subheadline.bold())
                    Text(summary.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider()
                    Label(summary.recommendedNextStep, systemImage: "arrow.right.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CrowdShieldTheme.publicAccent)
                    Text("Generated \(summary.generatedAt, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("Tap Generate for a plain-language brief of the current situation, ready to read aloud or forward to senior authorities.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .adaptiveGlassCard(cornerRadius: 12)
    }
}

struct FlowIssueRow: View {
    let issue: FlowIssue

    private var icon: String {
        switch issue.kind {
        case .reverseMovement: return "arrow.triangle.swap"
        case .routeBlockage: return "exclamationmark.octagon.fill"
        case .rapidSurge: return "chart.line.uptrend.xyaxis"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(issue.severity.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.kind.rawValue)
                    .font(.subheadline.weight(.semibold))
                Text(issue.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .adaptiveGlassCard(cornerRadius: 10)
        .padding(.horizontal)
    }
}

struct ActiveReliefRow: View {
    let zoneName: String
    /// 1.0 = just acknowledged, decaying toward 0.0 as the effect wears off.
    let strength: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: strength)

            VStack(alignment: .leading, spacing: 4) {
                Text(zoneName)
                    .font(.subheadline.weight(.medium))
                Text("Relief active — density trending down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ProgressView(value: strength)
                    .tint(.green)
                    .frame(height: 3)
            }

            Spacer()

            Text("\(Int(strength * 100))%")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.green)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .adaptiveGlassCard(cornerRadius: 14, tint: .green)
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.4), value: strength)
    }
}

#Preview {
    CommandDashboardView()
        .environmentObject(CrowdSimulationService())
}

